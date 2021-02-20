when defined(profiler):
  import nimprof

import os
import strformat

import ./zebra/game
import ./zebra/gfx
import ./zebra/types
import ./zebra/ui

proc runGame(game: GameState, gfx: GfxState, rootWidget: UiWidget, boardViewWidget: UiBoardView, statusBarWidget: UiStatusBar): GameType


proc main() =
  var args = commandLineParams()
  var worldName = "prototype"
  case args.len
  of 0: discard
  of 1: worldName = args[0]
  else:
    raise newException(Exception, &"{args} not valid for command-line arguments")

  withOpenGfx gfx:
    # FIXME: Needs a "waiting to load the thing" screen --GM
    var
      boardViewWidget = UiBoardView(
        x: 0, y: 0, w: 60, h: 25,
        board: nil,
      )
      statusBarWidget = UiStatusBar(
        x: 60, y: 0, w: 20, h: 25,
      )

      rootWidget = UiBag(
        x: 0, y: 0, w: 80, h: 25,
        ch: uint16(' '), bg: 8, fg: 15,
        widgets: @[],
      )

    rootWidget.widgets.add(statusBarWidget)
    rootWidget.widgets.add(boardViewWidget)


    var gameType = gtDemo
    try:
      while gameType != gtBed:
        var game = case gameType
          of gtBed: return # Shouldn't reach here, but just in case...
          of gtDemo: newDemoGame(worldName)
          of gtSingle: newSinglePlayerGame(worldName)
        gameType = runGame(
          game = game,
          gfx = gfx,
          rootWidget = rootWidget,
          boardViewWidget = boardViewWidget,
          statusBarWidget = statusBarWidget,
        )
    except FullQuitException:
      echo "Full quit requested."
    finally:
      echo "Quitting!"

proc runGame(game: GameState, gfx: GfxState, rootWidget: UiWidget, boardViewWidget: UiBoardView, statusBarWidget: UiStatusBar): GameType =
  while game.alive:
    game.tick()
    game.updatePlayerBoardView(boardViewWidget)
    game.updatePlayerStatusBar(statusBarWidget)

    gfx.drawWidget(rootWidget)
    gfx.blitToScreen()

    while true:
      var ev = gfx.getNextInput()
      if ev.kind == ievNone:
        break # End of list, stop here
      elif ev.kind == ievQuit:
        # Bail out once the event queue is drained
        game.alive = false

      game.applyInput(ev)

      if game.gameType == gtDemo and ev.kind == ievKeyRelease:
        case ev.keyType
        of ikP: # Play game
          return gtSingle
        else: discard

  # Where to from here?
  case game.gameType
  of gtDemo: gtBed
  else: gtDemo

main()
