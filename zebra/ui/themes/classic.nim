from ../../gfx import GfxCrop, drawChar, drawCharArray
from ../types import UiRect, UiTheme, UiThemeObj, UiThemeBorderType, UiThemeRectType, UiThemeTextType, UiWidget

type
  UiClassicThemeObj* = object of UiThemeObj
  UiClassicTheme* = ref UiClassicThemeObj

#method drawWidgetTheme*(theme: UiClassicTheme, widget: UiWidget, crop: GfxCrop)

method drawText*(theme: UiClassicTheme, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: seq[uint16])
method fillRect*(theme: UiClassicTheme, crop: GfxCrop, x: int64, y: int64, w: int64, h: int64, rectType: UiThemeRectType)

method expandInnerRect*(theme: UiClassicTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect {.locks: "unknown".}
method contractOuterRect*(theme: UiClassicTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect {.locks: "unknown".}

#method drawWidgetTheme(theme: UiClassicTheme, widget: UiWidget, crop: GfxCrop) =
#  theme.fillRect(crop, widget.outerRect.x, widget.outerRect.y, widget.outerRect.w, widget.outerRect.h, widget.themeRectType)

method drawText(theme: UiClassicTheme, crop: GfxCrop, x: int64, y: int64, textType: UiThemeTextType, text: seq[uint16]) =
  var (fg, bg) = case textType:
    of themeTextNormal: (14'u8, 1'u8)
    of themeTextKeyInfo:
      if (y mod 2) == 0: (0'u8, 3'u8)
      else: (0'u8, 7'u8)

  crop.drawCharArray(
    x = x, y = y,
    fg = fg, bg = bg,
    chs = text,
  )

method fillRect(theme: UiClassicTheme, crop: GfxCrop, x: int64, y: int64, w: int64, h: int64, rectType: UiThemeRectType) =
  var (fg, bg, drawBorder) = case rectType:
    of themeRectRootBackground: (0'u8, 8'u8, false)
    of themeRectBoardViewBackground: (7'u8, 8'u8, true)
    of themeRectBackground: (7'u8, 1'u8, true)

  if drawBorder:
    for py in 0..(h-1):
      for px in 0..(w-1):
        crop.drawChar(
          x = x+px, y = y+py,
          fg = fg, bg = bg,
          ch = if py == 0:
              if px == 0:
                uint16(0xDA)
              elif px == w-1:
                uint16(0xBF)
              else:
                uint16(0xC4)
            elif py == h-1:
              if px == 0:
                uint16(0xC0)
              elif px == w-1:
                uint16(0xD9)
              else:
                uint16(0xC4)
            else:
              if px == 0 or px == w-1:
                uint16(0xB3)
              else:
                uint16(' ')
        )

  else:
    for py in 0..(h-1):
      for px in 0..(w-1):
        crop.drawChar(
          x = x+px, y = y+py,
          fg = fg, bg = bg,
          ch = uint16(' '),
        )

method expandInnerRect(theme: UiClassicTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect =
  case widget.borderType
  of themeBorderNone:
    UiRect(x: x, y: y, w: w, h: h)
  of themeBorderNormal:
    if w == 0 or h == 0:
      # FIXME: Have a proper way to hide a widget --GM
      UiRect(x: x, y: y, w: w, h: h)
    else:
      UiRect(x: x-1, y: y-1, w: w+1+1, h: h+1+1)
method contractOuterRect(theme: UiClassicTheme, widget: UiWidget, x: int64, y: int64, w: int64, h: int64): UiRect =
  case widget.borderType
  of themeBorderNone:
    UiRect(x: x, y: y, w: w, h: h)
  of themeBorderNormal:
    if w == 0 or h == 0:
      # FIXME: Have a proper way to hide a widget --GM
      UiRect(x: x, y: y, w: w, h: h)
    else:
      UiRect(x: x+1, y: y+1, w: w-1-1, h: h-1-1)
