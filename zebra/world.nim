import strformat

import ./interntables
import ./types

proc broadcastEvent*(world: World, eventNameIdx: InternKey)
proc loadWorld*(worldName: string): World

import ./script/exec

method tick*(world: World)

import ./board
import ./player
import ./script/compile
import ./script/exprs
import ./vfs/disk
import ./vfs/types as vfsTypes

proc getWorldController(share: ScriptSharedExecState): ScriptExecBase =
  if share.worldController == nil:
    share.loadWorldControllerFromFile()

  share.worldController

proc loadWorld(worldName: string): World =
  echo &"Loading world \"{worldName}\""

  var share = newScriptSharedExecState(
    vfs = newDiskFs(
      rootDir = &"worlds/{worldName}/",
    ),
  )
  assert share != nil
  assert share.world == nil

  var execBase = share.getWorldController()
  assert execBase != nil
  var world = World(
    name: worldName,
    boards: initInternTable[Board](),
    tickTitle: false,
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
    world.params[k0] = world.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.indexedPairs():
    world.locals[k0] = world.resolveExpr(v0.varDefault)

  share.world = world

  # Now load boards
  for boardName in share.vfs.vfsDirList(@["boards"]):
    echo &"Loading board \"{boardName}\""
    discard world.loadBoardFromFile(boardName)

  # Return
  world

proc broadcastEvent(world: World, eventNameIdx: InternKey) =
  world.tickEvent(eventNameIdx)
  var boardsCopy: seq[Board] = @[]
  for board in world.boards.values():
    boardsCopy.add(board)
  for board in boardsCopy:
    board.broadcastEvent(eventNameIdx)

method tick(world: World) =
  # Tick world
  procCall tick(ScriptExecState(world))

  # Tick players
  for player in world.players:
    player.tick()

  # Work out which boards to tick
  var boardsToTick: seq[Board] = @[]
  if world.tickTitle:
    boardsToTick.add(world.boards["title"])
  for player in world.players:
    var (board, _, _) = player.getCamera()
    if board != nil:
      boardsToTick.add(board)

  # Tick those boards specifically
  for board in boardsToTick:
    board.tick()
