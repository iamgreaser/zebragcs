
import types

proc addEntityToGrid*(board: Board, entity: Entity)
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
  if not (x >= 0 and x < 60 and y >= 0 and y < 25): # TODO: Put width/height into the Board --GM
    false
  else:
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
