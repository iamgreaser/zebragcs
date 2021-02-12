import gcsglobals

proc parseOnBlock(sps: ScriptParseState): ScriptNode
proc parseCodeBlock(sps: ScriptParseState, endKind: ScriptTokenKind): seq[ScriptNode]
proc parseRoot(sps: ScriptParseState, endKind: ScriptTokenKind): ScriptNode

import streams
import strformat
import strscans
import strutils
import tables

const maxPeekDist = 100

proc `$`(x: ScriptVal): string =
  case x.kind
  of svkBool: &"BoolV({x.boolVal})"
  of svkDir: &"DirV({x.dirValX}, {x.dirValY})"
  of svkInt: &"IntV({x.intVal})"
  of svkPos: &"PosV({x.posValX}, {x.posValY})"

proc `$`(x: ScriptToken): string =
  case x.kind
  of stkBraceClosed: return "}T"
  of stkBraceOpen: return "{T"
  of stkEof: return "EofT"
  of stkEol: return "EolT"
  of stkGlobalVar: return &"GlobalT({x.globalName})"
  of stkInt: return &"IntT({x.intVal})"
  of stkParamVar: return &"ParamT({x.paramName})"
  of stkParenClosed: return ")T"
  of stkParenOpen: return "(T"
  of stkWord: return &"WordT({x.strVal})"

proc `$`(x: ScriptNode): string =
  case x.kind
  of snkAssign: return &"Assign({x.assignType}: {x.assignDstExpr} <:- {x.assignSrcExpr})"
  of snkBroadcast: return &"Broadcast({x.broadcastEventName})"
  of snkConst: return &"Const({x.constVal})"
  of snkDie: return &"Die"
  of snkFunc: return &"Func:{x.funcType}({x.funcArgs})"
  of snkGlobalDef: return &"GlobalDef(${x.globalDefName}: {x.globalDefType})"
  of snkGlobalVar: return &"GlobalVar(${x.globalVarName})"
  of snkGoto: return &"Goto({x.gotoStateName})"
  of snkIfBlock: return &"If({x.ifTest}, then {x.ifBody}, else {x.ifElse})"
  of snkMove: return &"Move({x.moveDirExpr})"
  of snkOnEventBlock: return &"OnEvent({x.onEventName}: {x.onEventBody})"
  of snkOnStateBlock: return &"OnState({x.onStateName}: {x.onStateBody})"
  of snkParamDef: return &"ParamDef(@{x.paramDefName}: {x.paramDefType} := {x.paramDefInitValue})"
  of snkParamVar: return &"ParamVar(@{x.paramVarName})"
  of snkRootBlock: return &"Root({x.rootBody})"
  of snkSend: return &"Send({x.sendEventName} -> {x.sendPos})"
  of snkSleep: return &"Sleep({x.sleepTimeExpr})"
  of snkSpawn: return &"Spawn({x.spawnEntityName} -> {x.spawnPos}: {x.spawnBody} else {x.spawnElse})"

proc `$`(x: ScriptGlobalBase): string =
  &"Global({x.varType})"
proc `$`(x: ScriptParamBase): string =
  &"Param({x.varType} := {x.varDefault})"
proc `$`(x: ScriptStateBase): string =
  &"State({x.stateBody})"
proc `$`(x: ScriptEventBase): string =
  &"Event({x.eventBody})"

proc `$`(x: ScriptSharedExecState): string =
  &"SharedExecState(globals={x.globals})"

proc `$`(x: ScriptExecBase): string =
  &"ExecBase(initState={x.initState}, globals={x.globals}, params={x.params}, states={x.states}, events={x.events})"

proc `$`(x: ScriptContinuation): string =
  &"Continuation({x.codePc} in {x.codeBlock})"

proc `$`(x: ScriptExecState): string =
  #&"ExecState(execBase={x.execBase}, activeState={x.activeState}, continuations={x.continuations})"
  #&"ExecState(activeState={x.activeState}, continuations={x.continuations})"
  &"ExecState(activeState={x.activeState}, alive={x.alive})"

proc `$`(x: Entity): string =
  &"Entity(pos=({x.x}, {x.y}), execState={x.execState}, params={x.params}, alive={x.alive})"

