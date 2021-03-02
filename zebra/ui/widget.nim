import ../gfx

type
  UiWidgetObj* = object of RootObj
    x*, y*: int64
    w*, h*: int64
    scrollX*, scrollY*: int64
  UiWidget* = ref UiWidgetObj

proc drawWidget*(gfx: GfxState, widget: UiWidget)
proc drawWidget*(crop: GfxCrop, widget: UiWidget)
method drawWidgetBase*(widget: UiWidget, crop: GfxCrop) {.base.}

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
