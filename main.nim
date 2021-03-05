when defined(profiler):
  import nimprof

import algorithm
import os
import strformat
import strutils

import ./zebra/game
import ./zebra/gfx
import ./zebra/interntables
import ./zebra/save
import ./zebra/types
import ./zebra/ui/bag
import ./zebra/ui/boardview
import ./zebra/ui/statusbar
import ./zebra/ui/themes/classic as classicTheme
import ./zebra/ui/types as uiTypes
import ./zebra/ui/window
import ./zebra/vfs/disk
#import ./zebra/vfs/types as vfsTypes

type
  MainStateObj = object
    gfx: GfxState
    gameType: GameType
    game: GameState
    rootWidget: UiWidget
    boardViewWidget: UiBoardView
    statusBarWidget: UiStatusBar
    textWindowWidget: UiWindow

    worldName: string
    worldMenuOpen: bool
    worldMenuIndex: int64
    worldList: seq[string]
  MainState = ref MainStateObj

proc openWorldMenu(mainState: MainState)
proc runGame(mainState: MainState, game: var GameState): GameType
proc updateTextWindow(mainState: MainState, textWindowWidget: UiWindow)

proc main() =
  initInternTableBase(static(globalInternInitStrings))
  var args = commandLineParams()
  var worldName = ""
  case args.len
  of 0: discard
  of 1: worldName = args[0]
  else:
    raise newException(Exception, &"{args} not valid for command-line arguments")

  withOpenGfx gfx:
    # FIXME: Needs a "waiting to load the thing" screen --GM
    var
      rootWidget = UiBag(
        innerRect: UiRect(
          x: 0, y: 0, w: 80, h: 25,
        ),
        outerRect: UiRect(
          x: 0, y: 0, w: 80, h: 25,
        ),
        themeRectType: themeRectRootBackground,
        borderType: themeBorderNone,
        widgets: @[],
        #theme: UiTheme(),
        theme: UiClassicTheme(),
      )

      boardViewWidget = UiBoardView(
        innerRect: UiRect(
          #x: 0, y: 0, w: 60, h: 25,
          x: 0, y: 0, w: 0, h: 0,
        ),
        themeRectType: themeRectBoardViewBackground,
        board: nil,
      )
      statusBarWidget = UiStatusBar(
        innerRect: UiRect(
          x: 60, y: 0, w: 20, h: 25,
        ),
        borderType: themeBorderNone,
      )

      textWindowWidget = UiWindow(
        innerRect: UiRect(
          w: 44, h: 6,
          x: (boardVisWidth - 44) div 2,
          y: (boardVisHeight - 6) div 2,
        ),
        bg: 1, fgText: 14, fgBorder: 7, fgPointer: 13,
        cursorY: 0,
        title: "Default window",
        textLines: @[
          "This window should not appear as-is,",
          "but somehow it appeared anyway.",
        ],
        menuLines: @[
          "Oops! I'll send a bug report.",
        ],
      )

    rootWidget.widgets.add(boardViewWidget)
    rootWidget.widgets.add(statusBarWidget)
    rootWidget.widgets.add(textWindowWidget)

    var mainState = MainState(
      gfx: gfx,
      worldName: worldName,
      rootWidget: rootWidget,
      boardViewWidget: boardViewWidget,
      statusBarWidget: statusBarWidget,
      textWindowWidget: textWindowWidget,
      gameType: if worldName != "":
          gtDemo
        else:
          gtInitialWorldSelect,
    )

    try:
      while mainState.gameType != gtBed:
        var game = case mainState.gameType
          of gtBed: return # Shouldn't reach here, but just in case...
          of gtInitialWorldSelect:
            mainState.openWorldMenu()
            nil
          of gtDemo: newDemoGame(mainState.worldName)
          of gtEditorSingle: newEditorSinglePlayerGame(mainState.worldName)
          of gtMultiClient: newMultiClientGame("localhost")
          of gtMultiServer: newMultiServerGame(mainState.worldName)
          of gtSingle: newSinglePlayerGame(mainState.worldName)
        mainState.gameType = mainState.runGame(
          game = game,
        )
    except FullQuitException:
      echo "Full quit requested."
    finally:
      echo "Quitting!"

