import strformat

import gcs/board
import gcs/entity
import gcs/gfx
import gcs/scriptcompile
import gcs/types


proc main() =
  var share = newScriptSharedExecState()

  var board = newBoard(share)
  var entity = board.newEntity(
    "draftcontroller",
    0, 0,
  )
  echo &"board: {board}\n"
  echo &"entity: {entity}\n"
  withOpenGfx gfx:
    var ticksLeft: int = 20*15
    var ticksDone: int = 0
    while entity.alive and ticksLeft > 0:
      board.tick()
      ticksLeft -= 1
      ticksDone += 1

      #echo &"board: {board}"

      gfx.draw(board)
      #var health = entity.params.getOrDefault("health", ScriptVal(kind: svkInt, intVal: 0))
      #var ammo = entity.params.getOrDefault("ammo", ScriptVal(kind: svkInt, intVal: 0))
      #echo &"entity pos: {entity.x}, {entity.y} / health: {health} / ammo: {ammo} / alive: {entity.alive}"

main()
