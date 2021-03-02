import strformat
from ./types import UiWidget, UiWidgetObj, drawWidget, drawText, UiThemeTextType
from ../gfx import GfxCrop, drawChar, drawCharArray

type
  UiWindowObj* = object of UiWidgetObj
    bg*, fgText*, fgBorder*, fgPointer*: uint8
    cursorY*: int64
    title*: string
    textLines*: seq[string]
    menuLines*: seq[string]
  UiWindow* = ref UiWindowObj

method drawWidgetBase*(widget: UiWindow, crop: GfxCrop)


method drawWidgetBase*(widget: UiWindow, crop: GfxCrop) =
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
      widget.drawText(crop, 2, i + 1, themeTextNormal, text)
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
      widget.drawText(crop, 4, i + yOffset, themeTextNormal, text)
    crop.drawChar(x = 2, y = widget.cursorY + yOffset, bg = widget.bg, fg = widget.fgPointer, ch = 16'u16)
    yOffset += widget.menuLines.len

  if widget.title != "":
    var title = &" {widget.title} "
    widget.drawText(crop, (widget.innerRect.w - title.len) div 2, 0, themeTextNormal, title)
