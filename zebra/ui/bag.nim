from ./types import UiWidget, UiWidgetObj, drawWidget, drawWidgetBase, refreshLayout
from ../gfx import GfxCrop, drawChar

type
  UiBagObj* = object of UiWidgetObj
    widgets*: seq[UiWidget]
  UiBag* = ref UiBagObj

method drawWidgetBase*(widget: UiBag, crop: GfxCrop)
method refreshLayout*(widget: UiBag)


method drawWidgetBase(widget: UiBag, crop: GfxCrop) =
  procCall drawWidgetBase(UiWidget(widget), crop)

  for innerWidget in widget.widgets:
    crop.drawWidget(innerWidget)

method refreshLayout(widget: UiBag) =
  procCall refreshLayout(UiWidget(widget))

  for innerWidget in widget.widgets:
    innerWidget.theme = widget.theme
    innerWidget.refreshLayout()
