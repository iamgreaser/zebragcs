import strformat
import strutils

import types
import unsorted


proc main() =
  var share = newScriptSharedExecState()

  share.loadEntityTypeFromFile("player", "scripts/player.script")
  share.loadEntityTypeFromFile("bullet", "scripts/bullet.script")

  var board = newBoard(share)
  var entity = board.newEntity(
    "player",
    30, 12,
  )
  echo &"board: {board}\n"
  echo &"entity: {entity}\n"
  var ticksLeft: int = 40
  var ticksDone: int = 0
  while entity.alive and ticksLeft > 0:
    case ticksDone
    of 14: entity.tickEvent("enemyshot")
    of 17: entity.tickEvent("pressshift")
    of 18: entity.tickEvent("typeup")
    of 20: entity.tickEvent("typeup")
    of 22: entity.tickEvent("typeup")
    of 24: entity.tickEvent("releaseshift")
    of 25: entity.tickEvent("typeleft")
    else: discard
    board.tick()
    ticksLeft -= 1
    ticksDone += 1
    #echo &"board: {board}"

    # TODO: Not hardcode the width and height --GM
    echo ">==========================================================="
    for y in 0..24:
      var lineSeq: seq[char] = @[]
      for x in 0..59:
        var gridseq = board.grid[y][x]
        lineSeq.add(if gridseq.len >= 1:
            '*'
          else:
            ' '
        )
      echo lineSeq.join("")
    echo "============================================================"
    for entity in board.entities:
      echo &"  - ({entity.x}, {entity.y})"
    echo ""
    #var health = entity.params.getOrDefault("health", ScriptVal(kind: svkInt, intVal: 0))
    #var ammo = entity.params.getOrDefault("ammo", ScriptVal(kind: svkInt, intVal: 0))
    #echo &"entity pos: {entity.x}, {entity.y} / health: {health} / ammo: {ammo} / alive: {entity.alive}"

main()
