import strformat
import tables

import types

proc asBool*(x: ScriptVal): bool
proc asInt*(x: ScriptVal): int64
proc resolveExpr*(execState: ScriptExecState, expr: ScriptNode): ScriptVal
proc storeAtExpr*(execState: ScriptExecState, dst: ScriptNode, val: ScriptVal)


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

proc defaultScriptVal(kind: ScriptValKind): ScriptVal =
  case kind
  of svkBool: ScriptVal(kind: kind, boolVal: false)
  of svkDir: ScriptVal(kind: kind, dirValX: 0, dirValY: 0)
  of svkInt: ScriptVal(kind: kind, intVal: 0)
  of svkPos: ScriptVal(kind: kind, posValX: 0, posValY: 0) # TODO: Consider making pos not have a default, and throw an exception instead --GM

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
    var entity = execState.entity
    assert entity != nil

    var expectedType = try:
        execBase.params[dst.paramVarName].varType
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared param \"@{dst.paramVarName}\"")

    if expectedType == val.kind:
      entity.params[dst.paramVarName] = val
    else:
      raise newException(ScriptExecError, &"Attempted to write {val.kind} into {dst} which is of type {expectedType}")

  of snkLocalVar:
    var entity = execState.entity
    assert entity != nil

    var expectedType = try:
        execBase.locals[dst.localVarName].varType
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared local \"%{dst.localVarName}\"")

    if expectedType == val.kind:
      entity.locals[dst.localVarName] = val
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
      var entity = execState.entity
      assert entity != nil
      return ScriptVal(kind: svkPos, posValX: entity.x, posValY: entity.y)

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
      return ScriptVal(kind: svkPos, posValX: v0, posValY: v1)

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

  of snkLocalVar:
    var k0 = expr.localVarName
    var d0 = try:
        execState.execBase.locals[k0]
      except KeyError:
        raise newException(ScriptExecError, &"Undeclared local \"%{k0}\"")
    var v0: ScriptVal = try:
        execState.entity.locals[k0]
      except KeyError:
        var vd = execState.resolveExpr(d0.varDefault)
        execState.entity.locals[k0] = vd
        vd
    return v0

  else:
    raise newException(ScriptExecError, &"Unhandled expr kind {expr.kind}")
