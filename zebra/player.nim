import strformat
import tables
import types

proc getCamera*(player: Player): tuple[board: Board, x: int64, y: int64]
proc getEntity*(player: Player): Entity
proc newPlayer*(world: World): Player

import ./script/compile
import ./script/exec
import ./script/exprs

method tick*(player: Player) {.locks: "unknown".}

proc getCamera(player: Player): tuple[board: Board, x: int64, y: int64] =
  var share = player.share
  assert share != nil
  var world = share.world
  assert world != nil

  # Check entity first
  var entity = player.getEntity()
  if entity != nil:
    return (entity.board, entity.x, entity.y)
    
  # Now check camera pos
  var pos = player.params["camerapos"]
  assert pos != nil
  case pos.kind
  of svkPos:
    var boardName = pos.posBoardName
    var board = world.boards[boardName]
    (board, pos.posValX, pos.posValY)
  else:
    raise newException(ScriptExecError, &"@camerapos expected pos, got {pos} instead")

proc getEntity(player: Player): Entity =
  var val = player.params["playerent"]
  assert val != nil
  case val.kind
  of svkEntity:
    var entity = val.entityRef
    if entity != nil and not entity.alive:
      player.params["playerent"] = ScriptVal(kind: svkEntity, entityRef: nil)
      nil
    else:
      entity
  else:
    raise newException(ScriptExecError, &"@playerent expected entity, got {val} instead")


proc getPlayerController(share: ScriptSharedExecState): ScriptExecBase =
  if share.playerController == nil:
    share.loadPlayerControllerFromFile()

  share.playerController

proc newPlayer(world: World): Player =
  var share = world.share
  assert share != nil
  
  var execBase = share.getPlayerController()
  assert execBase != nil

  var player = Player(
    execBase: execBase,
    activeState: execBase.initState,
    params: Table[string, ScriptVal](),
    locals: Table[string, ScriptVal](),
    alive: true,
    share: share,
    sleepTicksLeft: 0,
  )

  world.players.add(player)

  # Initialise!
  for k0, v0 in execBase.params.pairs():
    player.params[k0] = player.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.pairs():
    player.locals[k0] = player.resolveExpr(v0.varDefault)

  player


method tick(player: Player) {.locks: "unknown".} =
  procCall tick(ScriptExecState(player))

  # Update camera pos
  var entity = player.getEntity()
  if entity != nil:
    var board = entity.board
    assert board != nil
    player.params["camerapos"] = ScriptVal(
      kind: svkPos,
      posBoardName: board.boardName,
      posValX: entity.x,
      posValY: entity.y,
    )
    