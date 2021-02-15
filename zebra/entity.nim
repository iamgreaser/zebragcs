import tables

import ./types

proc hasPhysBlock*(entity: Entity): bool
proc moveBy*(entity: Entity, dx: int64, dy: int64): bool
proc moveTo*(entity: Entity, x: int64, y: int64): bool
proc newEntity*(board: Board, entityType: string, x, y: int64): Entity
proc tick*(entity: Entity)
proc tickEvent*(entity: Entity, eventName: string)

import ./board
import ./script/compile
import ./script/exprs
import ./script/exec


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
    locals: Table[string, ScriptVal](),
    alive: true,
  )
  execState.entity = entity
  # Initialise!
  for k0, v0 in execBase.params.pairs():
    entity.params[k0] = execState.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.pairs():
    entity.locals[k0] = execState.resolveExpr(v0.varDefault)

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

proc canMoveTo(entity: Entity, x: int64, y: int64): bool =
  var board = entity.board
  if board == nil:
    false
  elif x == entity.x and y == entity.y:
    false
  else:
    board.canAddEntityToGridPos(entity, x, y)

proc moveTo(entity: Entity, x: int64, y: int64): bool =
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

proc moveBy(entity: Entity, dx: int64, dy: int64): bool =
  entity.moveTo(entity.x + dx, entity.y + dy)

proc hasPhysBlock(entity: Entity): bool =
  try:
    entity.params["physblock"].asBool()
  except KeyError:
    true

proc tick(entity: Entity) =
  entity.execState.tick()

proc tickEvent(entity: Entity, eventName: string) =
  entity.execState.tickEvent(eventName)