proc `$`(x: Board): string =
  &"Board(entities={x.entities}, share={x.share})"

proc asBool(x: ScriptVal): bool =
  case x.kind
  of svkBool: x.boolVal
  else:
    raise newException(ScriptExecError, &"Expected bool, got {x} instead")

proc asInt(x: ScriptVal): int =
  case x.kind
  of svkInt: x.intVal
  else:
    raise newException(ScriptExecError, &"Expected int, got {x} instead")

proc defaultScriptVal(kind: ScriptValKind): ScriptVal =
  case kind
  of svkBool: ScriptVal(kind: kind, boolVal: false)
  of svkDir: ScriptVal(kind: kind, dirValX: 0, dirValY: 0)
  of svkInt: ScriptVal(kind: kind, intVal: 0)
  of svkPos: ScriptVal(kind: kind, posValX: 0, posValY: 0) # TODO: Consider making pos not have a default, and throw an exception instead --GM

proc resolveExpr(execState: ScriptExecState, expr: ScriptNode): ScriptVal =
  case expr.kind
  of snkConst:
    return expr.constVal

  of snkFunc:
    case expr.funcType

    of sftThisPos:
      var entity = execState.entity
      assert entity != nil
      return ScriptVal(kind: svkPos, posValX: entity.x, posValY: entity.y)

    of sftEq, sftNe:
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var v1 = execState.resolveExpr(expr.funcArgs[1])
      var iseq: bool = case v0.kind
        of svkBool:
          v1.kind == svkBool and v0.boolVal == v1.boolVal
        of svkDir:
          v1.kind == svkDir and v0.dirValX == v1.dirValX and v0.dirValY == v1.dirValY
        else:
          raise newException(ScriptExecError, &"Unhandled bool kind {v0.kind}")
      return ScriptVal(kind: svkBool, boolVal: (iseq == (expr.funcType == sftEq)))

    of sftLt, sftLe, sftGt, sftGe:
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0]).asInt()
      var v1 = execState.resolveExpr(expr.funcArgs[1]).asInt()
      var b0 = case expr.funcType
        of sftLt: v0 < v1
        of sftLe: v0 <= v1
        of sftGt: v0 > v1
        of sftGe: v0 >= v1
        else:
          raise newException(ScriptExecError, &"EDOOFUS: ScriptFuncType unknown for {expr}!")
      return ScriptVal(kind: svkBool, boolVal: b0)

    else:
      raise newException(ScriptExecError, &"Unhandled func kind {expr.funcType} for expr {expr}")

  of snkGlobalVar:
    var k0 = expr.globalVarName
    var share = execState.share
    assert share != nil
    var d0 = try:
        execState.execBase.globals[k0]
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared global \"${k0}\" (TODO: make sure the types get synced and verified properly! --GM)")
    var v0: ScriptVal = try:
        share.globals[k0]
      except KeyError:
        var vd = defaultScriptVal(d0.varType)
        share.globals[k0] = vd
        vd
    return v0

  of snkParamVar:
    var k0 = expr.paramVarName
    var d0 = try:
        execState.execBase.params[k0]
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared parameter \"@{k0}\"")
    var v0: ScriptVal = try:
        execState.entity.params[k0]
      except KeyError:
        var vd = execState.resolveExpr(d0.varDefault)
        execState.entity.params[k0] = vd
        vd
    return v0

  else:
    raise newException(ScriptExecError, &"Unhandled expr kind {expr.kind}")

proc newScriptParseState(strm: Stream): ScriptParseState =
  ScriptParseState(
    strm: strm,
    row: 1, col: 1,
  )

proc newScriptSharedExecState(): ScriptSharedExecState =
  ScriptSharedExecState(
    globals: initTable[string, ScriptVal](),
  )

proc newBoard(share: ScriptSharedExecState): Board =
  Board(
    share: share,
    entities: @[],
  )

proc getEntityType(share: ScriptSharedExecState, entityName: string): ScriptExecBase =
  share.entityTypes[entityName]

proc canAddEntityToGridPos(board: Board, entity: Entity, x: int, y: int): bool =
  if not (x >= 0 and x < 60 and y >= 0 and y < 25): # TODO: Put width/height into the Board --GM
    false
  else:
    true

