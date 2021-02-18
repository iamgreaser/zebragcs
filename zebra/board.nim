import streams
import strformat
import strutils
import tables

import ./types

proc addEntityToGrid*(board: Board, entity: Entity)
proc addEntityToList*(board: Board, entity: Entity)
proc broadcastEvent*(board: Board, eventName: string)
proc canAddEntityToGridPos*(board: Board, entity: Entity, x: int64, y: int64): bool
proc getBoard*(world: World, boardName: string): var Board
proc loadBoardFromFile*(world: World, boardName: string): Board
proc removeEntityFromGrid*(board: Board, entity: Entity)
proc removeEntityFromList*(board: Board, entity: Entity)
proc sendEventToPos*(board: Board, eventName: string, x: int64, y: int64)


import ./script/exec

import ./entity
import ./grid
import ./script/compile
import ./script/exprs
import ./script/tokens

proc getBoardController(share: ScriptSharedExecState, controllerName: string): ScriptExecBase =
  try:
    share.boardControllers[controllerName]
  except KeyError:
    share.loadBoardControllerFromFile(controllerName)
    share.boardControllers[controllerName]

proc getBoard(world: World, boardName: string): var Board =
  try:
    return world.boards[boardName]
  except KeyError:
    # FIXME: The lookup for this is broken and results in crashes --GM
    #raise newException(Exception, &"board \"{boardName}\" not found")
    discard world.loadBoardFromFile(boardName)
    return world.boards[boardName]

proc loadBoardInfo(strm: Stream, boardName: string): BoardInfo =
  var boardInfo = BoardInfo(
    boardName: boardName,
    controllerName: "default",
    w: 0, h: 0,
  )
  var hasSize = false
  var hasControllerName = false
  var sps = ScriptParseState(
    strm: strm,
    row: 1, col: 1,
    tokenPushStack: @[],
  )

  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEof: break # Exit condition
    of stkEol: discard
    of stkWord:
      case tok.wordVal.toLowerAscii()

      of "controller":
        if hasControllerName:
          raise newScriptParseError(sps, &"\"controller\" already defined earlier")
        boardInfo.controllerName = sps.readExpectedToken(stkWord).wordVal
        sps.expectEolOrEof()
        hasControllerName = true

      of "size":
        if hasSize:
          raise newScriptParseError(sps, &"\"size\" already defined earlier")
        boardInfo.w = sps.readExpectedToken(stkInt).intVal
        boardInfo.h = sps.readExpectedToken(stkInt).intVal
        sps.expectEolOrEof()
        hasSize = true

      else:
        raise newScriptParseError(sps, &"Expected expression, got {tok} instead")
    else:
      raise newScriptParseError(sps, &"Expected expression, got {tok} instead")

  if not hasSize:
    raise newException(BoardLoadError, &"board \"{boardName}\" was not given a size in \"boards/{boardName}/board.info\"")
  if not (boardInfo.w >= 1 and boardInfo.h >= 1):
    raise newException(BoardLoadError, &"board \"{boardName}\" has invalid size {boardInfo.w} x {boardInfo.h}")

  # Return!
  boardInfo

proc loadBoard(world: World, boardName: string, strm: Stream): Board =
  var share = world.share
  assert share != nil
  
  if world.boards.contains(boardName):
    raise newException(BoardLoadError, &"board \"{boardName}\" already assigned")

  var boardInfo = loadBoardInfo(strm, boardName)
  assert boardInfo != nil

  var execBase = share.getBoardController(boardInfo.controllerName)
  assert execBase != nil
  var board = Board(
    boardName: boardName,
    world: world,
    grid: newGrid[seq[Entity]](
      w = boardInfo.w,
      h = boardInfo.h,
      default = (proc(): seq[Entity] = newSeq[Entity]())),
    entities: @[],
    execBase: execBase,
    activeState: execBase.initState,
    params: Table[string, ScriptVal](),
    locals: Table[string, ScriptVal](),
    alive: true,
    share: share,
    sleepTicksLeft: 0,
  )

  world.boards[boardName] = board

  # Initialise!
  for k0, v0 in execBase.params.pairs():
    board.params[k0] = board.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.pairs():
    board.locals[k0] = board.resolveExpr(v0.varDefault)

  board

proc loadBoardFromFile(world: World, boardName: string): Board =
  var share = world.share
  assert share != nil
  var fname = (&"{share.rootDir}/boards/{boardName}/board.info").replace("//", "/")
  var strm = newFileStream(fname, fmRead)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    world.loadBoard(boardName, strm)
  finally:
    strm.close()

proc canAddEntityToGridPos(board: Board, entity: Entity, x: int64, y: int64): bool =
  if not (x >= 0 and x < board.grid.w and y >= 0 and y < board.grid.h):
    false
  else:
    if entity.hasPhysGhost():
      return true

    var entseq = board.grid[x, y]
    if entseq.len == 0:
      return true

    var i: int64 = entseq.len-1
    while i >= 0:
      var other = entseq[i]
      if other.hasPhysBlock():
        return false
      i -= 1

    true

proc addEntityToGrid(board: Board, entity: Entity) =
  # May be useful for safety, but clashes with forcemove. --GM
  #assert board.canAddEntityToGridPos(entity, entity.x, entity.y)

  board.grid[entity.x, entity.y].add(entity)

proc addEntityToList(board: Board, entity: Entity) =
  if not board.entities.contains(entity):
    board.entities.add(entity)

proc removeEntityFromGrid(board: Board, entity: Entity) =
  var entseq = board.grid[entity.x, entity.y]
  var i: int64 = 0
  while i < entseq.len:
    if entseq[i] == entity:
      entseq.delete(i)
    else:
      i += 1

  board.grid[entity.x, entity.y] = entseq
  discard

proc removeEntityFromList(board: Board, entity: Entity) =
  var i: int64 = 0
  while i < board.entities.len:
    if board.entities[i] == entity:
      board.entities.delete(i)
    else:
      i += 1


proc broadcastEvent(board: Board, eventName: string) =
  var entitiesCopy: seq[Entity] = @[]
  for entity in board.entities:
    entitiesCopy.add(entity)
  board.tickEvent(eventName)
  for entity in entitiesCopy:
    entity.tickEvent(eventName)

proc sendEventToPos(board: Board, eventName: string, x: int64, y: int64) =
  if (x >= 0 and x < board.grid.w and y >= 0 and y < board.grid.h):
    var entseq = board.grid[x, y]
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
