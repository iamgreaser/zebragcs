import tables

import ./types

proc addEntityToGrid*(board: Board, entity: Entity)
proc broadcastEvent*(board: Board, eventName: string)
proc sendEventToPos*(board: Board, eventName: string, x: int64, y: int64)
proc canAddEntityToGridPos*(board: Board, entity: Entity, x: int64, y: int64): bool
proc newBoard*(share: ScriptSharedExecState, controllerName: string): Board
proc removeEntityFromGrid*(board: Board, entity: Entity)

import ./script/exec
method tick*(board: Board)

import ./entity
import ./script/compile
import ./script/exprs

proc getBoardController(share: ScriptSharedExecState, controllerName: string): ScriptExecBase =
  try:
    share.boardControllers[controllerName]
  except KeyError:
    share.loadBoardControllerFromFile(controllerName)
    share.boardControllers[controllerName]

proc newBoard(share: ScriptSharedExecState, controllerName: string): Board =
  var execBase = share.getBoardController(controllerName)

  var board = Board(
    entities: @[],
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
    board.params[k0] = board.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.pairs():
    board.locals[k0] = board.resolveExpr(v0.varDefault)

  board

proc canAddEntityToGridPos(board: Board, entity: Entity, x: int64, y: int64): bool =
  if not (x >= 0 and x < boardWidth and y >= 0 and y < boardHeight):
    false
  else:
    var gridseq = board.grid[y][x]
    if gridseq.len == 0:
      return true

    var i: int64 = gridseq.len-1
    while i >= 0:
      var other = gridseq[i]
      if other.hasPhysBlock():
        return false
      i -= 1

    true

proc addEntityToGrid(board: Board, entity: Entity) =
  assert board.canAddEntityToGridPos(entity, entity.x, entity.y)
  board.grid[entity.y][entity.x].add(entity)

proc removeEntityFromGrid(board: Board, entity: Entity) =
  var gridseq = board.grid[entity.y][entity.x]
  var i: int64 = 0
  while i < gridseq.len:
    if gridseq[i] == entity:
      gridseq.delete(i)
    else:
      i += 1

  board.grid[entity.y][entity.x] = gridseq
  discard

proc broadcastEvent(board: Board, eventName: string) =
  var entitiesCopy: seq[Entity] = @[]
  for entity in board.entities:
    entitiesCopy.add(entity)
  for entity in entitiesCopy:
    entity.tickEvent(eventName)

proc sendEventToPos(board: Board, eventName: string, x: int64, y: int64) =
  if (x >= 0 and x < boardWidth and y >= 0 and y < boardHeight):
    var entseq = board.grid[y][x]
    if entseq.len >= 1:
      var entity = entseq[entseq.len-1]
      entity.tickEvent(eventName)

method tick(board: Board) =
  procCall tick(ScriptExecState(board))

  var entitiesCopy: seq[Entity] = @[]
  for entity in board.entities:
    entitiesCopy.add(entity)
  for entity in entitiesCopy:
    entity.tick()

  # Remove dead entities
  entitiesCopy = @[]
  for entity in board.entities:
    if entity.alive:
      entitiesCopy.add(entity)
    else:
      board.removeEntityFromGrid(entity)
  board.entities = entitiesCopy
