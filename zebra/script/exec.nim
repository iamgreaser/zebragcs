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
  execState.continuations.setLen(0)
method stmtDie(entity: Entity) =
  var board = entity.board
  assert board != nil
  board.removeEntityFromGrid(entity)
  procCall stmtDie(ScriptExecState(entity))

method stmtForceMovePerformRel(execState: ScriptExecState, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for move")
method stmtForceMovePerformRel(entity: Entity, dx, dy: int64): bool =
  entity.forceMoveBy(dx, dy)

method stmtForceMovePerformAbs(execState: ScriptExecState, boardName: string, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for move")
method stmtForceMovePerformAbs(entity: Entity, boardName: string, dx, dy: int64): bool =
  entity.forceMoveTo(entity.board.world.boards[boardName], dx, dy)

method stmtMovePerformRel(execState: ScriptExecState, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for move")
method stmtMovePerformRel(entity: Entity, dx, dy: int64): bool =
  entity.moveBy(dx, dy)

method stmtMovePerformAbs(execState: ScriptExecState, boardName: string, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for move")
method stmtMovePerformAbs(entity: Entity, boardName: string, dx, dy: int64): bool =
  entity.moveTo(entity.board.world.boards[boardName], dx, dy)

method stmtBroadcast(execState: ScriptExecState, eventName: string) {.base, locks: "unknown".} =
  raise newException(ScriptExecError, &"Unexpected type {execState} for broadcast")
method stmtBroadcast(entity: Entity, eventName: string) =
  var board = entity.board
  assert board != nil
  board.broadcastEvent(eventName)

method stmtSend(execState: ScriptExecState, dirOrPos: ScriptVal, eventName: string) {.base, locks: "unknown".} =
  case dirOrPos.kind
  of svkEntity:
    var entity = dirOrPos.entityRef
    if entity != nil:
      if entity.alive:
        entity.tickEvent(eventName)

  of svkPlayer:
    var player = dirOrPos.playerRef
    if player != nil:
      if player.alive:
        player.tickEvent(eventName)

  else:
    var share = execState.share
    assert share != nil
    var world = share.world
    assert world != nil

    var (boardName, x, y) = execState.resolvePos(dirOrPos)
    var board = try:
        world.boards[boardName]
      except KeyError:
        raise newException(ScriptExecError, &"Board \"{boardName}\" does not exist")
    assert board != nil
    board.sendEventToPos(eventName, x, y)

method stmtSpawn(execState: ScriptExecState, entityName: string, dirOrPos: ScriptVal, spawnBody: seq[ScriptNode], spawnElse: seq[ScriptNode]): Entity {.base, locks: "unknown".} =
  var share = execState.share
  assert share != nil
  var world = share.world
  assert world != nil

  var (boardName, x, y) = execState.resolvePos(dirOrPos)
  var board = try:
      # FIXME getBoard causes a crash under some circumstances, need to fix this --GM
      #world.getBoard(boardName)
      world.boards[boardName]
    except KeyError:
      raise newException(ScriptExecError, &"Board \"{boardName}\" does not exist")
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
          of satMul: ScriptVal(kind: svkInt, intVal: assignDst.asInt() * assignSrc.asInt())
          else:
            raise newException(ScriptExecError, &"Unhandled assignment type {assignType}")

        execState.storeAtExpr(assignDstExpr, assignResult)

      of snkDie:
        execState.stmtDie()
        return

      of snkForceMove:
        var moveDir = execState.resolveExpr(node.forceMoveDirExpr)
        case moveDir.kind
          of svkDir: execState.stmtForceMovePerformRel(moveDir.dirValX, moveDir.dirValY)
          of svkPos: execState.stmtForceMovePerformAbs(moveDir.posBoardName, moveDir.posValX, moveDir.posValY)
          else:
            raise newException(ScriptExecError, &"Expected dir, got {moveDir} instead")

      of snkGoto:
        var stateName: string = node.gotoStateName
        execState.activeState = stateName
        execState.continuations.setLen(0)
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
          of svkPos: execState.stmtMovePerformAbs(moveDir.posBoardName, moveDir.posValX, moveDir.posValY)
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
        var sayStr: string = sayExpr.asCoercedStr()

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

      of snkSpawn, snkSpawnInto:
        var dstExpr = case node.kind
          of snkSpawn: nil
          of snkSpawnInto: node.spawnIntoDstExpr
          else:
            raise newException(ScriptExecError, &"EDOOFUS: Unhandled spawn type {node}!")
        var dirOrPos = execState.resolveExpr(node.spawnPos)
        var entityName: string = node.spawnEntityName
        var spawnBody = node.spawnBody
        var spawnElse = node.spawnElse

        var newEntity = execState.stmtSpawn(entityName, dirOrPos, spawnBody, spawnElse)
        if newEntity == nil:
          execState.continuations.add(cont)
          cont = ScriptContinuation(codeBlock: node.spawnElse, codePc: 0)
        else:
          newEntity.customiseFromBody(execState, spawnBody)

        case node.kind
          of snkSpawn: discard
          of snkSpawnInto:
            execState.storeAtExpr(dstExpr, ScriptVal(kind: svkEntity, entityRef: newEntity))
          else:
            raise newException(ScriptExecError, &"EDOOFUS: Unhandled spawn type {node}!")

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
    execState.continuations.setLen(0)
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
  assert execBase != nil
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
