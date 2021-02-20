import strformat

import ./types
import ./ui

proc applyInput*(game: GameState, ev: InputEvent)
proc newSinglePlayerGame*(worldName: string): GameState
proc tick*(game: GameState)
proc updatePlayerBoardView*(game: GameState, boardWidget: UiBoardView)
proc updatePlayerStatusBar*(game: GameState, statusWidget: UiStatusBar)

import ./script/exec
import ./player
import ./world

proc newSinglePlayerGame(worldName: string): GameState =
  var world = loadWorld(worldName)
  world.broadcastEvent("initworld")

  echo "Spawning new player"
  var player = world.newPlayer()
  player.tickEvent("initplayer")

  var game = GameState(
    world: world,
    player: player,
    alive: true,
  )

  game

proc updatePlayerBoardView(game: GameState, boardWidget: UiBoardView) =
  var player = game.player
  assert player != nil

  var (playerBoard, playerBoardX, playerBoardY) = player.getCamera()

  # Sanity checks
  var playerEntity = player.getEntity()
  if playerEntity != nil:
    assert playerEntity.board != nil
    assert playerEntity.board.entities.contains(playerEntity)

  if playerBoard != nil:
    block:
      boardWidget.board = playerBoard
      boardWidget.w = min(boardVisWidth, playerBoard.grid.w)
      boardWidget.h = min(boardVisHeight, playerBoard.grid.h)
      boardWidget.x = max(0, (boardVisWidth - playerBoard.grid.w) div 2)
      boardWidget.y = max(0, (boardVisHeight - playerBoard.grid.h) div 2)
      boardWidget.scrollX = max(0,
        min(playerBoard.grid.w - boardWidget.w,
          playerBoardX - (boardWidget.w div 2)))
      boardWidget.scrollY = max(0,
        min(playerBoard.grid.h - boardWidget.h,
          playerBoardY - (boardWidget.h div 2)))

proc updatePlayerStatusBar(game: GameState, statusWidget: UiStatusBar) =
  discard # TODO!

proc tick(game: GameState) =
  var world = game.world
  assert world != nil
  world.tick()

proc applyInput(game: GameState, ev: InputEvent) =
  var player = game.player
  assert player != nil

  case ev.kind
  of ievNone:
    discard

  of ievQuit:
    game.alive = false
    discard

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
      # Quit to menu
      game.alive = false
    else:
      player.tickEvent(&"release{ev.keyType}")

  #else: discard
