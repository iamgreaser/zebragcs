import ../gfx

type
  UiRectObj* = object
    x*, y*: int64
    w*, h*: int64
  UiRect* = ref UiRectObj

  UiThemeObj* = object of RootObj
  UiTheme* = ref UiThemeObj

  UiThemeBorderType* = enum
    themeBorderNormal
    # and the non-defaults
    themeBorderNone

  UiThemeRectType* = enum
    themeRectBackground
    # and the non-defaults
    themeRectBoardViewBackground
    themeRectRootBackground

  UiThemeTextType* = enum
    themeTextNormal
    # and the non-defaults
    themeTextKeyInfo

  UiWidgetObj* = object of RootObj
    theme*: UiTheme
    outerRect*: UiRect
    innerRect*: UiRect
    themeRectType*: UiThemeRectType
    borderType*: UiThemeBorderType
    scrollX*, scrollY*: int64
  UiWidget* = ref UiWidgetObj


proc drawWidget*(gfx: GfxState, widget: UiWidget)
proc drawWidget*(crop: GfxCrop, widget: UiWidget)
method drawWidgetBase*(widget: UiWidget, crop: GfxCrop) {.base, locks: "unknown".}
method drawWidgetTheme*(theme: UiTheme, widget: UiWidget, crop: GfxCrop) {.base, locks: "unknown".}

proc drawText*(widget: UiWidget, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: string)
proc drawText*(widget: UiWidget, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: seq[uint16])
proc drawText*(theme: UiTheme, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: string)
method drawText*(theme: UiTheme, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: seq[uint16]) {.base, locks: "unknown".}
method fillRect*(theme: UiTheme, crop: GfxCrop, x: int64, y: int64, w: int64, h: int64, rectType: UiThemeRectType) {.base, locks: "unknown".}

method refreshLayout*(widget: UiWidget) {.base, locks: "unknown".}
method expandInnerRect*(theme: UiTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect {.base, locks: "unknown".}
method contractOuterRect*(theme: UiTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect {.base, locks: "unknown".}


proc drawWidget(gfx: GfxState, widget: UiWidget) =
  var rootCrop = GfxCrop(
    gfx: gfx,
    x: 0, y: 0,
    w: gfxWidth, h: gfxHeight,
    scrollX: 0, scrollY: 0,
  )
  rootCrop.drawWidget(widget)

proc drawWidget(crop: GfxCrop, widget: UiWidget) =
  block:
    var outerCrop = GfxCrop(
      parent: crop,
      x: widget.outerRect.x, y: widget.outerRect.y,
      w: widget.outerRect.w, h: widget.outerRect.h,
      scrollX: widget.scrollX, scrollY: widget.scrollY,
    )
    widget.theme.drawWidgetTheme(widget, outerCrop)

  # We could technically make this a child of outerCrop, but that would double our stack length. --GM
  block:
    var innerCrop = GfxCrop(
      parent: crop,
      x: widget.innerRect.x, y: widget.innerRect.y,
      w: widget.innerRect.w, h: widget.innerRect.h,
      scrollX: widget.scrollX, scrollY: widget.scrollY,
    )
    widget.drawWidgetBase(innerCrop)

method drawWidgetBase(widget: UiWidget, crop: GfxCrop) =
  discard # Draw nothing.

method drawWidgetTheme(theme: UiTheme, widget: UiWidget, crop: GfxCrop) =
  theme.fillRect(crop, 0, 0, widget.outerRect.w, widget.outerRect.h, widget.themeRectType)

method fillRect(theme: UiTheme, crop: GfxCrop, x: int64, y: int64, w: int64, h: int64, rectType: UiThemeRectType) =
  # Draw garbage. Go get yourself a proper theme!
  for py in 0..(h-1):
    for px in 0..(w-1):
      crop.drawChar(
        x = x+px, y = y+py,
        bg = 0, fg = 13,
        ch = (if (px == 0 or py == 0 or px == w or py == h):
            uint16('@')
          elif (px and 1) == 0:
            0xDC
          else:
            0xDF),
      )

proc drawText(widget: UiWidget, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: string) =
  widget.theme.drawText(crop, x, y, textType, text)
proc drawText(widget: UiWidget, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: seq[uint16]) =
  widget.theme.drawText(crop, x, y, textType, text)
proc drawText(theme: UiTheme, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: string) =
  var s: seq[uint16] = @[]
  for c in text: s.add(uint16(c))
  theme.drawText(crop, x, y, textType, s)
method drawText(theme: UiTheme, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: seq[uint16]) =
  # Draw garbage. Go get yourself a proper theme!
  crop.drawCharArray(
    x = x, y = y,
    bg = 2, fg = 12,
    chs = text,
  )

method refreshLayout(widget: UiWidget) =
  widget.outerRect = widget.theme.expandInnerRect(
    widget = widget,
    x = widget.innerRect.x,
    y = widget.innerRect.y,
    w = widget.innerRect.w,
    h = widget.innerRect.h,
  )

method expandInnerRect(theme: UiTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect =
  UiRect(x: x, y: y, w: w, h: h)

method contractOuterRect(theme: UiTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect =
  UiRect(x: x, y: y, w: w, h: h)
