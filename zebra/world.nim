import os
import strformat
import strutils
import tables

import ./types

proc broadcastEvent*(world: World, eventName: string)
proc loadWorld*(worldName: string): World
proc spawnPlayer*(world: World): Entity

import ./board
import ./entity
import ./script/compile
import ./script/exec
import ./script/exprs

proc getWorldController(share: ScriptSharedExecState): ScriptExecBase =
  if share.worldController == nil:
    share.loadWorldControllerFromFile()

  share.worldController

proc loadWorld(worldName: string): World =
  echo &"Loading world \"{worldName}\""

  var share = newScriptSharedExecState(
    rootDir = &"worlds/{worldName}/",
  )
  assert share != nil
  assert share.world == nil

  var execBase = share.getWorldController()
  assert execBase != nil
  var world = World(
    boards: Table[string, Board](),
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
    world.params[k0] = world.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.pairs():
    world.locals[k0] = world.resolveExpr(v0.varDefault)

  share.world = world

  # Now load boards
  for dirName in walkDirs((&"{share.rootDir}/boards/*/").replace("//", "/")):
    var componentList = dirName.split("/")
    var boardName = componentList[componentList.len-2]
    echo &"Loading board \"{boardName}\""
    discard world.loadBoardFromFile(boardName)

  # Return
  world

proc spawnPlayer(world: World): Entity =
  var board = world.getBoard("entry")
  var playerEntity = board.newEntity("player", board.grid.w div 2, board.grid.h div 2)
  playerEntity

proc broadcastEvent(world: World, eventName: string) =
  world.tickEvent(eventName)
  var boardsCopy: seq[Board] = @[]
  for board in world.boards.values():
    boardsCopy.add(board)
  for board in boardsCopy:
    board.broadcastEvent(eventName)
