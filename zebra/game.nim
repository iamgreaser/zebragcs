import strformat

import ./interntables
import ./types
import ./ui

type
  GameStateObj = object
    gameType*: GameType
    world*: World
    player*: Player
    board*: Board
    cursorX*: int64
    cursorY*: int64
    alive*: bool
    editing*: bool
  GameState* = ref GameStateObj

proc applyInput*(game: GameState, ev: InputEvent)
proc newDemoGame*(worldName: string): GameState
proc newEditorSinglePlayerGame*(worldName: string): GameState
proc newSinglePlayerGame*(worldName: string): GameState
proc tick*(game: GameState)
proc updatePlayerBoardView*(game: GameState, boardWidget: UiBoardView)
proc updatePlayerStatusBar*(game: GameState, statusWidget: UiStatusBar)

proc `$`*(x: GameState): string =
  &"GameState(world={x.world}, player={x.player})"

import ./script/exec
import ./player
import ./world

proc newDemoGame(worldName: string): GameState =
  echo &"Starting new demo of world \"{worldName}\""
  var world = loadWorld(worldName)
  world.tickTitle = true
  world.broadcastEvent(internKeyCT("initworld"))

  var game = GameState(
    gameType: gtDemo,
    world: world,
    player: nil,
    alive: true,
  )

  game

proc newEditorSinglePlayerGame(worldName: string): GameState =
  echo &"Starting new single-player game of world \"{worldName}\""
  var world = loadWorld(worldName)

  var board = world.boards["entry"]
  assert board != nil

  var game = GameState(
    gameType: gtEditorSingle,
    world: world,
    player: nil,
    board: board,
    cursorX: board.grid.w div 2,
    cursorY: board.grid.h div 2,
    alive: true,
    editing: true,
  )

  game

proc newSinglePlayerGame(worldName: string): GameState =
  echo &"Starting new single-player game of world \"{worldName}\""
  var world = loadWorld(worldName)
  world.broadcastEvent(internKeyCT("initworld"))

  echo "Spawning new player"
  var player = world.newPlayer()
  player.tickEvent(internKeyCT("initplayer"))

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
      var board = game.board
      if board == nil:
        board = world.boards["title"]
      assert board != nil
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

      if game.editing:
        boardWidget.cursorVisible = true
        boardWidget.cursorX = game.cursorX
        boardWidget.cursorY = game.cursorY
      else:
        boardWidget.cursorVisible = false

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
  case game.gameType
  of gtDemo:
    statusWidget.keyLabels = @[
      ("W", "World select"),
      ("P", "Play world"),
      ("E", "Edit world"),
      #("L", "Load game"),
      ("ESC", "Exit to BSD"),
    ]

  of gtInitialWorldSelect:
    statusWidget.keyLabels = @[
      ("ESC", "Exit to BSD"),
    ]

  of gtSingle:
    statusWidget.keyLabels = @[
      ("ESC", "Quit game"),
    ]

  of gtEditorSingle:
    statusWidget.keyLabels = @[
      ("ESC", "Quit editor"),
    ]

  of gtBed:
    discard # Don't bother

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

    elif game.editing:
      case ev.keyType
      of ikLeft:
        game.cursorX = max(game.cursorX-1, 0)
      of ikRight:
        game.cursorX = min(game.cursorX+1, game.board.grid.w-1)
      of ikUp:
        game.cursorY = max(game.cursorY-1, 0)
      of ikDown:
        game.cursorY = min(game.cursorY+1, game.board.grid.h-1)
      else:
        discard

    else:
      # TODO: Handle key repeat properly --GM
      var player = game.player
      if player != nil:
        # TODO: Intern these at compiletime --GM
        player.tickEvent(internKey(&"press{ev.keyType}"))
        player.tickEvent(internKey(&"type{ev.keyType}"))

  of ievKeyRelease:
    if ev.keyType == ikEsc:
      # Quit to menu or exit game
      game.alive = false

    elif game.editing:
      discard

    else:
      var player = game.player
      if player != nil:
        # TODO: Intern this at compiletime --GM
        player.tickEvent(internKey(&"release{ev.keyType}"))

  #else: discard
