import types

proc addEntityToGrid*(board: Board, entity: Entity)
proc broadcastEvent*(board: Board, eventName: string)
proc sendEventToPos*(board: Board, eventName: string, x: int, y: int)
proc canAddEntityToGridPos*(board: Board, entity: Entity, x: int, y: int): bool
proc newBoard*(share: ScriptSharedExecState): Board
proc removeEntityFromGrid*(board: Board, entity: Entity)
proc tick*(board: Board)

import entity

proc newBoard(share: ScriptSharedExecState): Board =
  Board(
    share: share,
    entities: @[],
  )

proc canAddEntityToGridPos(board: Board, entity: Entity, x: int, y: int): bool =
  if not (x >= 0 and x < boardWidth and y >= 0 and y < boardHeight):
    false
  else:
    var gridseq = board.grid[y][x]
    if gridseq.len == 0:
      return true

    var i: int = gridseq.len-1
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
  var i: int = 0
  while i < gridseq.len:
    if gridseq[i] == entity:
      gridseq.delete(i)
    else:
      i += 1

  board.grid[entity.y][entity.x] = gridseq
  discard

proc broadcastEvent(board: Board, eventName: string) =
  for entity in board.entities:
    entity.tickEvent(eventName)

proc sendEventToPos(board: Board, eventName: string, x: int, y: int) =
  if (x >= 0 and x < boardWidth and y >= 0 and y < boardHeight):
    var entseq = board.grid[y][x]
    if entseq.len >= 1:
      var entity = entseq[entseq.len-1]
      entity.tickEvent(eventName)

proc tick(board: Board) =
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