proc runGame(mainState: MainState, game: var GameState): GameType =
  mainState.game = game
  try:
    while mainState.worldMenuOpen or (game != nil and game.alive):
      if game != nil:
        game.tick()
        game.updatePlayerBoardView(mainState.boardViewWidget)
        game.updatePlayerStatusBar(mainState.statusBarWidget)

      mainState.updateTextWindow(mainState.textWindowWidget)

      mainState.rootWidget.refreshLayout()
      mainState.gfx.drawWidget(mainState.rootWidget)
      mainState.gfx.blitToScreen()

      if game != nil:
        game.endTick()

      while true:
        var ev = mainState.gfx.getNextInput()
        if ev.kind == ievNone:
          break # End of list, stop here
        elif ev.kind == ievQuit:
          # Bail out once the event queue is drained
          game.alive = false

        if mainState.worldMenuOpen:
          if ev.kind == ievKeyPress:
            case ev.keyType
            of ikUp: mainState.worldMenuIndex = ((mainState.worldMenuIndex + mainState.worldList.len - 1) mod mainState.worldList.len)
            of ikDown: mainState.worldMenuIndex = ((mainState.worldMenuIndex + 1) mod mainState.worldList.len)
            else: discard
          elif ev.kind == ievKeyRelease:
            case ev.keyType
            of ikEsc: # Close menu
              mainState.worldMenuOpen = false
            of ikEnter: # Select in menu and load it
              if mainState.worldMenuIndex == mainState.worldList.len-1:
                # Enter the editor - TODO!
                if not mainState.worldList[^1].contains("TODO"):
                  mainState.worldList[^1] = mainState.worldList[^1] & " - TODO!"
                discard
              else:
                mainState.worldName = mainState.worldList[mainState.worldMenuIndex]
                mainState.worldMenuOpen = false
                return gtDemo
            else: discard

        elif game != nil:
          game.applyInput(ev)

          if game.world == nil:
            if game.gameType == gtMultiServer:
              case ev.keyType
              of ikEnter:
                # Start game!
                game.startMultiServerGame()
                assert game.world != nil
              else: discard

          else:
            if game.gameType == gtDemo:
              if ev.kind == ievKeyRelease:
                case ev.keyType
                of ikC: # Net client
                  return gtMultiClient
                of ikE: # Edit world
                  return gtEditorSingle
                of ikN: # Net server
                  return gtMultiServer
                of ikP: # Play game
                  return gtSingle
                of ikW: # World select
                  mainState.openWorldMenu()
                else: discard

            elif game.gameType == gtSingle:
              if ev.kind == ievKeyRelease:
                case ev.keyType
                of ikF3: # Save
                  game.save("game.zebrasave")
                of ikF4: # Load
                  game.load("game.zebrasave")
                else: discard

  finally:
    if mainState.game != nil:
      mainState.game.close()
    mainState.game = nil

  # Where to from here?
  case mainState.gameType
  of gtDemo: gtBed
  of gtInitialWorldSelect:
    echo "No world selected, cannot continue."
    gtBed
  else: gtDemo

proc openWorldMenu(mainState: MainState) =
  mainState.worldList = @[]
  var vfs = newDiskFs(
    rootDir = "worlds/",
  )

  for worldName in vfs.vfsDirList(@[]):
    mainState.worldList.add(worldName)

  mainState.worldList.sort()

  mainState.worldList.add("<< Create New World >>")

  if mainState.worldList.len >= 1:
    mainState.worldMenuOpen = true
    mainState.worldMenuIndex = min(mainState.worldMenuIndex, mainState.worldList.len-1)

proc updateTextWindow(mainState: MainState, textWindowWidget: UiWindow) =
  # TODO: Something useful --GM
  textWindowWidget.title = ""
  textWindowWidget.textLines = @[]
  textWindowWidget.menuLines = @[]
  textWindowWidget.cursorY = 0

  if mainState.worldMenuOpen:
    textWindowWidget.title = "World select"
    textWindowWidget.textLines.setLen(0)
    textWindowWidget.menuLines = mainState.worldList
    textWindowWidget.cursorY = mainState.worldMenuIndex

  else:
    var game = mainState.game
    if game != nil:
      var player = game.player
      if player != nil:
        textWindowWidget.title = player.windowTitle
        textWindowWidget.textLines = player.windowTextLines
        textWindowWidget.menuLines.setLen(0)
        textWindowWidget.cursorY = player.windowCursorY
        for item in player.windowMenuItems:
          textWindowWidget.menuLines.add(item.text)

      elif game.gameType == gtMultiClient:
        textWindowWidget.title = "Net client"
        textWindowWidget.textLines = @[
          #----------------------------------------
          "Connecting... (not really, it's a TODO)",
          "",
          "Press ESC to abort",
        ]
        textWindowWidget.menuLines.setLen(0)
        textWindowWidget.cursorY = 0

      elif game.gameType == gtMultiServer and game.world == nil:
        textWindowWidget.title = "Net Server"
        textWindowWidget.textLines = @[
          #----------------------------------------
          &"World: \"{mainState.worldName}\"",
          &"Other players present: {0}",
        ]
        textWindowWidget.menuLines = @[
          #--------------------------------------
          "Start Game",
        ]
        textWindowWidget.cursorY = 0


  textWindowWidget.innerRect.h = 0
  if textWindowWidget.textLines.len >= 1:
    textWindowWidget.innerRect.h += textWindowWidget.textLines.len
  if textWindowWidget.menuLines.len >= 1:
    if textWindowWidget.innerRect.h != 0:
      textWindowWidget.innerRect.h += 1
    textWindowWidget.innerRect.h += textWindowWidget.menuLines.len
  if textWindowWidget.innerRect.h != 0:
    textWindowWidget.innerRect.h += 2

  textWindowWidget.innerRect.w = (2 + 40 + 2)
  textWindowWidget.innerRect.x = (boardVisWidth - textWindowWidget.innerRect.w) div 2
  textWindowWidget.innerRect.y = (boardVisHeight - textWindowWidget.innerRect.h) div 2

main()
