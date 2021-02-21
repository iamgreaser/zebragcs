import strformat
import tables

import ./types
import ./gfx

type
  UiWidgetObj = object of RootObj
    x*, y*: int64
    w*, h*: int64
    scrollX*, scrollY*: int64
  UiWidget* = ref UiWidgetObj

  UiBagObj = object of UiWidgetObj
    widgets*: seq[UiWidget]
    ch*: uint16
    bg*, fg*: uint8
  UiBag* = ref UiBagObj

  UiBoardViewObj = object of UiWidgetObj
    board*: Board
    cursorVisible*: bool
    cursorX*: int64
    cursorY*: int64
  UiBoardView* = ref UiBoardViewObj
  UiStatusBarObj = object of UiWidgetObj
  UiStatusBar* = ref UiStatusBarObj

  UiSolidObj = object of UiWidgetObj
    ch*: uint16
    bg*, fg*: uint8
  UiSolid* = ref UiSolidObj

  UiWindowObj = object of UiWidgetObj
    bg*, fgText*, fgBorder*, fgPointer*: uint8
    cursorY*: int64
    title*: string
    textLines*: seq[string]
    menuLines*: seq[string]
  UiWindow* = ref UiWindowObj

proc drawWidget*(gfx: GfxState, widget: UiWidget)
proc drawWidget*(crop: GfxCrop, widget: UiWidget)
method drawWidgetBase*(widget: UiWidget, crop: GfxCrop) {.base.}
method drawWidgetBase*(widget: UiBag, crop: GfxCrop)
method drawWidgetBase*(widget: UiSolid, crop: GfxCrop)
method drawWidgetBase*(widget: UiBoardView, crop: GfxCrop)
method drawWidgetBase*(widget: UiStatusBar, crop: GfxCrop)
method drawWidgetBase*(widget: UiWindow, crop: GfxCrop)

import ./grid
import ./script/exprs

proc drawWidget(gfx: GfxState, widget: UiWidget) =
  var innerCrop = GfxCrop(
    gfx: gfx,
    x: widget.x, y: widget.y,
    w: widget.w, h: widget.h,
    scrollX: widget.scrollX, scrollY: widget.scrollY,
  )
  widget.drawWidgetBase(innerCrop)

proc drawWidget(crop: GfxCrop, widget: UiWidget) =
  var innerCrop = GfxCrop(
    parent: crop,
    x: widget.x, y: widget.y,
    w: widget.w, h: widget.h,
    scrollX: widget.scrollX, scrollY: widget.scrollY,
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
  if board == nil:
    return

  for y in 0..(min(crop.h, board.grid.h)-1):
    var py = y + crop.scrollY
    for x in 0..(min(crop.w, board.grid.w)-1):
      var px = x + crop.scrollX
      var entseq = board.grid[px, py]
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
        x = px, y = py,
        bg = uint8(bgcolor),
        fg = uint8(fgcolor),
        ch = uint16(ch),
      )

  if widget.cursorVisible:
    crop.drawChar(x = widget.cursorX-1, y = widget.cursorY, bg = 0'u8, fg = 15'u8, ch = 195'u16)
    crop.drawChar(x = widget.cursorX+1, y = widget.cursorY, bg = 0'u8, fg = 15'u8, ch = 180'u16)
    crop.drawChar(x = widget.cursorX, y = widget.cursorY-1, bg = 0'u8, fg = 15'u8, ch = 194'u16)
    crop.drawChar(x = widget.cursorX, y = widget.cursorY+1, bg = 0'u8, fg = 15'u8, ch = 193'u16)

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

method drawWidgetBase*(widget: UiWindow, crop: GfxCrop) =
  for y in 1..(crop.h-2):
    for x in 1..(crop.w-2):
      crop.drawChar(x = x, y = y, bg = widget.bg, fg = widget.fgBorder, ch = uint16(' '))

  for x in 1..(crop.w-2):
    crop.drawChar(x = x, y = 0, bg = widget.bg, fg = widget.fgBorder, ch = 196'u16)
    crop.drawChar(x = x, y = crop.h-1, bg = widget.bg, fg = widget.fgBorder, ch = 196'u16)
  for y in 1..(crop.h-2):
    crop.drawChar(x = 0, y = y, bg = widget.bg, fg = widget.fgBorder, ch = 179'u16)
    crop.drawChar(x = crop.w-1, y = y, bg = widget.bg, fg = widget.fgBorder, ch = 179'u16)
  crop.drawChar(x = 0, y = 0, bg = widget.bg, fg = widget.fgBorder, ch = 218'u16)
  crop.drawChar(x = crop.w-1, y = 0, bg = widget.bg, fg = widget.fgBorder, ch = 191'u16)
  crop.drawChar(x = 0, y = crop.h-1, bg = widget.bg, fg = widget.fgBorder, ch = 192'u16)
  crop.drawChar(x = crop.w-1, y = crop.h-1, bg = widget.bg, fg = widget.fgBorder, ch = 217'u16)

  var yOffset = 1
  if widget.textLines.len >= 1:
    for i in 0..(widget.textLines.len-1):
      var text = widget.textLines[i]
      crop.drawCharArray(
        x = 2,
        y = i + 1,
        bg = widget.bg,
        fg = widget.fgText,
        chs = text,
      )
    yOffset += widget.textLines.len

  if widget.menuLines.len >= 1:
    if yOffset != 1:
      for x in 1..(crop.w-2):
        crop.drawChar(x = x, y = yOffset, bg = widget.bg, fg = widget.fgBorder, ch = 196'u16)
      crop.drawChar(x = 0, y = yOffset, bg = widget.bg, fg = widget.fgBorder, ch = 195'u16)
      crop.drawChar(x = crop.w-1, y = yOffset, bg = widget.bg, fg = widget.fgBorder, ch = 180'u16)
      yOffset += 1

    for i in 0..(widget.menuLines.len-1):
      var text = widget.menuLines[i]
      crop.drawCharArray(
        x = 4,
        y = i + yOffset,
        bg = widget.bg,
        fg = widget.fgText,
        chs = text,
      )
    crop.drawChar(x = 2, y = widget.cursorY + yOffset, bg = widget.bg, fg = widget.fgPointer, ch = 16'u16)
    yOffset += widget.menuLines.len

  if widget.title != "":
    var title = &" {widget.title} "
    crop.drawCharArray(
      x = (crop.w - title.len) div 2, y = 0,
      # Intentionally inverted here --GM
      bg = widget.fgBorder,
      fg = widget.bg,
      chs = title,
    )
