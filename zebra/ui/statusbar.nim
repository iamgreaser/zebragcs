import strformat
from ./widget import UiWidget, UiWidgetObj, drawWidget
from ../gfx import GfxCrop, clearToState, drawChar, drawCharArray

type
  UiStatusBarObj* = object of UiWidgetObj
    textLabels*: seq[string]
    keyLabels*: seq[tuple[key: string, desc: string]]
  UiStatusBar* = ref UiStatusBarObj

method drawWidgetBase*(widget: UiStatusBar, crop: GfxCrop)


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

  var textLabelY: int64 = 8
  for label in widget.textLabels:
    crop.drawCharArray(x =  2, y = textLabelY, bg = 1, fg = 14, chs = label)
    textLabelY += 1

  var keyLabelY: int64 = 23-(widget.keyLabels.len-1)
  for label in widget.keyLabels:
    var bg = if (keyLabelY mod 2) == 0: 3'u8
      else: 7'u8
    crop.drawCharArray(x =  2, y = keyLabelY, bg = bg, fg =  0, chs = &" {label.key} ")
    crop.drawCharArray(x =  5+label.key.len, y = keyLabelY, bg =  1, fg = 14, chs = label.desc)
    keyLabelY += 1