proc addEntityToGrid(board: Board, entity: Entity) =
  assert board.canAddEntityToGridPos(entity, entity.x, entity.y)
  board.grid[entity.y][entity.x].add(entity)

proc removeEntityFromGrid(board: Board, entity: Entity) =
  var gridseq = board.grid[entity.y][entity.x]
  var i: int = 0
  while i < gridseq.len:
    if gridseq[i] == entity:
      gridseq.delete(i)
    else:
      i += 1
    
  board.grid[entity.y][entity.x] = gridseq
  discard

proc newEntity(board: Board, entityType: string, x, y: int): Entity =
  var share = board.share
  assert share != nil
  var execBase = share.getEntityType(entityType)
  var execState = ScriptExecState(
    execBase: execBase,
    activeState: execBase.initState,
    entity: nil,
    share: share,
    sleepTicksLeft: 0,
    alive: true,
  )
  var entity = Entity(
    board: board,
    x: x, y: y,
    execState: execState,
    params: Table[string, ScriptVal](),
    alive: true,
  )
  execState.entity = entity
  # Initialise!
  for k0, v0 in execBase.params.pairs():
    entity.params[k0] = execState.resolveExpr(v0.varDefault)

  # Now attempt to see if we can add it
  if board.canAddEntityToGridPos(entity, entity.x, entity.y):
    # Yes - add and return it
    board.addEntityToGrid(entity)
    board.entities.add(entity)
    entity
  else:
    # No - invalidate and return nil
    entity.alive = false
    execState.alive = false
    nil
    

proc canMoveTo(entity: Entity, x: int, y: int): bool =
  var board = entity.board
  if board == nil:
    false
  elif x == entity.x and y == entity.y:
    false
  else:
    board.canAddEntityToGridPos(entity, x, y)

proc moveTo(entity: Entity, x: int, y: int): bool =
  var canMove = entity.canMoveTo(x, y)
  if canMove:
    var board = entity.board
    assert board != nil
    if x != entity.x or y != entity.y:
      board.removeEntityFromGrid(entity)
      entity.x = x
      entity.y = y
      board.addEntityToGrid(entity)
    true
  else:
    false

proc moveBy(entity: Entity, dx: int, dy: int): bool =
  entity.moveTo(entity.x + dx, entity.y + dy)

proc skipBytes(sps: ScriptParseState, count: int) =
  var skipped = sps.strm.readstr(count)
  for c in skipped:
    if c == '\n':
      sps.col = 1
      sps.row += 1
    elif c == '\r':
      raise newException(ScriptParseError, &"unexpected CR character at {sps.row}:{sps.col}, stop using Windows newlines")
    elif c == '\t':
      raise newException(ScriptParseError, &"unexpected tab character at {sps.row}:{sps.col}")
    else:
      sps.col += 1

proc newScriptParseError(sps: ScriptParseState, message: string): ref ScriptParseError =
  newException(ScriptParseError, &"{sps.row}:{sps.col}: {message}")

