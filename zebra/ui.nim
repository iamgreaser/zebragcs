import tables

import ./types
import ./gfx

type
  UiWidgetObj = object of RootObj
    x*, y*: int64
    w*, h*: int64
  UiWidget* = ref UiWidgetObj

  UiBagObj = object of UiWidgetObj
    widgets*: seq[UiWidget]
    ch*: uint16
    bg*, fg*: uint8
  UiBag* = ref UiBagObj

  UiBoardViewObj = object of UiWidgetObj
    board*: Board
  UiBoardView* = ref UiBoardViewObj
  UiStatusBarObj = object of UiWidgetObj
  UiStatusBar* = ref UiStatusBarObj

  UiSolidObj = object of UiWidgetObj
    ch*: uint16
    bg*, fg*: uint8
  UiSolid* = ref UiSolidObj

  UiWindowObj = object of UiWidgetObj
  UiWindow* = ref UiWindowObj

proc drawWidget*(gfx: GfxState, widget: UiWidget)
proc drawWidget*(crop: GfxCrop, widget: UiWidget)
method drawWidgetBase*(widget: UiWidget, crop: GfxCrop) {.base.}
method drawWidgetBase*(widget: UiBag, crop: GfxCrop)
method drawWidgetBase*(widget: UiSolid, crop: GfxCrop)
method drawWidgetBase*(widget: UiBoardView, crop: GfxCrop)
method drawWidgetBase*(widget: UiStatusBar, crop: GfxCrop)

import ./grid
import ./script/exprs

proc drawWidget(gfx: GfxState, widget: UiWidget) =
  var innerCrop = GfxCrop(
    gfx: gfx,
    x: widget.x, y: widget.y,
    w: widget.w, h: widget.h,
  )
  widget.drawWidgetBase(innerCrop)

proc drawWidget(crop: GfxCrop, widget: UiWidget) =
  var innerCrop = GfxCrop(
    parent: crop,
    x: widget.x, y: widget.y,
    w: widget.w, h: widget.h,
  )
  widget.drawWidgetBase(innerCrop)

method drawWidgetBase(widget: UiWidget, crop: GfxCrop) {.base.} =
  for y in 0..(crop.h-1):
    for x in 0..(crop.w-1):
      crop.drawChar(
        x = x, y = y,
        bg = 0, fg = 13,
        ch = (if (x == 0 or y == 0 or x == crop.w-1 or y == crop.h-1):
            uint16('@')
          elif (x and 1) == 0:
            0xDC
          else:
            0xDF),
      )

method drawWidgetBase(widget: UiBag, crop: GfxCrop) =
  var
    ch = widget.ch
    bg = widget.bg
    fg = widget.fg

  for y in 0..(crop.h-1):
    for x in 0..(crop.w-1):
      crop.drawChar(
        x = x, y = y,
        bg = bg, fg = fg, ch = ch,
      )

  for innerWidget in widget.widgets:
    crop.drawWidget(innerWidget)

method drawWidgetBase(widget: UiSolid, crop: GfxCrop) =
  var
    ch = widget.ch
    bg = widget.bg
    fg = widget.fg

  for y in 0..(crop.h-1):
    for x in 0..(crop.w-1):
      crop.drawChar(
        x = x, y = y,
        bg = bg, fg = fg, ch = ch,
      )

method drawWidgetBase(widget: UiBoardView, crop: GfxCrop) =
  var board = widget.board
  assert board != nil

  for y in 0..(min(crop.h, board.grid.h)-1):
    for x in 0..(min(crop.w, board.grid.w)-1):
      var entseq = board.grid[x, y]
      var (fgcolor, bgcolor, ch) = if entseq.len >= 1:
          var entity = entseq[entseq.len-1]
          var execBase = entity.execBase
          assert execBase != nil

          var ch = try: uint64(entity.params["char"].asInt())
            except KeyError: uint64('?')
          var fgcolor = try: uint64(entity.params["fgcolor"].asInt())
            except KeyError: 0x07'u64
          var bgcolor = try: uint64(entity.params["bgcolor"].asInt())
            except KeyError: 0x00'u64

          (fgcolor, bgcolor, ch)

        else:
          (0x07'u64, 0x00'u64, uint64(' '))
      crop.drawChar(
        x = x, y = y,
        bg = uint8(bgcolor),
        fg = uint8(fgcolor),
        ch = uint16(ch),
      )

