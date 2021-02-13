import streams
import strformat
import tables

import types

proc loadEntityTypeFromFile*(share: ScriptSharedExecState, entityName: string, fname: string)
proc newBoard*(share: ScriptSharedExecState): Board
proc newEntity*(board: Board, entityType: string, x, y: int): Entity
proc newScriptSharedExecState*(): ScriptSharedExecState
proc tick*(execState: ScriptExecState)
proc tick*(entity: Entity)
proc tick*(board: Board)
proc tickEvent*(execState: ScriptExecState, eventName: string)
proc tickEvent*(entity: Entity, eventName: string)

import scriptnodes


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
