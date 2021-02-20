import strformat
import tables

import ./types
import ./ui

proc applyInput*(game: GameState, ev: InputEvent)
proc newDemoGame*(worldName: string): GameState
proc newSinglePlayerGame*(worldName: string): GameState
proc tick*(game: GameState)
proc updatePlayerBoardView*(game: GameState, boardWidget: UiBoardView)
proc updatePlayerStatusBar*(game: GameState, statusWidget: UiStatusBar)

import ./script/exec
import ./player
import ./world

proc newDemoGame(worldName: string): GameState =
  var world = loadWorld(worldName)
  world.tickTitle = true
  world.broadcastEvent("initworld")

  var game = GameState(
    gameType: gtDemo,
    world: world,
    player: nil,
    alive: true,
  )

  game

proc newSinglePlayerGame(worldName: string): GameState =
  var world = loadWorld(worldName)
  world.broadcastEvent("initworld")

  echo "Spawning new player"
  var player = world.newPlayer()
  player.tickEvent("initplayer")

  var game = GameState(
    gameType: gtSingle,
    world: world,
    player: player,
    alive: true,
  )

  game

proc updatePlayerBoardView(game: GameState, boardWidget: UiBoardView) =
  var player = game.player

  var (playerBoard, playerBoardX, playerBoardY) = if player != nil:
      player.getCamera()
    else:
      var world = game.world
      assert world != nil
      var board = world.boards["title"]
      var w = min(board.grid.w-1, boardVisWidth div 2)
      var h = min(board.grid.h-1, boardVisHeight div 2)
      (board, w, h)

  if player != nil:
    # Kill the game if our player controller is dead
    if not player.alive:
      game.alive = false

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

  case ev.kind
  of ievNone:
    discard

  of ievQuit:
    game.alive = false
    raise newException(FullQuitException, "Quit event received")

  of ievKeyPress:
    if ev.keyType == ikEsc:
      # Wait for release
      discard
    else:
      # TODO: Handle key repeat properly --GM
      var player = game.player
      if player != nil:
        player.tickEvent(&"press{ev.keyType}")
        player.tickEvent(&"type{ev.keyType}")

  of ievKeyRelease:
    if ev.keyType == ikEsc:
      # Quit to menu or exit game
      game.alive = false
    else:
      var player = game.player
      if player != nil:
        player.tickEvent(&"release{ev.keyType}")

  #else: discard
