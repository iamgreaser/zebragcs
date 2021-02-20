when defined(profiler):
  import nimprof

import os
import strformat

import ./zebra/game
import ./zebra/gfx
import ./zebra/types
import ./zebra/ui


proc main() =
  var args = commandLineParams()
  var worldName = "prototype"
  case args.len
  of 0: discard
  of 1: worldName = args[0]
  else:
    raise newException(Exception, &"{args} not valid for command-line arguments")

  var game = newSinglePlayerGame(worldName)

  withOpenGfx gfx:
    # FIXME: Needs a "waiting to load the thing" screen --GM
    var player = game.player
    assert player != nil

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

    while game.alive and game.player != nil and game.player.alive:
      var player = game.player
      assert player != nil
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
          return # Bail out immediately

        game.applyInput(ev)

main()
