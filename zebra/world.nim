import strformat
import strutils

import ./interntables
import ./types

proc broadcastEvent*(world: World, node: ScriptNode, eventNameIdx: InternKey)
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

  # Now load entity types
  for entityTypeFileName in share.vfs.vfsFileList(@["scripts", "entities"]):
    if entityTypeFileName.endsWith(".script"):
      var entityTypeName = entityTypeFileName[0..(^8)]
      echo &"Reserving entity type \"{entityTypeName}\""
      share.entityTypeNames.add(internKey(entityTypeName))

  for entityTypeFileName in share.vfs.vfsFileList(@["scripts", "entities"]):
    if entityTypeFileName.endsWith(".script"):
      var entityTypeName = entityTypeFileName[0..(^8)]
      echo &"Loading entity type \"{entityTypeName}\""
      share.loadEntityTypeFromFile(entityTypeName)

  # Now load boards
  for boardName in share.vfs.vfsDirList(@["boards"]):
    echo &"Loading board \"{boardName}\""
    discard world.loadBoardFromFile(boardName)

  # Return
  world

proc broadcastEvent(world: World, node: ScriptNode, eventNameIdx: InternKey) =
  world.tickEvent(node, eventNameIdx)
  var boardsCopy: seq[Board] = @[]
  for board in world.boards.values():
    boardsCopy.add(board)
  for board in boardsCopy:
    board.broadcastEvent(node, eventNameIdx)

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
