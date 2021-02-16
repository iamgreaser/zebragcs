import strformat

import ./zebra/board
#import ./zebra/entity
import ./zebra/gfx
import ./zebra/script/compile
import ./zebra/types
import ./zebra/ui


proc main() =
  var share = newScriptSharedExecState(
    rootDir="worlds/prototype/",
  )

  var gameRunning: bool = true

  # TODO: Add spawn points and reinstate the player entity --GM
  var board = share.newBoard("draftcontroller")
  #var entity = board.newEntity("player", 0, 0)
  echo &"board: {board}\n"
  #echo &"entity: {entity}\n"
  withOpenGfx gfx:
    var
      boardViewWidget = UiBoardView(
        x: 0, y: 0, w: 60, h: 25,
        board: board,
      )
      statusBarWidget = UiStatusBar(
        x: 60, y: 0, w: 20, h: 25,
      )

    #while gameRunning and board.alive and entity.alive:
    while gameRunning and board.alive:
      board.tick()

      #echo &"board: {board}"

      #gfx.draw(board)
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
            board.broadcastEvent(&"press{ev.keyType}")
            board.broadcastEvent(&"type{ev.keyType}")

        of ievKeyRelease:
          if ev.keyType == ikEsc:
            # Quit
            gameRunning = false
            break
          else:
            board.broadcastEvent(&"release{ev.keyType}")

        #else: discard

main()
