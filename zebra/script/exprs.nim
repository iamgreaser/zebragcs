import strformat
import tables

import ../types

proc asBool*(x: ScriptVal): bool
proc asInt*(x: ScriptVal): int64
proc asStr*(x: ScriptVal): string
proc resolveExpr*(execState: ScriptExecState, expr: ScriptNode): ScriptVal
proc storeAtExpr*(execState: ScriptExecState, dst: ScriptNode, val: ScriptVal)

method resolvePos*(execState: ScriptExecState, val: ScriptVal): tuple[boardName: string, x: int64, y: int64] {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Could not resolve position of type {execState}")
method resolvePos*(world: World, val: ScriptVal): tuple[boardName: string, x: int64, y: int64] {.locks: "unknown".} =
  case val.kind:
    of svkPos: (val.posBoardName, val.posValX, val.posValY)
    else:
      raise newException(ScriptExecError, &"Expected pos, got {val} instead")
method resolvePos*(board: Board, val: ScriptVal): tuple[boardName: string, x: int64, y: int64] {.locks: "unknown".} =
  case val.kind:
    of svkPos: (val.posBoardName, val.posValX, val.posValY)
    else:
      raise newException(ScriptExecError, &"Expected pos, got {val} instead")
method resolvePos*(entity: Entity, val: ScriptVal): tuple[boardName: string, x: int64, y: int64] {.locks: "unknown".} =
  case val.kind:
    of svkDir: (entity.board.boardName, entity.x + val.dirValX, entity.y + val.dirValY)
    of svkPos: (val.posBoardName, val.posValX, val.posValY)
    else:
      raise newException(ScriptExecError, &"Expected dir or pos, got {val} instead")

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

proc asBool(x: ScriptVal): bool =
  case x.kind
  of svkBool: x.boolVal
  else:
    raise newException(ScriptExecError, &"Expected bool, got {x} instead")

proc asInt(x: ScriptVal): int64 =
  case x.kind
  of svkInt: x.intVal
  else:
    raise newException(ScriptExecError, &"Expected int, got {x} instead")

proc asStr(x: ScriptVal): string =
  case x.kind
  of svkStr: x.strVal
  else:
    raise newException(ScriptExecError, &"Expected str, got {x} instead")

method funcThisPos(execState: ScriptExecState): ScriptVal {.base.} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for builtin func thispos")
method funcThisPos(entity: Entity): ScriptVal =
  return ScriptVal(kind: svkPos, posBoardName: entity.board.boardName, posValX: entity.x, posValY: entity.y)

method funcAt(execState: ScriptExecState, x: int64, y: int64): ScriptVal {.base.} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for builtin func at")
method funcAt(board: Board, x: int64, y: int64): ScriptVal =
  return ScriptVal(kind: svkPos, posBoardName: board.boardName, posValX: x, posValY: y)
method funcAt(entity: Entity, x: int64, y: int64): ScriptVal =
  return entity.board.funcAt(x, y)

method funcAtBoard(execState: ScriptExecState, boardName: string, x: int64, y: int64): ScriptVal {.base.} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for builtin func atboard")
method funcAtBoard(world: World, boardName: string, x: int64, y: int64): ScriptVal =
  return ScriptVal(kind: svkPos, posBoardName: boardName, posValX: x, posValY: y)
method funcAtBoard(board: Board, boardName: string, x: int64, y: int64): ScriptVal =
  return board.world.funcAtBoard(boardName, x, y)
method funcAtBoard(entity: Entity, boardName: string, x: int64, y: int64): ScriptVal =
  return entity.board.funcAtBoard(boardName, x, y)

method funcDirComponents(execState: ScriptExecState, funcType: ScriptFuncType, dir: ScriptVal): tuple[dx: int64, dy: int64] {.base.} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for builtin func seek")
method funcDirComponents(board: Board, funcType: ScriptFuncType, dir: ScriptVal): tuple[dx: int64, dy: int64] =
  case dir.kind:
    of svkDir: (dir.dirValX, dir.dirValY)
    else:
      raise newException(ScriptExecError, &"Expected dir, got {dir} instead")
method funcDirComponents(entity: Entity, funcType: ScriptFuncType, dir: ScriptVal): tuple[dx: int64, dy: int64] =
  case dir.kind:
    of svkDir: (dir.dirValX, dir.dirValY)
    of svkPos: (dir.posValX - entity.x, dir.posValY - entity.y)
    else:
      raise newException(ScriptExecError, &"Expected dir or pos, got {dir} instead")

method funcSeek(execState: ScriptExecState, pos: ScriptVal): ScriptVal {.base.} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for builtin func seek")
method funcSeek(entity: Entity, pos: ScriptVal): ScriptVal =
  var thisBoardName = entity.board.boardName
  var (otherBoardName, dx, dy) = case pos.kind:
    of svkPos: (pos.posBoardName, pos.posValX - entity.x, pos.posValY - entity.y)
    else:
      raise newException(ScriptExecError, &"Expected dir or pos, got {pos} instead")

  # If the boards are different, go idle instead.
  if otherBoardName != thisBoardName:
    return ScriptVal(kind: svkDir, dirValX: 0, dirValY: 0)

  dx = max(-1, min(1, dx))
  dy = max(-1, min(1, dy))

  if dx == 0 or dy == 0:
    return ScriptVal(kind: svkDir, dirValX: dx, dirValY: dy)
  elif entity.randomUintBelow(2) == 0:
    return ScriptVal(kind: svkDir, dirValX: 0, dirValY: dy)
  else:
    return ScriptVal(kind: svkDir, dirValX: dx, dirValY: 0)

proc defaultScriptVal(execState: ScriptExecState, kind: ScriptValKind): ScriptVal =
  case kind
  of svkBool: ScriptVal(kind: kind, boolVal: false)
  of svkDir: ScriptVal(kind: kind, dirValX: 0, dirValY: 0)
  of svkInt: ScriptVal(kind: kind, intVal: 0)
  of svkPos: execState.funcAt(0, 0) # TODO: Consider making pos not have a default, and throw an exception instead --GM
  of svkStr: ScriptVal(kind: kind, strVal: "")

proc storeAtExpr(execState: ScriptExecState, dst: ScriptNode, val: ScriptVal) =
  var execBase = execState.execBase
  assert execBase != nil

  case dst.kind
  of snkGlobalVar:
    var share = execState.share
    assert share != nil

    var expectedType = try:
        execBase.globals[dst.globalVarName].varType
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared global \"${dst.globalVarName}\"")

    if expectedType == val.kind:
      share.globals[dst.globalVarName] = val
    else:
      raise newException(ScriptExecError, &"Attempted to write {val.kind} into {dst} which is of type {expectedType}")

  of snkParamVar:
    var expectedType = try:
        execBase.params[dst.paramVarName].varType
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared param \"@{dst.paramVarName}\"")

    if expectedType == val.kind:
      execState.params[dst.paramVarName] = val
    else:
      raise newException(ScriptExecError, &"Attempted to write {val.kind} into {dst} which is of type {expectedType}")

  of snkLocalVar:
    var expectedType = try:
        execBase.locals[dst.localVarName].varType
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared local \"%{dst.localVarName}\"")

    if expectedType == val.kind:
      execState.locals[dst.localVarName] = val
    else:
      raise newException(ScriptExecError, &"Attempted to write {val.kind} into {dst} which is of type {expectedType}")

  else:
    raise newException(ScriptExecError, &"Unhandled assignment destination {dst}")