proc readTokenDirect(sps: ScriptParseState): ScriptToken =
  var s = peekStr(sps.strm, maxPeekDist)
  var mid, post: string
  var midInt: int

  # Skip comments
  if scanf(s, "$s#$*", post):
    skipBytes(sps, s.len - post.len)
    s = peekStr(sps.strm, maxPeekDist)
    if scanf(s, "$*\n$*", mid, post):
      echo &"Comment: [#{mid}]"
      skipBytes(sps, s.len - post.len)
      return ScriptToken(kind: stkEol)
    else:
      skipBytes(sps, s.len)
      s = peekStr(sps.strm, maxPeekDist)
      if s == "":
        return ScriptToken(kind: stkEof)
      else:
        raise newScriptParseError(sps, &"Line after comment too long")

  if scanf(s, "$*\n$s$*", mid, post) and scanf(mid, "$s$."):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkEol)
  elif scanf(s, "$s$i$*", midInt, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkInt, intVal: midInt)
  elif scanf(s, "$s$$$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkGlobalVar, globalName: mid)
  elif scanf(s, "$s@$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkParamVar, paramName: mid)
  elif scanf(s, "$s$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkWord, strVal: mid)
  elif scanf(s, "$s{$*", post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkBraceOpen)
  elif scanf(s, "$s}$*", post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkBraceClosed)
  elif s == "":
    return ScriptToken(kind: stkEof)
  else:
    #raise newScriptParseError(sps, &"Invalid token from \"{s}\"")
    raise newScriptParseError(sps, &"Invalid token")

proc readToken(sps: ScriptParseState): ScriptToken =
  var tok = sps.readTokenDirect()
  #echo &"Token: {tok}"
  return tok

proc readExpectedToken(sps: ScriptParseState, kind: ScriptTokenKind): ScriptToken =
  var tok = sps.readToken()
  if tok.kind != kind:
    raise newScriptParseError(sps, &"Expected {kind} token, got {tok} instead")
  else:
    return tok

proc expectToken(sps: ScriptParseState, kind: ScriptTokenKind) =
  var tok = sps.readToken()
  if tok.kind != kind:
    raise newScriptParseError(sps, &"Expected {kind} token, got {tok} instead")

proc readKeywordToken(sps: ScriptParseState): string =
  var tok = sps.readToken()
  if tok.kind == stkWord:
    return tok.strVal.toLowerAscii()
  else:
    raise newScriptParseError(sps, &"Expected keyword token, got {tok} instead")

proc readVarTypeKeyword(sps: ScriptParseState): ScriptValKind =
  var varTypeName = sps.readKeywordToken()
  case varTypeName
  of "bool": svkBool
  of "dir": svkDir
  of "int": svkInt
  of "pos": svkPos
  else:
    raise newScriptParseError(sps, &"Expected type keyword, got \"{varTypeName}\" instead")

proc readGlobalName(sps: ScriptParseState): string =
  sps.readExpectedToken(stkGlobalVar).globalName

proc readParamName(sps: ScriptParseState): string =
  sps.readExpectedToken(stkParamVar).paramName

proc parseExpr(sps: ScriptParseState): ScriptNode =
  var tok = sps.readToken()
  case tok.kind
  of stkInt: return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkInt, intVal: tok.intVal))
  of stkGlobalVar: return ScriptNode(kind: snkGlobalVar, globalVarName: tok.globalName)
  of stkParamVar: return ScriptNode(kind: snkParamVar, paramVarName: tok.paramName)
  of stkWord:
    case tok.strVal.toLowerAscii()
    of "false": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: false))
    of "true": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: true))

    of "i", "idle": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: 0))
    of "n", "north": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: -1))
    of "s", "south": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: +1))
    of "w", "west": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: -1, dirValY: 0))
    of "e", "east": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: +1, dirValY: 0))

    of "cw": return ScriptNode(kind: snkFunc, funcType: sftCw, funcArgs: @[sps.parseExpr()])
    of "opp": return ScriptNode(kind: snkFunc, funcType: sftOpp, funcArgs: @[sps.parseExpr()])
    of "ccw": return ScriptNode(kind: snkFunc, funcType: sftCcw, funcArgs: @[sps.parseExpr()])

    of "eq": return ScriptNode(kind: snkFunc, funcType: sftEq, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "ne": return ScriptNode(kind: snkFunc, funcType: sftNe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "lt": return ScriptNode(kind: snkFunc, funcType: sftLt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "le": return ScriptNode(kind: snkFunc, funcType: sftLe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "gt": return ScriptNode(kind: snkFunc, funcType: sftGt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "ge": return ScriptNode(kind: snkFunc, funcType: sftGe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])

    of "thispos": return ScriptNode(kind: snkFunc, funcType: sftThispos, funcArgs: @[])

    else:
      raise newScriptParseError(sps, &"Expected expression, got {tok} instead")
  else:
    raise newScriptParseError(sps, &"Expected expression, got {tok} instead")

proc parseEolOrElse(sps: ScriptParseState): seq[ScriptNode] =
  var tok = sps.readToken()
  if tok.kind == stkEol:
    return @[]
  elif tok.kind == stkWord:
    case tok.strVal.toLowerAscii()
    of "else":
      sps.expectToken(stkBraceOpen)
      sps.expectToken(stkEol)
      return sps.parseCodeBlock(stkBraceClosed)
    else:
      raise newScriptParseError(sps, &"Expected EOL or \"else\" keyword, got {tok} instead")
  else:
    raise newScriptParseError(sps, &"Expected EOL or \"else\" keyword, got {tok} instead")

proc parseOnBlock(sps: ScriptParseState): ScriptNode =
  var typeName = sps.readKeywordToken()
  case typeName

  of "event":
    var eventName = sps.readKeywordToken()
    sps.expectToken(stkBraceOpen)
    sps.expectToken(stkEol)
    return ScriptNode(
      kind: snkOnEventBlock,
      onEventName: eventName,
      onEventBody: sps.parseCodeBlock(stkBraceClosed),
    )

  of "state":
    var stateName = sps.readKeywordToken()
    sps.expectToken(stkBraceOpen)
    sps.expectToken(stkEol)
    return ScriptNode(
      kind: snkOnStateBlock,
      onStateName: stateName,
      onStateBody: sps.parseCodeBlock(stkBraceClosed),
    )

  else:
    raise newScriptParseError(sps, &"Unexpected keyword \"{typeName}\" after \"on\" keyword")

proc parseCodeBlock(sps: ScriptParseState, endKind: ScriptTokenKind): seq[ScriptNode] =
  var nodes: seq[ScriptNode] = @[]
  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEol: discard
    of stkWord:
      case tok.strVal.toLowerAscii()

      of "goto":
        var stateName = sps.readKeywordToken()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkGoto,
          gotoStateName: stateName,
        ))

      of "broadcast":
        var eventName = sps.readKeywordToken()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkBroadcast,
          broadcastEventName: eventName,
        ))

      of "dec", "fdiv", "inc", "mul", "set":
        var assignType = case tok.strVal.toLowerAscii()
        of "dec": satDec
        of "fdiv": satFDiv
        of "inc": satInc
        of "mul": satMul
        of "set": satSet
        else:
          # SHOULD NOT REACH HERE!
          raise newScriptParseError(sps, &"EDOOFUS: ScriptAssignType unknown for {tok}!")

        var dstExpr = sps.parseExpr()
        var srcExpr = sps.parseExpr()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkAssign,
          assignType: assignType,
          assignDstExpr: dstExpr,
          assignSrcExpr: srcExpr,
        ))

      of "die":
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkDie,
        ))

      of "if":
        var ifTest = sps.parseExpr()
        sps.expectToken(stkBraceOpen)
        nodes.add(ScriptNode(
          kind: snkIfBlock,
          ifTest: ifTest,
          ifBody: sps.parseCodeBlock(stkBraceClosed),
          ifElse: sps.parseEolOrElse(),
        ))

      of "move":
        var dirExpr = sps.parseExpr()
        nodes.add(ScriptNode(
          kind: snkMove,
          moveDirExpr: dirExpr,
          moveElse: sps.parseEolOrElse(),
        ))

      of "send":
        var posExpr = sps.parseExpr()
        var eventName = sps.readKeywordToken().toLowerAscii()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkSend,
          sendEventName: eventName,
          sendPos: posExpr,
        ))

      of "sleep":
        var timeExpr = sps.parseExpr()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkSleep,
          sleepTimeExpr: timeExpr,
        ))

      of "spawn":
        var posExpr = sps.parseExpr()
        var entityName = sps.readKeywordToken().toLowerAscii()
        sps.expectToken(stkBraceOpen)
        sps.expectToken(stkEol)

        var bodyExpr: seq[ScriptNode] = @[]
        while true:
          var tok = sps.readToken()
          case tok.kind
          of stkBraceClosed: break # Exit here.
          of stkEol: discard
          of stkWord:
            case tok.strVal.toLowerAscii()
            of "set":
              var dstExpr = sps.parseExpr()
              if dstExpr.kind != snkParamVar:
                raise newScriptParseError(sps, &"Expected param in spawn block set, got {dstExpr} instead")
              var srcExpr = sps.parseExpr()
              bodyExpr.add(ScriptNode(
                kind: snkAssign,
                assignType: satSet,
                assignDstExpr: dstExpr,
                assignSrcExpr: srcExpr,
              ))
            else:
              raise newScriptParseError(sps, &"Unexpected spawn block keyword {tok}")
          else:
            raise newScriptParseError(sps, &"Unexpected token {tok}")

        nodes.add(ScriptNode(
          kind: snkSpawn,
          spawnEntityName: entityName,
          spawnPos: posExpr,
          spawnBody: bodyExpr,
          spawnElse: sps.parseEolOrElse(),
        ))

      else:
        raise newScriptParseError(sps, &"Unexpected word token \"{tok.strval}\"")
    else:
      if tok.kind == endKind:
        return nodes
      else:
        raise newScriptParseError(sps, &"Unexpected token {tok}")

