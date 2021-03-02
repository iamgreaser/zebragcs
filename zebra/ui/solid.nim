from ./types import UiWidget, UiWidgetObj, drawWidget
from ../gfx import GfxCrop, clearToState, drawChar

type
  UiSolidObj* = object of UiWidgetObj
    ch*: uint16
    bg*, fg*: uint8
  UiSolid* = ref UiSolidObj

method drawWidgetBase*(widget: UiSolid, crop: GfxCrop)


method drawWidgetBase(widget: UiSolid, crop: GfxCrop) =
  crop.clearToState(bg = widget.bg, fg = widget.fg, ch = widget.ch)
