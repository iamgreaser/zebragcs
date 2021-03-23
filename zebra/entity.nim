import strformat

import ./interntables
import ./types

proc customiseFromBody*(entity: Entity, execState: ScriptExecState, body: seq[ScriptNode])
proc forceMoveBy*(entity: Entity, dx: int64, dy: int64)
proc forceMoveTo*(entity: Entity, board: Board, x: int64, y: int64)
proc hasPhysBlock*(entity: Entity): bool
proc hasPhysGhost*(entity: Entity): bool
proc moveBy*(entity: Entity, dx: int64, dy: int64): bool
proc moveTo*(entity: Entity, board: Board, x: int64, y: int64): bool
proc newEntity*(board: Board, entityType: InternKey, x, y: int64, forced: bool = false): Entity

import ./board
import ./script/exprs


proc getEntityType(share: ScriptSharedExecState, entityNameIdx: InternKey): ScriptExecBase =
  try:
    share.entityTypes[entityNameIdx]
  except KeyError:
    raise newException(Exception, &"entity type \"{entityNameIdx.getInternName()}\" not found")
    #share.loadEntityTypeFromFile(entityNameIdx.getInternName())
    #share.entityTypes[entityNameIdx]

proc newEntity(board: Board, entityType: InternKey, x, y: int64, forced: bool = false): Entity =
  var share = board.share
  assert share != nil
  var execBase = share.getEntityType(entityType)
  var entity = Entity(
    board: board,
    x: x, y: y,
    execBase: execBase,
    activeStateIdx: execBase.initStateIdx,
    params: initInternTable[ScriptVal](),
    locals: initInternTable[ScriptVal](),
    alive: true,
    share: share,
    sleepTicksLeft: 0,
  )

  # Initialise!
  for k0, v0 in execBase.params.indexedPairs():
    entity.params[k0] = entity.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.indexedPairs():
    entity.locals[k0] = entity.resolveExpr(v0.varDefault)

  # Now attempt to see if we can add it
  if board.canAddEntityToGridPos(entity, entity.x, entity.y, forced = forced):
    # Yes - add and return it
    board.addEntityToGrid(entity)
    board.entities.add(entity)
    entity
  else:
    # No - invalidate and return nil
    entity.alive = false
    nil

proc customiseFromBody(entity: Entity, execState: ScriptExecState, body: seq[ScriptNode]) =
  for spawnNode in body:
    case spawnNode.kind
    of snkAssign:
      var spawnNodeDstExpr = spawnNode.assignDstExpr
      var spawnNodeSrc = execState.resolveExpr(spawnNode.assignSrcExpr)
      case spawnNode.assignType
      of satSet:
        case spawnNodeDstExpr.kind
        of snkParamVar:
          # TODO: Confirm types --GM
          entity.params[spawnNodeDstExpr.paramVarNameIdx] = spawnNodeSrc
        else:
          raise newException(ScriptExecError, &"Unhandled spawn assignment destination {spawnNodeDstExpr}")
      else:
        raise newException(ScriptExecError, &"Unhandled spawn statement/block kind {spawnNode}")
    else:
      raise newException(ScriptExecError, &"Unhandled spawn statement/block kind {spawnNode}")

proc canMoveTo(entity: Entity, board: Board, x: int64, y: int64): bool =
  if board == nil:
    false
  elif x == entity.x and y == entity.y:
    false
  else:
    board.canAddEntityToGridPos(entity, x, y)

proc forceMoveTo(entity: Entity, board: Board, x: int64, y: int64) =
  assert board != nil
  var srcBoard = entity.board
  assert srcBoard != nil
  var dstBoard = board
  assert dstBoard != nil
  if x != entity.x or y != entity.y or srcBoard != dstBoard:
    srcBoard.removeEntityFromGrid(entity)
    entity.x = x
    entity.y = y
    if srcBoard != dstBoard:
      srcBoard.removeEntityFromList(entity)
      dstBoard.addEntityToList(entity)
      entity.board = dstBoard
    dstBoard.addEntityToGrid(entity)

proc forceMoveBy(entity: Entity, dx: int64, dy: int64) =
  entity.forceMoveTo(entity.board, entity.x + dx, entity.y + dy)

proc moveTo(entity: Entity, board: Board, x: int64, y: int64): bool =
  assert board != nil
  var canMove = entity.canMoveTo(board, x, y)
  if canMove:
    var srcBoard = entity.board
    assert srcBoard != nil
    var dstBoard = board
    assert dstBoard != nil
    if x != entity.x or y != entity.y or srcBoard != dstBoard:
      srcBoard.removeEntityFromGrid(entity)
      entity.x = x
      entity.y = y
      if srcBoard != dstBoard:
        srcBoard.removeEntityFromList(entity)
        dstBoard.addEntityToList(entity)
        entity.board = dstBoard
      dstBoard.addEntityToGrid(entity)
    true
  else:
    false

proc moveBy(entity: Entity, dx: int64, dy: int64): bool =
  entity.moveTo(entity.board, entity.x + dx, entity.y + dy)

proc hasPhysBlock(entity: Entity): bool =
  entity.params["physblock"].asBool(nil)

proc hasPhysGhost(entity: Entity): bool =
  entity.params["physghost"].asBool(nil)
