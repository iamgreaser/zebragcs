when defined(profiler):
  import nimprof

import os
import strformat
import strutils

import ./zebra/world
import ./zebra/board
import ./zebra/entity
import ./zebra/gfx
import ./zebra/script/compile
import ./zebra/script/exec
import ./zebra/types
import ./zebra/ui


const boardVisWidth = 60
const boardVisHeight = 25

proc main() =
  var worldName = "prototype"
  var gameRunning: bool = true

  var share = newScriptSharedExecState(
    rootDir = &"worlds/{worldName}/",
  )
  var world = share.loadWorld()
  for dirName in walkDirs((&"{share.rootDir}/boards/*/").replace("//", "/")):
    var componentList = dirName.split("/")
    var boardName = componentList[componentList.len-2]
    echo &"Loading board \"{boardName}\""
    discard world.loadBoardFromFile(boardName)


  withOpenGfx gfx:
    world.broadcastEvent("initworld")

    var playerEntity = block:
      var board = world.getBoard("entry")
      board.newEntity("player", board.grid.w div 2, board.grid.h div 2)
    echo &"player entity: {playerEntity}\n"

    var
      boardViewWidget = UiBoardView(
        x: 0, y: 0, w: 60, h: 25,
        board: playerEntity.board,
      )
      statusBarWidget = UiStatusBar(
        x: 60, y: 0, w: 20, h: 25,
      )

      rootWidget = UiBag(
        x: 0, y: 0, w: 80, h: 25,
        ch: uint16(' '), bg: 8, fg: 15,
        widgets: @[],
      )

    rootWidget.widgets.add(statusBarWidget)
    rootWidget.widgets.add(boardViewWidget)

    while gameRunning and playerEntity.alive:
      world.tick()
      playerEntity.board.tick()
      assert playerEntity.board.entities.contains(playerEntity)

      block:
        var board = playerEntity.board
        boardViewWidget.board = board
        boardViewWidget.x = max(0, (boardVisWidth - board.grid.w) div 2)
        boardViewWidget.y = max(0, (boardVisHeight - board.grid.h) div 2)
        boardViewWidget.w = min(boardVisWidth, board.grid.w)
        boardViewWidget.h = min(boardVisHeight, board.grid.h)

      gfx.drawWidget(rootWidget)
      gfx.blitToScreen()
      #var health = entity.params.getOrDefault("health", ScriptVal(kind: svkInt, intVal: 0))
      #var ammo = entity.params.getOrDefault("ammo", ScriptVal(kind: svkInt, intVal: 0))
      #echo &"entity pos: {entity.x}, {entity.y} / health: {health} / ammo: {ammo} / alive: {entity.alive}"

      while true:
        var ev = gfx.getNextInput()
        case ev.kind
        of ievNone: break

        of ievQuit:
          gameRunning = false
          break

        of ievKeyPress:
          if ev.keyType == ikEsc:
            # Wait for release
            discard
          else:
            # TODO: Handle key repeat properly --GM
            playerEntity.board.broadcastEvent(&"press{ev.keyType}")
            playerEntity.board.broadcastEvent(&"type{ev.keyType}")

        of ievKeyRelease:
          if ev.keyType == ikEsc:
            # Quit
            gameRunning = false
            break
          else:
            playerEntity.board.broadcastEvent(&"release{ev.keyType}")

        #else: discard

main()
