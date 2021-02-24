import os
import strformat
import std/monotimes
import times

import ./interntables
import ./network
import ./types
import ./ui

var lastSleepTime: MonoTime
var didLastSleep: bool = false
var cpuUsage: float64 = 0.0
const cpuUsageReportPeriod: int = 20
var cpuUsageTicksUntilNextReport: int = cpuUsageReportPeriod

type
  GameStateObj = object
    gameType*: GameType
    worldName*: string
    world*: World
    player*: Player
    board*: Board
    cursorX*: int64
    cursorY*: int64
    frameIdx*: uint16
    alive*: bool
    editing*: bool
  GameState* = ref GameStateObj

proc addGameInput*(game: GameState, player: Player, ev: NetEvent)
proc applyInput*(game: GameState, ev: InputEvent)
proc applyGameInput*(game: GameState, player: Player, ev: NetEvent)
proc close*(game: GameState)
proc endTick*(game: GameState)
proc newDemoGame*(worldName: string): GameState
proc newEditorSinglePlayerGame*(worldName: string): GameState
proc newMultiClientGame*(ipAddr: string, udpPort: uint16 = 22700): GameState
proc newMultiServerGame*(worldName: string, udpPort: uint16 = 22700): GameState
proc newSinglePlayerGame*(worldName: string): GameState
proc startMultiServerGame*(game: GameState)
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
    worldName: worldName,
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
    worldName: worldName,
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
    worldName: worldName,
    world: world,
    player: player,
    alive: true,
  )

  game

proc newMultiClientGame(ipAddr: string, udpPort: uint16 = 22700): GameState =
  echo &"Connecting to multi-player game at zebragcs://{ipAddr}:{udpPort}"
  var game = GameState(
    gameType: gtMultiClient,
    worldName: "",
    world: nil,
    player: nil,
    frameIdx: 0,
    alive: true,
  )

  game

proc newMultiServerGame(worldName: string, udpPort: uint16 = 22700): GameState =
  echo &"Creating lobby for new multi-player game on port {udpPort} of world \"{worldName}\""

  var game = GameState(
    gameType: gtMultiServer,
    worldName: worldName,
    world: nil,
    player: nil,
    frameIdx: 0,
    alive: true,
  )

  game

proc startMultiServerGame(game: GameState) =
  assert game.world == nil
  echo &"Starting multi-player server game of world \"{game.worldName}\""
  var world = loadWorld(game.worldName)
  world.broadcastEvent(internKeyCT("initworld"))
  game.world = world

  echo "Spawning new player"
  var player = world.newPlayer()
  player.tickEvent(internKeyCT("initplayer"))
  game.player = player


proc updatePlayerBoardView(game: GameState, boardWidget: UiBoardView) =
  if game.world == nil:
    return

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
  statusWidget.textLabels.setLen(0)

  case game.gameType
  of gtDemo:
    statusWidget.keyLabels = @[
      ("W", "World select"),
      ("P", "Play world"),
      ("E", "Edit world"),
      ("N", "Net server"),
      ("C", "Net client"),
      #("L", "Load game"),
      ("ESC", "Exit to BSD"),
    ]

  of gtInitialWorldSelect:
    statusWidget.keyLabels = @[
      ("ESC", "Exit to BSD"),
    ]

  of gtMultiClient:
    statusWidget.keyLabels = @[
      ("ESC", "Disconnect"),
    ]

  of gtMultiServer:
    statusWidget.textLabels = @[
      &"Frame: {game.frameIdx:04X}",
    ]
    statusWidget.keyLabels = @[
      ("ESC", "Stop server"),
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
  if world != nil:
    world.tick()


proc applyGameInput(game: GameState, player: Player, ev: NetEvent) =
  # TODO: Handle key repeat properly --GM
  # TODO: Intern these names at compiletime --GM
  case ev.kind
  of nevInputPress:
    player.tickEvent(internKey(&"press{ev.inputKey}"))

  of nevInputRelease:
    player.tickEvent(internKey(&"release{ev.inputKey}"))

  of nevInputType:
    player.tickEvent(internKey(&"type{ev.inputKey}"))

proc addGameInput(game: GameState, player: Player, ev: NetEvent) =
  game.applyGameInput(player, ev)

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
      var player = game.player
      if player != nil:
        game.applyGameInput(player,
          NetEvent(kind: nevInputPress, inputKey: ev.keyType))
        game.applyGameInput(player,
          NetEvent(kind: nevInputType, inputKey: ev.keyType))

  of ievKeyRelease:
    if ev.keyType == ikEsc:
      # Quit to menu or exit game
      game.alive = false

    elif game.editing:
      discard

    else:
      var player = game.player
      if player != nil:
        game.applyGameInput(player,
          NetEvent(kind: nevInputRelease, inputKey: ev.keyType))

  #else: discard

proc close(game: GameState) =
  game.alive = false
  # TODO: Close any network sockets we may have --GM

proc endTick(game: GameState) =
  if game.world != nil:
    game.frameIdx += 1'u16

  if didLastSleep:
    lastSleepTime = lastSleepTime + initDuration(milliseconds = 50)
    var now = getMonoTime()
    if now < lastSleepTime:
      var sleepBeg = now.ticks div 1_000_000
      var sleepEnd = lastSleepTime.ticks div 1_000_000
      var sleepDiff = sleepEnd - sleepBeg
      var sleepDiffNanos = lastSleepTime.ticks - now.ticks
      var cpuUsedThisTick = float64(50*1_000_000 - sleepDiffNanos) / float64(50*1_000_000)
      cpuUsage += cpuUsedThisTick
      cpuUsageTicksUntilNextReport -= 1
      assert sleepDiff >= 0
      sleep(int(sleepDiff))
    else:
      # Slipped!
      var cpuUsedThisTick = 1.0
      cpuUsage += cpuUsedThisTick
      cpuUsageTicksUntilNextReport -= 1
      lastSleepTime = now
  else:
    sleep(50)
    lastSleepTime = getMonoTime()
    didLastSleep = true;

  if cpuUsageTicksUntilNextReport <= 0:
    cpuUsageTicksUntilNextReport = cpuUsageReportPeriod
    cpuUsage /= float64(cpuUsageReportPeriod)
    echo &"cpu: {cpuUsage:9.6f}"
    cpuUsage = 0.0
