import strformat
import tables

import ../types

method tick*(execState: ScriptExecState) {.base, locks: "unknown".}
proc tickEvent*(execState: ScriptExecState, eventName: string)

import ../board
import ../entity
import ./exprs


method stmtDie(execState: ScriptExecState) {.base, locks: "unknown".} =
  execState.alive = false
  execState.continuations = @[]
method stmtDie(entity: Entity) =
  var board = entity.board
  assert board != nil
  board.removeEntityFromGrid(entity)
  procCall stmtDie(ScriptExecState(entity))

method stmtMovePerformRel(execState: ScriptExecState, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for move")
method stmtMovePerformRel(entity: Entity, dx, dy: int64): bool =
  entity.moveBy(dx, dy)

method stmtBroadcast(execState: ScriptExecState, eventName: string) {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for broadcast")
method stmtBroadcast(entity: Entity, eventName: string) =
  var board = entity.board
  assert board != nil
  board.broadcastEvent(eventName)

method stmtSend(execState: ScriptExecState, dirOrPos: ScriptVal, eventName: string) {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for send")
method stmtSend(entity: Entity, dirOrPos: ScriptVal, eventName: string) =
  var board = entity.board
  assert board != nil
  var (x, y) = entity.resolvePos(dirOrPos)
  board.sendEventToPos(eventName, x, y)

method stmtSpawn(execState: ScriptExecState, entityName: string, dirOrPos: ScriptVal, spawnBody: seq[ScriptNode], spawnElse: seq[ScriptNode]): Entity {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for spawn")
method stmtSpawn(board: Board, entityName: string, dirOrPos: ScriptVal, spawnBody: seq[ScriptNode], spawnElse: seq[ScriptNode]): Entity =
  var (x, y) = board.resolvePos(dirOrPos)

  var newEntity = board.newEntity(entityName, x, y)
  return newEntity
method stmtSpawn(entity: Entity, entityName: string, dirOrPos: ScriptVal, spawnBody: seq[ScriptNode], spawnElse: seq[ScriptNode]): Entity =
  var (x, y) = entity.resolvePos(dirOrPos)
  var board = entity.board
  assert board != nil

  var newEntity = board.newEntity(entityName, x, y)
  return newEntity

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
        execState.stmtDie()
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
        var didMove = case moveDir.kind
          of svkDir: execState.stmtMovePerformRel(moveDir.dirValX, moveDir.dirValY)
          else:
            raise newException(ScriptExecError, &"Expected dir, got {moveDir} instead")

        if not didMove:
          var body = node.moveElse
          execState.continuations.add(cont)
          cont = ScriptContinuation(codeBlock: body, codePc: 0)

      of snkBroadcast:
        var eventName: string = node.broadcastEventName
        execState.stmtBroadcast(eventName)

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
        var dirOrPos = execState.resolveExpr(node.sendPos)
        var eventName: string = node.sendEventName
        execState.stmtSend(dirOrPos, eventName)

      of snkSleep:
        var sleepTime = execState.resolveExpr(node.sleepTimeExpr).asInt()
        if sleepTime >= 1:
          execState.sleepTicksLeft = sleepTime
          execState.continuations.add(cont)
          return

      of snkSpawn:
        var dirOrPos = execState.resolveExpr(node.spawnPos)
        var entityName: string = node.spawnEntityName
        var spawnBody = node.spawnBody
        var spawnElse = node.spawnElse
        var newEntity = execState.stmtSpawn(entityName, dirOrPos, spawnBody, spawnElse)
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

method tick(execState: ScriptExecState) {.base, locks: "unknown".} =
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