proc parseRoot(sps: ScriptParseState, endKind: ScriptTokenKind): ScriptNode =
  var nodes: seq[ScriptNode] = @[]
  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEol: discard
    of stkWord:
      case tok.strVal.toLowerAscii()

      of "on":
        nodes.add(sps.parseOnBlock())

      of "global":
        var varType = sps.readVarTypeKeyword()
        var varName = sps.readGlobalName()
        nodes.add(ScriptNode(
          kind: snkGlobalDef,
          globalDefType: varType,
          globalDefName: varName,
        ))

      of "param":
        var varType = sps.readVarTypeKeyword()
        var varName = sps.readParamName()
        var valueNode = sps.parseExpr()

        nodes.add(ScriptNode(
          kind: snkParamDef,
          paramDefType: varType,
          paramDefName: varName,
          paramDefInitValue: valueNode,
        ))

      else:
        raise newScriptParseError(sps, &"Unexpected word token \"{tok.strval}\"")
    else:
      if tok.kind == endKind:
        return ScriptNode(
          kind: snkRootBlock,
          rootBody: nodes,
        )
      else:
        raise newScriptParseError(sps, &"Unexpected token {tok}")

proc compileRoot(node: ScriptNode): ScriptExecBase =
  var execBase = ScriptExecBase(
    globals: initTable[string, ScriptGlobalBase](),
    params: initTable[string, ScriptParamBase](),
    states: initTable[string, ScriptStateBase](),
    events: initTable[string, ScriptEventBase](),
  )

  if node.kind != snkRootBlock:
    raise newException(ScriptCompileError, &"EDOOFUS: compileRoot needs a root, not kind {node.kind}")

  for node in node.rootBody:
    case node.kind
    of snkGlobalDef:
      execBase.globals[node.globalDefName] = ScriptGlobalBase(
        varType: node.globalDefType,
      )

    of snkParamDef:
      execBase.params[node.paramDefName] = ScriptParamBase(
        varType: node.paramDefType,
        varDefault: node.paramDefInitValue,
      )

    of snkOnStateBlock:
      if execBase.initState == "":
        execBase.initState = node.onStateName

      execBase.states[node.onStateName] = ScriptStateBase(
        stateBody: node.onStateBody,
      )

    of snkOnEventBlock:
      execBase.events[node.onEventName] = ScriptEventBase(
        eventBody: node.onEventBody,
      )

    else:
      raise newException(ScriptCompileError, &"Unhandled root node kind {node.kind}")
    #raise newException(ScriptCompileError, &"TODO: Compile things")

  # Validate a few things
  if execBase.initState == "":
    raise newException(ScriptCompileError, &"No states defined - define something using \"on state\"!")

  # TODO: Validate state names

  return execBase

