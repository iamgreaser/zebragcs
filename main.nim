when defined(profiler):
  import nimprof

import strformat
import tables

import ./zebra/world
import ./zebra/board
import ./zebra/entity
import ./zebra/gfx
import ./zebra/script/compile
import ./zebra/script/exec
import ./zebra/types
import ./zebra/ui


proc main() =
  var share = newScriptSharedExecState(
    rootDir="worlds/prototype/",
  )

  var gameRunning: bool = true

  var world = share.newWorld()

  withOpenGfx gfx:
    # TEST: Create 2 boards
    discard world.newBoard("entry", "draftcontroller")
    discard world.newBoard("second", "second")

    world.broadcastEvent("initworld")

    var playerEntity = world.boards["entry"].newEntity("player", 30, 12)
    echo &"player entity: {playerEntity}\n"

    var
      boardViewWidget = UiBoardView(
        x: 0, y: 0, w: 60, h: 25,
        board: playerEntity.board,
      )
      statusBarWidget = UiStatusBar(
        x: 60, y: 0, w: 20, h: 25,
      )

    while gameRunning and playerEntity.alive:
      world.tick()
      playerEntity.board.tick()
      assert playerEntity.board.entities.contains(playerEntity)

      boardViewWidget.board = playerEntity.board
      gfx.drawWidget(boardViewWidget)
      gfx.drawWidget(statusBarWidget)
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