method drawWidgetBase(widget: UiStatusBar, crop: GfxCrop) =
  crop.clearToState(bg = 1, fg = 14, ch = uint16(' '))

  crop.drawCharArray(x =  6, y =  0, bg =  1, fg =  8, chs = "\xDC\xDC\xDC\xDC\xDC\xDC\xDC")
  crop.drawCharArray(x =  3, y =  1, bg =  1, fg =  8, chs = "\xDC 123456789 \xDC")
  crop.drawCharArray(x =  2, y =  2, bg =  1, fg =  7, chs = "\xDE  123456789  \xDD")
  crop.drawCharArray(x =  2, y =  4, bg =  1, fg =  7, chs = "\xDE  123456789  \xDD")
  crop.drawCharArray(x =  4, y =  1, bg =  8, fg = 15, chs = " Z E B R A ")
  crop.drawCharArray(x =  3, y =  2, bg =  7, fg =  0, chs = " \xDA\xC4\xC4\xC4\xDA\xC4\xC4\xDA\xC4\xC4\xBF ")
  crop.drawCharArray(x =  2, y =  3, bg =  7, fg =  0, chs = "  \xB3 \xC4\xBF\xB3  \xC0\xC4\xC4\xBF  ")
  crop.drawCharArray(x =  3, y =  4, bg =  7, fg =  0, chs = " \xC0\xC4\xC4\xD9\xC0\xC4\xC4\xD9\xC4\xC4\xD9 ")
  crop.drawCharArray(x =  4, y =  5, bg =  1, fg =  8, chs = "\xDF\xDF\xDB\xDB\xDB\xDB\xDB\xDB\xDB\xDF\xDF")

  crop.drawCharArray(x =  3, y =  7, bg =  1, fg = 14, chs = "Score:")
  crop.drawCharArray(x =  3, y =  8, bg =  1, fg = 14, chs = "             0")
  crop.drawCharArray(x =  3, y = 10, bg =  1, fg = 14, chs = "Health:    100")
  crop.drawCharArray(x =  3, y = 11, bg =  1, fg = 14, chs = "Ammo:        0")
  crop.drawCharArray(x =  3, y = 12, bg =  1, fg = 14, chs = "Gems:        0")
  crop.drawCharArray(x =  3, y = 14, bg =  1, fg = 14, chs = "Status Bar    ")
  crop.drawCharArray(x =  3, y = 15, bg =  1, fg = 14, chs = "Fakeness: 100%")

  crop.drawCharArray(x =  2, y = 19, bg =  3, fg =  0, chs = " W ")
  crop.drawCharArray(x =  6, y = 19, bg =  1, fg = 14, chs = "World select")
  crop.drawCharArray(x =  2, y = 20, bg =  7, fg =  0, chs = " P ")
  crop.drawCharArray(x =  6, y = 20, bg =  1, fg = 14, chs = "Play world")
  crop.drawCharArray(x =  2, y = 21, bg =  3, fg =  0, chs = " E ")
  crop.drawCharArray(x =  6, y = 21, bg =  1, fg = 14, chs = "Edit world")
  crop.drawCharArray(x =  2, y = 22, bg =  7, fg =  0, chs = " L ")
  crop.drawCharArray(x =  6, y = 22, bg =  1, fg = 14, chs = "Load game")
  crop.drawCharArray(x =  2, y = 23, bg =  3, fg =  0, chs = " Q ")
  crop.drawCharArray(x =  6, y = 23, bg =  1, fg = 14, chs = "Quit game")