proc loadEntityType(share: ScriptSharedExecState, entityName: string, strm: Stream) =
  var sps = newScriptParseState(strm)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot()
  #echo &"exec base: {execBase}\n"
  share.entityTypes[entityName] = execBase

proc loadEntityTypeFromFile(share: ScriptSharedExecState, entityName: string, fname: string) =
  var strm = newFileStream(fname, fmRead)
  try:
    share.loadEntityType(entityName, strm)
  finally:
    strm.close()

proc tickContinuations(execState: ScriptExecState) =
  while execState.continuations.len >= 1:
    var cont = execState.continuations.pop()
    while cont.codePc < cont.codeBlock.len:
      var nodePc = cont.codePc
      var node: ScriptNode = cont.codeBlock[nodePc]
      cont.codePc += 1

      case node.kind

      of snkAssign:
        var assignType = node.assignType
        var assignDstExpr = node.assignDstExpr
        var assignDst = execState.resolveExpr(node.assignDstExpr)
        var assignSrc = execState.resolveExpr(node.assignSrcExpr)
        var assignResult: ScriptVal = case assignType
          of satSet: assignSrc
          of satDec: ScriptVal(kind: svkInt, intVal: assignDst.asInt() - assignSrc.asInt())
          else:
            raise newException(ScriptExecError, &"Unhandled assignment type {assignType}")

        case assignDstExpr.kind
        of snkGlobalVar:
          var share = execState.share
          assert share != nil
          # TODO: Confirm types --GM
          share.globals[assignDstExpr.globalVarName] = assignResult

        of snkParamVar:
          var entity = execState.entity
          assert entity != nil
          # TODO: Confirm types --GM
          entity.params[assignDstExpr.paramVarName] = assignResult

        else:
          raise newException(ScriptExecError, &"Unhandled assignment destination {assignDstExpr}")

      of snkDie:
        var entity = execState.entity
        assert entity != nil
        execState.alive = false;
        entity.alive = false;
        execState.continuations = @[]
        return

      of snkGoto:
        var stateName: string = node.gotoStateName
        execState.activeState = stateName
        execState.continuations = @[]
        return

      of snkIfBlock:
        var test = execState.resolveExpr(node.ifTest)
        var body =
          if test.asBool():
            node.ifBody
          else:
            node.ifElse
        execState.continuations.add(cont)
        cont = ScriptContinuation(codeBlock: body, codePc: 0)

      of snkMove:
        var moveDir = execState.resolveExpr(node.moveDirExpr)
        if moveDir.kind != svkDir:
          raise newException(ScriptExecError, &"Expected dir, got {moveDir} instead")

        var entity = execState.entity
        assert entity != nil
        var didMove = entity.moveBy(
          moveDir.dirValX,
          moveDir.dirValY,
        )

        if not didMove:
          var body = node.moveElse
          execState.continuations.add(cont)
          cont = ScriptContinuation(codeBlock: body, codePc: 0)

      of snkSend:
        var eventName: string = node.sendEventName
        var dirOrPos = execState.resolveExpr(node.sendPos)
        var pos = case dirOrPos.kind:
          of svkDir:
            var entity = execState.entity
            assert entity != nil
            ScriptVal(kind: svkPos,
              posValX: entity.x + dirOrPos.dirValX,
              posValY: entity.y + dirOrPos.dirValY,
            )
          of svkPos: dirOrPos
          else:
            raise newException(ScriptExecError, &"Expected dir or pos, got {dirOrPos} instead")
        # TODO: Actually send event --GM
        echo &"TODO: Send event {eventName} to ({pos.posValX}, {pos.posValY})"

      of snkSleep:
        var sleepTime = execState.resolveExpr(node.sleepTimeExpr).asInt()
        if sleepTime >= 1:
          execState.sleepTicksLeft = sleepTime
          execState.continuations.add(cont)
          return

      of snkSpawn:
        var entityName: string = node.spawnEntityName
        var dirOrPos = execState.resolveExpr(node.spawnPos)
        var spawnBody = node.spawnBody
        var pos = case dirOrPos.kind:
          of svkDir:
            var entity = execState.entity
            assert entity != nil
            ScriptVal(kind: svkPos,
              posValX: entity.x + dirOrPos.dirValX,
              posValY: entity.y + dirOrPos.dirValY,
            )
          of svkPos: dirOrPos
          else:
            raise newException(ScriptExecError, &"Expected dir or pos, got {dirOrPos} instead")

        var srcEntity = execState.entity
        assert srcEntity != nil
        var board = srcEntity.board
        assert board != nil

        var newEntity = board.newEntity(entityName, pos.posValX, pos.posValY)
        if newEntity == nil:
          execState.continuations.add(cont)
          cont = ScriptContinuation(codeBlock: node.spawnElse, codePc: 0)
        else:
          for spawnNode in spawnBody:
            case spawnNode.kind
            of snkAssign:
              var spawnNodeDstExpr = spawnNode.assignDstExpr
              var spawnNodeSrc = execState.resolveExpr(spawnNode.assignSrcExpr)
              case spawnNode.assignType
              of satSet:
                case spawnNodeDstExpr.kind
                of snkParamVar:
                  # TODO: Confirm types --GM
                  newEntity.params[spawnNodeDstExpr.paramVarName] = spawnNodeSrc
                else:
                  raise newException(ScriptExecError, &"Unhandled spawn assignment destination {spawnNodeDstExpr}")
              else:
                raise newException(ScriptExecError, &"Unhandled spawn statement/block kind {spawnNode}")
            else:
              raise newException(ScriptExecError, &"Unhandled spawn statement/block kind {spawnNode}")

      else:
        raise newException(ScriptExecError, &"Unhandled statement/block kind {node.kind}")

    assert cont.codePc == cont.codeBlock.len

