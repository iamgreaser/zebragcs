import strformat

import zebra/board
import zebra/entity
import zebra/gfx
import zebra/scriptcompile
import zebra/types


proc main() =
  var share = newScriptSharedExecState(
    rootDir="worlds/prototype/",
  )

  var gameRunning: bool = true

  var board = newBoard(share)
  var entity = board.newEntity(
    "draftcontroller",
    0, 0,
  )
  echo &"board: {board}\n"
  echo &"entity: {entity}\n"
  withOpenGfx gfx:
    while gameRunning and entity.alive:
      board.tick()

      #echo &"board: {board}"

      gfx.draw(board)
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
