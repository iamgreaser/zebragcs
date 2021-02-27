import strformat

import ../interntables

import ../types

proc asBool*(x: ScriptVal, node: ScriptNode): bool
proc asCoercedStr*(x: ScriptVal, node: ScriptNode): string
proc asInt*(x: ScriptVal, node: ScriptNode): int64
proc asStr*(x: ScriptVal, node: ScriptNode): string
proc newScriptExecError*(node: ScriptNode, message: string): ref ScriptExecError
proc resolveExpr*(execState: ScriptExecState, expr: ScriptNode): ScriptVal
proc storeAtExpr*(execState: ScriptExecState, dst: ScriptNode, val: ScriptVal)

proc newScriptExecError(node: ScriptNode, message: string): ref ScriptExecError =
  if node == nil:
    newException(ScriptExecError, &"system: {message}")
  else:
    newException(ScriptExecError, &"{node.fname}:{node.row}:{node.col}: {message}")

method funcThisPos(execState: ScriptExecState, node: ScriptNode): ScriptVal {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for builtin func thispos (or posof)")
method funcThisPos(entity: Entity, node: ScriptNode): ScriptVal {.locks: "unknown".} =
  return ScriptVal(kind: svkPos, posBoardNameIdx: entity.board.boardNameIdx, posValX: entity.x, posValY: entity.y)

method funcSelf(execState: ScriptExecState, node: ScriptNode): ScriptVal {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for builtin func self")
method funcSelf(entity: Entity, node: ScriptNode): ScriptVal {.locks: "unknown".} =
  return ScriptVal(kind: svkEntity, entityRef: entity)
method funcSelf(player: Player, node: ScriptNode): ScriptVal {.locks: "unknown".} =
  return ScriptVal(kind: svkPlayer, playerRef: player)

method funcAt(execState: ScriptExecState, node: ScriptNode, x: int64, y: int64): ScriptVal {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for builtin func at")
method funcAt(board: Board, node: ScriptNode, x: int64, y: int64): ScriptVal {.locks: "unknown".} =
  return ScriptVal(kind: svkPos, posBoardNameIdx: board.boardNameIdx, posValX: x, posValY: y)
method funcAt(entity: Entity, node: ScriptNode, x: int64, y: int64): ScriptVal {.locks: "unknown".} =
  return entity.board.funcAt(node, x, y)

method funcAtBoard(execState: ScriptExecState, boardName: string, x: int64, y: int64): ScriptVal {.base.} =
  return ScriptVal(kind: svkPos, posBoardNameIdx: internKey(boardName), posValX: x, posValY: y)

method resolvePos*(execState: ScriptExecState, node: ScriptNode, val: ScriptVal): tuple[boardNameIdx: InternKey, x: int64, y: int64] {.base, locks: "unknown".} =
  case val.kind:
    of svkPos: (val.posBoardNameIdx, val.posValX, val.posValY)
    of svkEntity:
      var entity = val.entityRef
      var pos = if entity != nil:
        entity.funcThisPos(node)
      else:
        # TODO: Pick a suitable default position --GM
        execState.funcThisPos(node)
      (pos.posBoardNameIdx, pos.posValX, pos.posValY)
    else:
      raise node.newScriptExecError(&"Expected pos or entity, got {val} instead")
method resolvePos*(entity: Entity, node: ScriptNode, val: ScriptVal): tuple[boardNameIdx: InternKey, x: int64, y: int64] {.locks: "unknown".} =
  case val.kind:
    of svkDir: (entity.board.boardNameIdx, entity.x + val.dirValX, entity.y + val.dirValY)
    of svkPos: (val.posBoardNameIdx, val.posValX, val.posValY)
    of svkEntity:
      var otherEntity = val.entityRef
      var pos = if otherEntity != nil:
        otherEntity.funcThisPos(node)
      else:
        entity.funcThisPos(node)
      (pos.posBoardNameIdx, pos.posValX, pos.posValY)

    else:
      raise node.newScriptExecError(&"Expected dir, pos or entity, got {val} instead")

proc randomUintBelow(execState: ScriptExecState, n: uint64): int64 =
  # xorshift64*
  var share = execState.share
  assert share != nil
  var x = share.seed
  x = x xor (x shr 12)
  x = x xor (x shl 25)
  x = x xor (x shr 27)
  share.seed = x
  x *= 0x2545F4914F6CDD1D'u64

  # Reduce the space
  x = (x div 2) div (0x8000000000000000'u64 div n)
  assert x >= 0 and x < n
  return int64(x)

proc asBool(x: ScriptVal, node: ScriptNode): bool =
  case x.kind
  of svkBool: x.boolVal
  of svkEntity: x.entityRef != nil
  else:
    raise node.newScriptExecError(&"Expected bool or entity, got {x} instead")

proc asInt(x: ScriptVal, node: ScriptNode): int64 =
  case x.kind
  of svkInt: x.intVal
  else:
    raise node.newScriptExecError(&"Expected int, got {x} instead")

proc asStr(x: ScriptVal, node: ScriptNode): string =
  case x.kind
  of svkStr: x.strVal
  else:
    raise node.newScriptExecError(&"Expected str, got {x} instead")

proc asCoercedStr(x: ScriptVal, node: ScriptNode): string =
  case x.kind
  of svkBool:
    if x.boolVal:
      "true"
    else:
      "false"
  of svkEntity: &"<entity 0x{cast[uint](x.entityRef):x}>"
  of svkPlayer: &"<player 0x{cast[uint](x.playerRef):x}>"
  of svkInt: $x.intVal
  of svkStr: x.strVal
  of svkDir: &"rel {x.dirValX} {x.dirValY}"
  of svkPos: &"at {x.posValX} {x.posValY}"

method funcDirComponents(execState: ScriptExecState, node: ScriptNode, dir: ScriptVal): tuple[dx: int64, dy: int64] {.base, locks: "unknown".} =
  case dir.kind:
    of svkDir: (dir.dirValX, dir.dirValY)
    else:
      raise node.newScriptExecError(&"Expected dir, got {dir} instead")
method funcDirComponents(entity: Entity, node: ScriptNode, dir: ScriptVal): tuple[dx: int64, dy: int64] =
  case dir.kind:
    of svkDir: (dir.dirValX, dir.dirValY)
    of svkPos:
      if dir.posBoardNameIdx != entity.board.boardNameIdx:
        (0'i64, 0'i64)
      else:
        (dir.posValX - entity.x, dir.posValY - entity.y)
    else:
      raise node.newScriptExecError(&"Expected dir or pos, got {dir} instead")

method funcSeek(execState: ScriptExecState, node: ScriptNode, pos: ScriptVal): ScriptVal {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for builtin func seek")
method funcSeek(entity: Entity, node: ScriptNode, pos: ScriptVal): ScriptVal =
  var thisBoardNameIdx = entity.board.boardNameIdx
  var (otherBoardNameIdx, x, y) = entity.resolvePos(node, pos)
  var dx = x - entity.x
  var dy = y - entity.y

  # If the boards are different, go idle instead.
  if otherBoardNameIdx != thisBoardNameIdx:
    return ScriptVal(kind: svkDir, dirValX: 0, dirValY: 0)

  dx = max(-1, min(1, dx))
  dy = max(-1, min(1, dy))

  if dx == 0 or dy == 0:
    return ScriptVal(kind: svkDir, dirValX: dx, dirValY: dy)
  elif entity.randomUintBelow(2) == 0:
    return ScriptVal(kind: svkDir, dirValX: 0, dirValY: dy)
  else:
    return ScriptVal(kind: svkDir, dirValX: dx, dirValY: 0)

proc defaultScriptVal(execState: ScriptExecState, node: ScriptNode, kind: ScriptValKind): ScriptVal =
  case kind
  of svkBool: ScriptVal(kind: kind, boolVal: false)
  of svkDir: ScriptVal(kind: kind, dirValX: 0, dirValY: 0)
  of svkEntity: ScriptVal(kind: kind, entityRef: nil)
  of svkInt: ScriptVal(kind: kind, intVal: 0)
  of svkPlayer: ScriptVal(kind: kind, playerRef: nil)
  of svkPos: execState.funcAt(node, 0, 0) # TODO: Consider making pos not have a default, and throw an exception instead --GM
  of svkStr: ScriptVal(kind: kind, strVal: "")

proc storeAtExpr(execState: ScriptExecState, dst: ScriptNode, val: ScriptVal) =
  var execBase = execState.execBase
  assert execBase != nil

  case dst.kind
  of snkGlobalVar:
    var share = execState.share
    assert share != nil

    var expectedType = try:
        execBase.globals[dst.globalVarNameIdx].varType
      except KeyError:
        raise dst.newScriptExecError(&"Undeclared global \"${dst.globalVarNameIdx.getInternName()}\"")

    if expectedType == val.kind:
      share.globals[dst.globalVarNameIdx] = val
    else:
      raise dst.newScriptExecError(&"Attempted to write {val.kind} into {dst} which is of type {expectedType}")

  of snkParamVar:
    var expectedType = try:
        execBase.params[dst.paramVarNameIdx].varType
      except KeyError:
        raise dst.newScriptExecError(&"Undeclared param \"@{dst.paramVarNameIdx.getInternName()}\"")

    if expectedType == val.kind:
      execState.params[dst.paramVarNameIdx] = val
    else:
      raise dst.newScriptExecError(&"Attempted to write {val.kind} into {dst} which is of type {expectedType}")

  of snkLocalVar:
    var expectedType = try:
        execBase.locals[dst.localVarNameIdx].varType
      except KeyError:
        raise dst.newScriptExecError(&"Undeclared local \"%{dst.localVarNameIdx.getInternName()}\"")

    if expectedType == val.kind:
      execState.locals[dst.localVarNameIdx] = val
    else:
      raise dst.newScriptExecError(&"Attempted to write {val.kind} into {dst} which is of type {expectedType}")

  else:
    raise dst.newScriptExecError(&"Unhandled assignment destination {dst}")

proc resolveExpr(execState: ScriptExecState, expr: ScriptNode): ScriptVal =
  case expr.kind
  of snkConst:
    return expr.constVal

  of snkStringBlock:
    var accum = ""
    for subExpr in expr.stringNodes:
      accum &= execState.resolveExpr(subExpr).asCoercedStr(subExpr)
    return ScriptVal(kind: svkStr, strVal: accum)

  of snkFunc:
    internCase case expr.funcType

    of "thispos":
      return execState.funcThisPos(expr)

    of "cw", "opp", "ccw":
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var (dx, dy) = case v0.kind
        of svkDir:
          (v0.dirValX, v0.dirValY)
        else:
          raise expr.newScriptExecError(&"Unhandled dir kind {v0.kind}")

      (dx, dy) = internCase (case expr.funcType
        of "cw": (-dy, dx)
        of "opp": (-dx, -dy)
        of "ccw": (dy, -dx)
        else:
          raise expr.newScriptExecError(&"EDOOFUS: Unhandled rotation function {expr.funcType.getInternName()}"))

      return ScriptVal(kind: svkDir, dirValX: dx, dirValY: dy)

    of "eq", "ne":
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var v1 = execState.resolveExpr(expr.funcArgs[1])
      var iseq: bool = case v0.kind
        of svkBool:
          v1.kind == svkBool and v0.boolVal == v1.boolVal
        of svkInt:
          v1.kind == svkInt and v0.intVal == v1.intVal
        of svkEntity:
          v1.kind == svkEntity and v0.entityRef == v1.entityRef
        of svkDir:
          v1.kind == svkDir and v0.dirValX == v1.dirValX and v0.dirValY == v1.dirValY
        of svkPlayer:
          v1.kind == svkPlayer and v0.playerRef == v1.playerRef
        of svkPos:
          v1.kind == svkPos and v0.posValX == v1.posValX and v0.posValY == v1.posValY
        of svkStr:
          v1.kind == svkStr and v0.strVal == v1.strVal
        #else:
        #  raise v0.newScriptExecError(&"Unhandled bool kind {v0.kind}")
      return ScriptVal(kind: svkBool, boolVal: (iseq == (expr.funcType == internKeyCT("eq"))))

    of "not":
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      return ScriptVal(kind: svkBool, boolVal: not v0.asBool(expr.funcArgs[0]))

    of "lt", "le", "gt", "ge":
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0]).asInt(expr.funcArgs[0])
      var v1 = execState.resolveExpr(expr.funcArgs[1]).asInt(expr.funcArgs[0])
      var b0 = internCase (case expr.funcType
        of "lt": v0 < v1
        of "le": v0 <= v1
        of "gt": v0 > v1
        of "ge": v0 >= v1
        else:
          raise expr.newScriptExecError(&"EDOOFUS: ScriptFuncType unknown for {expr}!"))
      return ScriptVal(kind: svkBool, boolVal: b0)

    of "self":
      assert expr.funcArgs.len == 0
      return execState.funcSelf(expr)

    of "posof":
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      case v0.kind
      of svkEntity:
        var otherEntity = v0.entityRef
        if otherEntity != nil:
          return otherEntity.funcThisPos(expr.funcArgs[0])
        else:
          return execState.funcThisPos(expr.funcArgs[0])
      else:
        raise expr.funcArgs[0].newScriptExecError(&"Expected entity, got {v0} instead")

    of "at":
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0]).asInt(expr.funcArgs[0])
      var v1 = execState.resolveExpr(expr.funcArgs[1]).asInt(expr.funcArgs[1])
      return execState.funcAt(expr, v0, v1)

    of "atboard":
      assert expr.funcArgs.len == 3
      var boardName = execState.resolveExpr(expr.funcArgs[0]).asStr(expr.funcArgs[0])
      var v0 = execState.resolveExpr(expr.funcArgs[1]).asInt(expr.funcArgs[1])
      var v1 = execState.resolveExpr(expr.funcArgs[2]).asInt(expr.funcArgs[2])
      return execState.funcAtBoard(boardName, v0, v1)

    of "dirx":
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var (dx, _) = execState.funcDirComponents(expr.funcArgs[0], v0)
      return ScriptVal(kind: svkInt, intVal: dx)

    of "diry":
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var (_, dy) = execState.funcDirComponents(expr.funcArgs[0], v0)
      return ScriptVal(kind: svkInt, intVal: dy)

    of "random":
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0]).asInt(expr.funcArgs[0])
      var v1 = execState.resolveExpr(expr.funcArgs[1]).asInt(expr.funcArgs[1])
      var vout = if v0 < v1:
          v0 + execState.randomUintBelow(uint64(v1+1-v0))
        elif v1 < v0:
          v1 + execState.randomUintBelow(uint64(v0+1-v1))
        elif v0 == v1:
          v0
        else:
          raise expr.newScriptExecError(&"EDOOFUS: Math itself has somehow failed ({v0} vs {v1})")

      return ScriptVal(kind: svkInt, intVal: vout)

    of "randomdir":
      assert expr.funcArgs.len == 0
      case execState.randomUintBelow(4'u64)
        of 0'i64: return ScriptVal(kind: svkDir, dirValX: 0, dirValY: -1)
        of 1'i64: return ScriptVal(kind: svkDir, dirValX: 0, dirValY: +1)
        of 2'i64: return ScriptVal(kind: svkDir, dirValX: -1, dirValY: 0)
        of 3'i64: return ScriptVal(kind: svkDir, dirValX: +1, dirValY: 0)
        else:
          raise expr.newScriptExecError(&"EDOOFUS: Missing a case for randomdir!")

    of "seek":
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      return execState.funcSeek(expr.funcArgs[0], v0)

    else: raise expr.newScriptExecError(&"Unhandled func kind {expr.funcType.getInternName()} for expr {expr}")

  of snkGlobalVar:
    var k0 = expr.globalVarNameIdx
    var share = execState.share
    assert share != nil
    var d0 = try:
        execState.execBase.globals[k0]
      except KeyError:
        raise expr.newScriptExecError(&"Undeclared global \"${k0.getInternName()}\" (TODO: make sure the types get synced and verified properly! --GM)")
    var v0: ScriptVal = try:
        share.globals[k0]
      except KeyError:
        var vd = execState.defaultScriptVal(expr, d0.varType)
        share.globals[k0] = vd
        vd
    return v0

  of snkParamVar:
    var k0 = expr.paramVarNameIdx
    var d0 = try:
        execState.execBase.params[k0]
      except KeyError:
        raise expr.newScriptExecError(&"Undeclared parameter \"@{k0.getInternName()}\"")
    var v0: ScriptVal = try:
        execState.params[k0]
      except KeyError:
        var vd = execState.resolveExpr(d0.varDefault)
        execState.params[k0] = vd
        vd
    return v0

  of snkLocalVar:
    var k0 = expr.localVarNameIdx
    var d0 = try:
        execState.execBase.locals[k0]
      except KeyError:
        raise expr.newScriptExecError(&"Undeclared local \"%{k0.getInternName()}\"")
    var v0: ScriptVal = try:
        execState.locals[k0]
      except KeyError:
        var vd = execState.resolveExpr(d0.varDefault)
        execState.locals[k0] = vd
        vd
    return v0

  else:
    raise expr.newScriptExecError(&"Unhandled expr kind {expr.kind}")
