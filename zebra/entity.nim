import tables

import ./types

proc hasPhysBlock*(entity: Entity): bool
proc moveBy*(entity: Entity, dx: int64, dy: int64): bool
proc moveTo*(entity: Entity, board: Board, x: int64, y: int64): bool
proc newEntity*(board: Board, entityType: string, x, y: int64): Entity

import ./board
import ./script/compile
import ./script/exprs


proc getEntityType(share: ScriptSharedExecState, entityName: string): ScriptExecBase =
  try:
    share.entityTypes[entityName]
  except KeyError:
    share.loadEntityTypeFromFile(entityName)
    share.entityTypes[entityName]

proc newEntity(board: Board, entityType: string, x, y: int64): Entity =
  var share = board.share
  assert share != nil
  var execBase = share.getEntityType(entityType)
  var entity = Entity(
    board: board,
    x: x, y: y,
    execBase: execBase,
    activeState: execBase.initState,
    params: Table[string, ScriptVal](),
    locals: Table[string, ScriptVal](),
    alive: true,
    share: share,
    sleepTicksLeft: 0,
  )

  # Initialise!
  for k0, v0 in execBase.params.pairs():
    entity.params[k0] = entity.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.pairs():
    entity.locals[k0] = entity.resolveExpr(v0.varDefault)

  # Now attempt to see if we can add it
  if board.canAddEntityToGridPos(entity, entity.x, entity.y):
    # Yes - add and return it
    board.addEntityToGrid(entity)
    board.entities.add(entity)
    entity
  else:
    # No - invalidate and return nil
    entity.alive = false
    nil

proc canMoveTo(entity: Entity, board: Board, x: int64, y: int64): bool =
  var board = entity.board
  if board == nil:
    false
  elif x == entity.x and y == entity.y:
    false
  else:
    board.canAddEntityToGridPos(entity, x, y)

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
  try:
    entity.params["physblock"].asBool()
  except KeyError:
    true
