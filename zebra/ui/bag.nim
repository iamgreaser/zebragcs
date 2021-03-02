from ./widget import UiWidget, drawWidget
from ./solid import UiSolid, UiSolidObj, drawWidgetBase
from ../gfx import GfxCrop, drawChar

type
  UiBagObj* = object of UiSolidObj
    widgets*: seq[UiWidget]
  UiBag* = ref UiBagObj

method drawWidgetBase*(widget: UiBag, crop: GfxCrop)


method drawWidgetBase(widget: UiBag, crop: GfxCrop) =
  procCall drawWidgetBase(UiSolid(widget), crop)

  for innerWidget in widget.widgets:
    crop.drawWidget(innerWidget)