proc resolveExpr(execState: ScriptExecState, expr: ScriptNode): ScriptVal =
  case expr.kind
  of snkConst:
    return expr.constVal

  of snkFunc:
    case expr.funcType

    of sftThisPos:
      return execState.funcThisPos()

    of sftCw, sftOpp, sftCcw:
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var (dx, dy) = case v0.kind
        of svkDir:
          (v0.dirValX, v0.dirValY)
        else:
          raise newException(ScriptExecError, &"Unhandled dir kind {v0.kind}")

      (dx, dy) = case expr.funcType
        of sftCw: (-dy, dx)
        of sftOpp: (-dx, -dy)
        of sftCcw: (dy, -dx)
        else:
          raise newException(ScriptExecError, &"EDOOFUS: Unhandled rotation function {expr.funcType}")

      return ScriptVal(kind: svkDir, dirValX: dx, dirValY: dy)

    of sftEq, sftNe:
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var v1 = execState.resolveExpr(expr.funcArgs[1])
      var iseq: bool = case v0.kind
        of svkBool:
          v1.kind == svkBool and v0.boolVal == v1.boolVal
        of svkInt:
          v1.kind == svkInt and v0.intVal == v1.intVal
        of svkDir:
          v1.kind == svkDir and v0.dirValX == v1.dirValX and v0.dirValY == v1.dirValY
        of svkPos:
          v1.kind == svkPos and v0.posValX == v1.posValX and v0.posValY == v1.posValY
        of svkStr:
          v1.kind == svkStr and v0.strVal == v1.strVal
        #else:
        #  raise newException(ScriptExecError, &"Unhandled bool kind {v0.kind}")
      return ScriptVal(kind: svkBool, boolVal: (iseq == (expr.funcType == sftEq)))

    of sftNot:
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      return ScriptVal(kind: svkBool, boolVal: not v0.asBool())

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

    of sftAt:
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0]).asInt()
      var v1 = execState.resolveExpr(expr.funcArgs[1]).asInt()
      return execState.funcAt(v0, v1)

    of sftAtBoard:
      assert expr.funcArgs.len == 3
      var boardName = execState.resolveExpr(expr.funcArgs[0]).asStr()
      var v0 = execState.resolveExpr(expr.funcArgs[1]).asInt()
      var v1 = execState.resolveExpr(expr.funcArgs[2]).asInt()
      return execState.funcAtBoard(boardName, v0, v1)

    of sftDirX:
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var (dx, _) = execState.funcDirComponents(expr.funcType, v0)
      return ScriptVal(kind: svkInt, intVal: dx)

    of sftDirY:
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      var (_, dy) = execState.funcDirComponents(expr.funcType, v0)
      return ScriptVal(kind: svkInt, intVal: dy)

    of sftRandom:
      assert expr.funcArgs.len == 2
      var v0 = execState.resolveExpr(expr.funcArgs[0]).asInt()
      var v1 = execState.resolveExpr(expr.funcArgs[1]).asInt()
      var vout = if v0 < v1:
          v0 + execState.randomUintBelow(uint64(v1+1-v0))
        elif v1 < v0:
          v1 + execState.randomUintBelow(uint64(v0+1-v1))
        elif v0 == v1:
          v0
        else:
          raise newException(ScriptExecError, &"EDOOFUS: Math itself has somehow failed ({v0} vs {v1})")

      return ScriptVal(kind: svkInt, intVal: vout)

    of sftRandomDir:
      assert expr.funcArgs.len == 0
      case execState.randomUintBelow(4'u64)
        of 0'i64: return ScriptVal(kind: svkDir, dirValX: 0, dirValY: -1)
        of 1'i64: return ScriptVal(kind: svkDir, dirValX: 0, dirValY: +1)
        of 2'i64: return ScriptVal(kind: svkDir, dirValX: -1, dirValY: 0)
        of 3'i64: return ScriptVal(kind: svkDir, dirValX: +1, dirValY: 0)
        else:
          raise newException(ScriptExecError, &"EDOOFUS: Missing a case for randomdir!")

    of sftSeek:
      assert expr.funcArgs.len == 1
      var v0 = execState.resolveExpr(expr.funcArgs[0])
      return execState.funcSeek(v0)

    #else: raise newException(ScriptExecError, &"Unhandled func kind {expr.funcType} for expr {expr}")

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
        var vd = execState.defaultScriptVal(d0.varType)
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
        execState.params[k0]
      except KeyError:
        var vd = execState.resolveExpr(d0.varDefault)
        execState.params[k0] = vd
        vd
    return v0

  of snkLocalVar:
    var k0 = expr.localVarName
    var d0 = try:
        execState.execBase.locals[k0]
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared local \"%{k0}\"")
    var v0: ScriptVal = try:
        execState.locals[k0]
      except KeyError:
        var vd = execState.resolveExpr(d0.varDefault)
        execState.locals[k0] = vd
        vd
    return v0

  else:
    raise newException(ScriptExecError, &"Unhandled expr kind {expr.kind}")
