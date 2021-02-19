when defined(profiler):
  import nimprof

import os
import strformat

import ./zebra/gfx
import ./zebra/player
import ./zebra/types
import ./zebra/ui
import ./zebra/world
import ./zebra/script/exec


const boardVisWidth = 60
const boardVisHeight = 25

proc main() =
  var args = commandLineParams()
  var worldName = "prototype"
  case args.len
  of 0: discard
  of 1: worldName = args[0]
  else:
    raise newException(Exception, &"{args} not valid for command-line arguments")
  var gameRunning: bool = true

  var world = loadWorld(worldName)

  withOpenGfx gfx:
    world.broadcastEvent("initworld")

    var player = world.newPlayer()
    player.tickEvent("initplayer")
    echo &"player: {player}\n"
    # FIXME: Needs a "waiting to load the thing" screen --GM
    var playerEntity = player.getEntity()
    assert playerEntity != nil
    assert playerEntity.board != nil

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

    while gameRunning and player.alive:
      world.tick()
      var (playerBoard, playerBoardX, playerBoardY) = player.getCamera()

      # Sanity checks
      var playerEntity = player.getEntity()
      if playerEntity != nil:
        assert playerEntity.board != nil
        assert playerEntity.board.entities.contains(playerEntity)

      if playerBoard != nil:
        block:
          boardViewWidget.board = playerBoard
          boardViewWidget.w = min(boardVisWidth, playerBoard.grid.w)
          boardViewWidget.h = min(boardVisHeight, playerBoard.grid.h)
          boardViewWidget.x = max(0, (boardVisWidth - playerBoard.grid.w) div 2)
          boardViewWidget.y = max(0, (boardVisHeight - playerBoard.grid.h) div 2)
          boardViewWidget.scrollX = max(0,
            min(playerBoard.grid.w - boardViewWidget.w,
              playerBoardX - (boardViewWidget.w div 2)))
          boardViewWidget.scrollY = max(0,
            min(playerBoard.grid.h - boardViewWidget.h,
              playerBoardY - (boardViewWidget.h div 2)))

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
            player.tickEvent(&"press{ev.keyType}")
            player.tickEvent(&"type{ev.keyType}")

        of ievKeyRelease:
          if ev.keyType == ikEsc:
            # Quit
            gameRunning = false
            break
          else:
            player.tickEvent(&"release{ev.keyType}")

        #else: discard

main()
