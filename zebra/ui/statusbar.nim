import strformat
from ./types import UiWidget, UiWidgetObj, UiThemeTextType, drawWidget, drawText
from ../gfx import GfxCrop, clearToState, drawChar, drawCharArray

type
  UiStatusBarObj* = object of UiWidgetObj
    textLabels*: seq[string]
    keyLabels*: seq[tuple[key: string, desc: string]]
  UiStatusBar* = ref UiStatusBarObj

method drawWidgetBase*(widget: UiStatusBar, crop: GfxCrop)


method drawWidgetBase(widget: UiStatusBar, crop: GfxCrop) =
  #crop.clearToState(bg = 1, fg = 14, ch = uint16(' '))

  var tr: uint8 = 1 # TODO: Support backgrounds other than colour #1 --GM
  crop.drawCharArray(x =  6, y =  1, bg = tr, fg =  8, chs = "\xDC\xDC\xDC\xDC\xDC\xDC\xDC")
  crop.drawCharArray(x =  3, y =  2, bg = tr, fg =  8, chs = "\xDC 123456789 \xDC")
  crop.drawCharArray(x =  2, y =  3, bg = tr, fg =  7, chs = "\xDE  123456789  \xDD")
  crop.drawCharArray(x =  2, y =  5, bg = tr, fg =  7, chs = "\xDE  123456789  \xDD")
  crop.drawCharArray(x =  4, y =  2, bg =  8, fg = 15, chs = " Z E B R A ")
  crop.drawCharArray(x =  3, y =  3, bg =  7, fg =  0, chs = " \xDA\xC4\xC4\xC4\xDA\xC4\xC4\xDA\xC4\xC4\xBF ")
  crop.drawCharArray(x =  2, y =  4, bg =  7, fg =  0, chs = "  \xB3 \xC4\xBF\xB3  \xC0\xC4\xC4\xBF  ")
  crop.drawCharArray(x =  3, y =  5, bg =  7, fg =  0, chs = " \xC0\xC4\xC4\xD9\xC0\xC4\xC4\xD9\xC4\xC4\xD9 ")
  crop.drawCharArray(x =  4, y =  6, bg = tr, fg =  8, chs = "\xDF\xDF\xDB\xDB\xDB\xDB\xDB\xDB\xDB\xDF\xDF")

  var textLabelY: int64 = 9
  for label in widget.textLabels:
    widget.drawText(crop, 2, textLabelY, themeTextNormal, label)
    textLabelY += 1

  var keyLabelY: int64 = 23-(widget.keyLabels.len-1)
  for label in widget.keyLabels:
    widget.drawText(crop, 2, keyLabelY, themeTextKeyInfo, &" {label.key} ")
    widget.drawText(crop, 5+label.key.len, keyLabelY, themeTextNormal, label.desc)
    keyLabelY += 1