proc tick(execState: ScriptExecState) =
  var execBase = execState.execBase

  # Handle sleep first
  var didSleep = if execState.sleepTicksLeft >= 1:
      execState.sleepTicksLeft -= 1
      if execState.sleepTicksLeft >= 1:
        return
      true
    else:
      false

  # If this is dead then we don't care. Drain all continuations.
  if not execState.alive:
    execState.continuations = @[]
    return

  # If we actually slept, then the next state wrap is instantaneous.
  if didSleep:
    execState.tickContinuations()
    if execState.continuations.len >= 1:
      return
    if execState.sleepTicksLeft >= 1:
      return
    
  if execState.continuations.len < 1:
    var activeState = execState.activeState
    var stateBlock = execBase.states[activeState]
    execState.continuations.add(
      ScriptContinuation(
        codeBlock: stateBlock.stateBody,
        codePc: 0,
      )
    )

  execState.tickContinuations()

proc tickEvent(execState: ScriptExecState, eventName: string) =
  var execBase = execState.execBase
  var eventBlock = try:
      execBase.events[eventName]
    except KeyError:
      return # If we don't have a handler for this event, then ignore it.

  # Push a continuation and tick away
  execState.continuations.add(
    ScriptContinuation(
      codeBlock: eventBlock.eventBody,
      codePc: 0,
    )
  )
  execState.tickContinuations()

