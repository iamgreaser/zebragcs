import strformat
import tables

import ../types

proc tick*(execState: ScriptExecState)
proc tickEvent*(execState: ScriptExecState, eventName: string)

import ../board
import ../entity
import ./exprs


proc tickContinuations(execState: ScriptExecState, lowerBound: uint64) =
  while uint64(execState.continuations.len) > lowerBound:
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
          of satInc: ScriptVal(kind: svkInt, intVal: assignDst.asInt() + assignSrc.asInt())
          else:
            raise newException(ScriptExecError, &"Unhandled assignment type {assignType}")

        execState.storeAtExpr(assignDstExpr, assignResult)

      of snkDie:
        var entity = execState.entity
        assert entity != nil
        execState.alive = false;
        entity.alive = false;
        var board = entity.board
        assert board != nil
        board.removeEntityFromGrid(entity)
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

      of snkWhileBlock:
        var test = execState.resolveExpr(node.whileTest)
        var body = node.whileBody
        if test.asBool():
          cont.codePc = nodePc # Step back to here
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

      of snkBroadcast:
        var entity = execState.entity
        assert entity != nil
        var board = entity.board
        assert board != nil
        var eventName: string = node.broadcastEventName
        board.broadcastEvent(eventName)

      of snkSay:
        var sayExpr = execState.resolveExpr(node.sayExpr)
        var sayStr: string = case sayExpr.kind
          of svkBool:
            if sayExpr.boolVal:
              "true"
            else:
              "false"
          of svkInt: $sayExpr.intVal
          of svkStr: sayExpr.strVal
          of svkDir: &"rel {sayExpr.dirValX} {sayExpr.dirValY}"
          of svkPos: &"at {sayExpr.posValX} {sayExpr.posValY}"

        # TODO: Actually put it in the window somewhere --GM
        echo &"SAY: [{sayStr}]"

      of snkSend:
        var entity = execState.entity
        assert entity != nil
        var board = entity.board
        assert board != nil
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
        board.sendEventToPos(eventName, pos.posValX, pos.posValY)

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
    execState.tickContinuations(lowerBound=0'u64)
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

  execState.tickContinuations(lowerBound=0'u64)

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
  execState.tickContinuations(lowerBound=uint64(execState.continuations.len-1))
