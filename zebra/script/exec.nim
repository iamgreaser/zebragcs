import strformat
import ../interntables
import ../types

method tick*(execState: ScriptExecState) {.base, locks: "unknown".}
proc tickEvent*(execState: ScriptExecState, node: ScriptNode, eventNameIdx: InternKey, args: seq[ScriptVal] = @[])

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

method stmtForceMovePerformRel(execState: ScriptExecState, node: ScriptNode, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for move")
method stmtForceMovePerformRel(entity: Entity, node: ScriptNode, dx, dy: int64): bool =
  entity.forceMoveBy(dx, dy)

method stmtForceMovePerformAbs(execState: ScriptExecState, node: ScriptNode, boardNameIdx: InternKey, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for move")
method stmtForceMovePerformAbs(entity: Entity, node: ScriptNode, boardNameIdx: InternKey, dx, dy: int64): bool =
  entity.forceMoveTo(entity.board.world.boards[boardNameIdx], dx, dy)

method stmtMovePerformRel(execState: ScriptExecState, node: ScriptNode, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for move")
method stmtMovePerformRel(entity: Entity, node: ScriptNode, dx, dy: int64): bool =
  entity.moveBy(dx, dy)

method stmtMovePerformAbs(execState: ScriptExecState, node: ScriptNode, boardNameIdx: InternKey, dx, dy: int64): bool {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for move")
method stmtMovePerformAbs(entity: Entity, node: ScriptNode, boardNameIdx: InternKey, dx, dy: int64): bool =
  entity.moveTo(entity.board.world.boards[boardNameIdx], dx, dy)

method stmtBroadcast(execState: ScriptExecState, node: ScriptNode, eventNameIdx: InternKey) {.base, locks: "unknown".} =
  raise node.newScriptExecError(&"Unexpected type {execState} for broadcast")
method stmtBroadcast(entity: Entity, node: ScriptNode, eventNameIdx: InternKey) =
  var board = entity.board
  assert board != nil
  board.broadcastEvent(node, eventNameIdx)

method stmtSend(execState: ScriptExecState, node: ScriptNode, dirOrPos: ScriptVal, eventNameIdx: InternKey, sendArgNodes: seq[ScriptNode]) {.base, locks: "unknown".} =
  var sendArgs: seq[ScriptVal] = @[]
  for argNode in sendArgNodes:
    sendArgs.add(execState.resolveExpr(argNode))

  case dirOrPos.kind
  of svkEntity:
    var entity = dirOrPos.entityRef
    if entity != nil:
      if entity.alive:
        entity.tickEvent(node, eventNameIdx, sendArgs)

  of svkPlayer:
    var player = dirOrPos.playerRef
    if player != nil:
      if player.alive:
        player.tickEvent(node, eventNameIdx, sendArgs)

  else:
    var share = execState.share
    assert share != nil
    var world = share.world
    assert world != nil

    var (boardNameIdx, x, y) = execState.resolvePos(node, dirOrPos)
    var board = try:
        world.boards[boardNameIdx]
      except KeyError:
        raise node.newScriptExecError(&"Board \"{boardNameIdx.getInternName()}\" does not exist")
    assert board != nil
    board.sendEventToPos(node, eventNameIdx, x, y, sendArgs)

method stmtSpawn(execState: ScriptExecState, node: ScriptNode, entityNameIdx: InternKey, dirOrPos: ScriptVal, spawnBody: seq[ScriptNode], spawnElse: seq[ScriptNode]): Entity {.base, locks: "unknown".} =
  var share = execState.share
  assert share != nil
  var world = share.world
  assert world != nil

  var (boardNameIdx, x, y) = execState.resolvePos(node, dirOrPos)
  var board = try:
      # FIXME getBoard causes a crash under some circumstances, need to fix this --GM
      #world.getBoard(boardName)
      world.boards[boardNameIdx]
    except KeyError:
      raise node.newScriptExecError(&"Board \"{boardNameIdx.getInternName()}\" does not exist")
  assert board != nil

  var newEntity = board.newEntity(entityNameIdx, x, y)
  return newEntity

proc tickContinuations(execState: ScriptExecState, lowerBound: uint64) =
  while uint64(execState.continuations.len) > lowerBound:
    var cont = execState.continuations[^1]
    if not (cont.codePc < cont.codeBlock.len):
      #echo &"{cont.codePc} < {cont.codeBlock.len}"
      assert cont.codePc == cont.codeBlock.len
      execState.continuations.setLen(execState.continuations.len-1)
      continue
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
        of satDec: ScriptVal(kind: svkInt, intVal: assignDst.asInt(node.assignDstExpr) - assignSrc.asInt(node.assignSrcExpr))
        of satInc: ScriptVal(kind: svkInt, intVal: assignDst.asInt(node.assignDstExpr) + assignSrc.asInt(node.assignSrcExpr))
        of satMul: ScriptVal(kind: svkInt, intVal: assignDst.asInt(node.assignDstExpr) * assignSrc.asInt(node.assignSrcExpr))
        else:
          raise node.newScriptExecError(&"Unhandled assignment type {assignType}")

      execState.storeAtExpr(assignDstExpr, assignResult)

    of snkDie:
      execState.stmtDie()
      return

    of snkForceMove:
      var moveDir = execState.resolveExpr(node.forceMoveDirExpr)
      case moveDir.kind
        of svkDir: execState.stmtForceMovePerformRel(node.forceMoveDirExpr, moveDir.dirValX, moveDir.dirValY)
        of svkPos: execState.stmtForceMovePerformAbs(node.forceMoveDirExpr, moveDir.posBoardNameIdx, moveDir.posValX, moveDir.posValY)
        else:
          raise node.forceMoveDirExpr.newScriptExecError(&"Expected dir, got {moveDir} instead")

    of snkGoto:
      var stateNameIdx: InternKey = node.gotoStateNameIdx
      execState.activeStateIdx = stateNameIdx
      execState.continuations.setLen(0)
      return

    of snkIfBlock:
      var test = execState.resolveExpr(node.ifTest)
      var body =
        if test.asBool(node.ifTest):
          node.ifBody
        else:
          node.ifElse
      cont = ScriptContinuation(codeBlock: body, codePc: 0)
      execState.continuations.add(cont)

    of snkWhileBlock:
      var test = execState.resolveExpr(node.whileTest)
      var body = node.whileBody
      if test.asBool(node.whileTest):
        cont.codePc = nodePc # Step back to here
        cont = ScriptContinuation(codeBlock: body, codePc: 0)
        execState.continuations.add(cont)

    of snkLayerPrintLeft, snkLayerPrintRight:
      var layerNameIdx = node.layerPrintNameIdx
      var x0 = execState.resolveExpr(node.layerPrintX).asInt(node.layerPrintX)
      var y0 = execState.resolveExpr(node.layerPrintY).asInt(node.layerPrintY)
      var fg = execState.resolveExpr(node.layerPrintFg).asInt(node.layerPrintFg)
      var bg = execState.resolveExpr(node.layerPrintBg).asInt(node.layerPrintBg)
      var s = execState.resolveExpr(node.layerPrintStr).asCoercedStr(node.layerPrintStr)
      if node.kind == snkLayerPrintRight:
        x0 -= s.len-1
      let y = y0
      var i = 0
      while i < s.len:
        var x = i + x0
        var pos = execState.funcAt(node, x, y)
        var ch = s[i]
        execState.setfuncLayer(node, layerNameIdx, pos,
          ScriptVal(kind: svkCell, cellVal: LayerCell(ch: uint16(ch), fg: uint8(fg), bg: uint8(bg))))
        i += 1

    of snkLayerRectFill:
      var layerNameIdx = node.layerRectNameIdx
      var cell: ScriptVal = execState.resolveExpr(node.layerRectCell)
      var x0 = execState.resolveExpr(node.layerRectX).asInt(node.layerRectX)
      var y0 = execState.resolveExpr(node.layerRectY).asInt(node.layerRectY)
      var w = execState.resolveExpr(node.layerRectWidth).asInt(node.layerRectWidth)
      var h = execState.resolveExpr(node.layerRectHeight).asInt(node.layerRectHeight)
      if w >= 1 and h >= 1:
        for y in (y0..(y0+h-1)):
          for x in (x0..(x0+w-1)):
            var pos = execState.funcAt(node, x, y)
            execState.setfuncLayer(node, layerNameIdx, pos, cell)

    of snkListAppend:
      var dst = node.listAppendDst
      var val = execState.resolveExpr(node.listAppendVal)
      var oldSrc = execState.resolveExpr(dst)

      if oldSrc.kind != svkList:
        raise node.newScriptExecError(&"Expected list, got {oldSrc} instead")
      if not matchesTypeOfVal(oldSrc.listCellType, val):
        raise node.newScriptExecError(&"Expected cell type {oldSrc.listCellType}, got {val.kind} instead")

      # FIXME: This is probably slow --GM
      var newList: seq[ScriptVal] = @[]
      for v in oldSrc.listCells:
        newList.add(v)
      newList.add(val)

      execState.storeAtExpr(dst, ScriptVal(
        kind: svkList,
        listCellType: oldSrc.listCellType,
        listCells: newList,
      ))

    of snkMove:
      var moveDir = execState.resolveExpr(node.moveDirExpr)
      var didMove = case moveDir.kind
        of svkDir: execState.stmtMovePerformRel(node.moveDirExpr, moveDir.dirValX, moveDir.dirValY)
        of svkPos: execState.stmtMovePerformAbs(node.moveDirExpr, moveDir.posBoardNameIdx, moveDir.posValX, moveDir.posValY)
        else:
          raise node.moveDirExpr.newScriptExecError(&"Expected dir, got {moveDir} instead")

      if not didMove:
        var body = node.moveElse
        cont = ScriptContinuation(codeBlock: body, codePc: 0)
        execState.continuations.add(cont)

    of snkBroadcast:
      var eventNameIdx: InternKey = node.broadcastEventNameIdx
      execState.stmtBroadcast(node, eventNameIdx)

    of snkSay:
      var sayExpr = execState.resolveExpr(node.sayExpr)
      var sayStr: string = sayExpr.asCoercedStr(node.sayExpr)

      # TODO: Actually put it in the window somewhere --GM
      echo &"SAY: [{sayStr}]"

    of snkSend:
      var dirOrPos = execState.resolveExpr(node.sendPos)
      var eventNameIdx: InternKey = node.sendEventNameIdx
      execState.stmtSend(node, dirOrPos, eventNameIdx, node.sendArgs)

    of snkSleep:
      var sleepTime = execState.resolveExpr(node.sleepTimeExpr).asInt(node.sleepTimeExpr)
      if sleepTime >= 1:
        execState.sleepTicksLeft = sleepTime
        return

    of snkSpawn, snkSpawnInto:
      var dstExpr = case node.kind
        of snkSpawn: nil
        of snkSpawnInto: node.spawnIntoDstExpr
        else:
          raise node.newScriptExecError(&"EDOOFUS: Unhandled spawn type {node}!")
      var dirOrPos = execState.resolveExpr(node.spawnPos)
      var entityNameIdx: InternKey = node.spawnEntityNameIdx
      var spawnBody = node.spawnBody
      var spawnElse = node.spawnElse

      var newEntity = execState.stmtSpawn(node, entityNameIdx, dirOrPos, spawnBody, spawnElse)
      if newEntity == nil:
        cont = ScriptContinuation(codeBlock: node.spawnElse, codePc: 0)
        execState.continuations.add(cont)
      else:
        newEntity.customiseFromBody(execState, spawnBody)

      case node.kind
        of snkSpawn: discard
        of snkSpawnInto:
          execState.storeAtExpr(dstExpr, ScriptVal(kind: svkEntity, entityRef: newEntity))
        else:
          raise node.newScriptExecError(&"EDOOFUS: Unhandled spawn type {node}!")

    else:
      raise node.newScriptExecError(&"Unhandled statement/block kind {node.kind}")

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
    var activeStateIdx = execState.activeStateIdx
    var stateBlock = execBase.states[activeStateIdx]
    execState.continuations.add(
      ScriptContinuation(
        codeBlock: stateBlock.stateBody,
        codePc: 0,
      )
    )

  execState.tickContinuations(lowerBound=0'u64)

proc tickEvent(execState: ScriptExecState, node: ScriptNode, eventNameIdx: InternKey, args: seq[ScriptVal] = @[]) =
  var execBase = execState.execBase
  assert execBase != nil
  var eventBlock = try:
      execBase.events[eventNameIdx]
    except KeyError:
      return # If we don't have a handler for this event, then ignore it.

  # Set variables
  # TODO: Tie this to some sort of dynamic binding stack --GM
  if args.len != eventBlock.eventParams.len:
    raise node.newScriptExecError(&"send arg mismatch for event {eventNameIdx.getInternName()} to entity type {execBase.entityNameIdx.getInternName()}: expected {eventBlock.eventParams.len}, got {args.len}")

  for i in 0..(args.len-1):
    var arg = args[i]
    var param = eventBlock.eventParams[i]
    execState.storeAtExpr(param, arg)

  # Push a continuation and tick away
  execState.continuations.add(
    ScriptContinuation(
      codeBlock: eventBlock.eventBody,
      codePc: 0,
    )
  )
  execState.tickContinuations(lowerBound=uint64(execState.continuations.len-1))