proc tick(entity: Entity) =
  entity.execState.tick()

proc tickEvent(entity: Entity, eventName: string) =
  entity.execState.tickEvent(eventName)

proc tick(board: Board) =
  var entitiesCopy: seq[Entity] = @[]
  for entity in board.entities:
    entitiesCopy.add(entity)
  for entity in entitiesCopy:
    entity.execState.tick()

  # Remove dead entities
  entitiesCopy = @[]
  for entity in board.entities:
    if entity.alive:
      entitiesCopy.add(entity)
    else:
      board.removeEntityFromGrid(entity)
  board.entities = entitiesCopy

proc main() =
  var share = newScriptSharedExecState()

  share.loadEntityTypeFromFile("player", "scripts/player.script")
  share.loadEntityTypeFromFile("bullet", "scripts/bullet.script")

  var board = newBoard(share)
  var entity = board.newEntity(
    "player",
    30, 12,
  )
  echo &"board: {board}\n"
  echo &"entity: {entity}\n"
  var ticksLeft: int = 40
  var ticksDone: int = 0
  while entity.alive and ticksLeft > 0:
    case ticksDone
    of 14: entity.tickEvent("enemyshot")
    of 17: entity.tickEvent("pressshift")
    of 18: entity.tickEvent("typeup")
    of 20: entity.tickEvent("typeup")
    of 22: entity.tickEvent("typeup")
    of 24: entity.tickEvent("releaseshift")
    of 25: entity.tickEvent("typeleft")
    else: discard
    board.tick()
    ticksLeft -= 1
    ticksDone += 1
    #echo &"board: {board}"

    # TODO: Not hardcode the width and height --GM
    echo ">==========================================================="
    for y in 0..24:
      var lineSeq: seq[char] = @[]
      for x in 0..59:
        var gridseq = board.grid[y][x]
        lineSeq.add(if gridseq.len >= 1:
            '*'
          else:
            ' '
        )
      echo lineSeq.join("")
    echo "============================================================"
    for entity in board.entities:
      echo &"  - ({entity.x}, {entity.y})"
    echo ""
    #var health = entity.params.getOrDefault("health", ScriptVal(kind: svkInt, intVal: 0))
    #var ammo = entity.params.getOrDefault("ammo", ScriptVal(kind: svkInt, intVal: 0))
    #echo &"entity pos: {entity.x}, {entity.y} / health: {health} / ammo: {ammo} / alive: {entity.alive}"

main()
