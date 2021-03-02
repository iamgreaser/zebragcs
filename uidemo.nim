when defined(profiler):
  import nimprof

import os
import strformat

import sdl2
import ./zebra/gfx
import ./zebra/interntables
import ./zebra/types

import ./zebra/ui/bag
import ./zebra/ui/widget
import ./zebra/ui/window

type
  MainStateObj = object
    gfx: GfxState
    rootWidget: UiWidget
    alive: bool
  MainState = ref MainStateObj

proc run*(mainState: MainState)

proc main() =
  initInternTableBase(static(globalInternInitStrings))
  var args = commandLineParams()
  case args.len
  of 0: discard
  else:
    raise newException(Exception, &"{args} not valid for command-line arguments")

  withOpenGfx gfx:
    var
      rootWidget = UiBag(
        x: 0, y: 0, w: 80, h: 25,
        ch: uint16(' '), bg: 8, fg: 15,
        widgets: @[],
      )

    rootWidget.widgets.add(
      UiWindow(
        w: 38, h: 7,
        x: ((gfxWidth div 2) - 38) div 2,
        y: (gfxHeight - 7) div 2,
        bg: 1, fgText: 14, fgBorder: 7, fgPointer: 13,
        cursorY: 0,
        title: "Default window",
        textLines: @[
          "This window should not appear,",
          "but somehow it appeared anyway.",
        ],
        menuLines: @[
          "Oops! I'll send a bug report.",
          "Nah, get stuffed.",
        ],
      )
    )

    rootWidget.widgets.add(
      UiWindow(
        w: 38, h: 7,
        x: ((gfxWidth div 2) - 38) div 2 + (gfxWidth div 2),
        y: (gfxHeight - 7) div 2,
        bg: 1, fgText: 14, fgBorder: 7, fgPointer: 13,
        cursorY: 0,
        title: "Default window",
        textLines: @[
          "This window should not appear,",
          "but somehow it appeared anyway.",
        ],
        menuLines: @[
          "Oops! I'll send a bug report.",
          "Nah, get stuffed.",
        ],
      )
    )

    var mainState = MainState(
      gfx: gfx,
      rootWidget: rootWidget,
      alive: true,
    )

    try:
      mainState.run()
    except FullQuitException:
      echo "Full quit requested."
    finally:
      echo "Quitting!"

proc run(mainState: MainState) =
  try:
    while mainState.alive:
      mainState.gfx.drawWidget(mainState.rootWidget)
      mainState.gfx.blitToScreen()
      sdl2.delay(10)

      while true:
        var ev = mainState.gfx.getNextInput()
        if ev.kind == ievNone:
          break # End of list, stop here
        elif ev.kind == ievQuit:
          # Bail out once the event queue is drained
          mainState.alive = false

        if ev.kind == ievKeyRelease:
          case ev.keyType
          of ikEsc: # World select
            # Bail out once the event queue is drained
            mainState.alive = false
          else: discard

  finally:
    discard


main()
