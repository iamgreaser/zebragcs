from ./types import UiWidget, UiWidgetObj, drawWidget
from ../gfx import GfxCrop, drawChar
from ../types as gameTypes import Board, Entity, LayerCell
from ../script/exprs import asInt
import ../grid
import ../interntables

type
  UiBoardViewObj* = object of UiWidgetObj
    board*: Board
    cursorVisible*: bool
    cursorX*: int64
    cursorY*: int64
  UiBoardView* = ref UiBoardViewObj

method drawWidgetBase*(widget: UiBoardView, crop: GfxCrop)


method drawWidgetBase(widget: UiBoardView, crop: GfxCrop) =
  var board = widget.board
  if board == nil:
    return

  for y in 0..(min(crop.h, board.grid.h)-1):
    var py = y + crop.scrollY
    for x in 0..(min(crop.w, board.grid.w)-1):
      var px = x + crop.scrollX
      var entseq = board.grid[px, py]
      var bestZorder: int64 = -100
      var (fgcolor, bgcolor, ch) = if entseq.len >= 1:
          var entity = entseq[entseq.len-1]
          var execBase = entity.execBase
          assert execBase != nil

          var ch = try: uint64(entity.params["char"].asInt(nil))
            except KeyError: uint64('?')
          var fgcolor = try: uint64(entity.params["fgcolor"].asInt(nil))
            except KeyError: 0x07'u64
          var bgcolor = try: uint64(entity.params["bgcolor"].asInt(nil))
            except KeyError: 0x00'u64

          bestZorder = 100
          (fgcolor, bgcolor, ch)

        else:
          (0x07'u64, 0x00'u64, uint64(' '))

      for layerIdx, layer in board.layers.indexedPairs():
        var layerInfo = layer.layerInfo
        if layerInfo.zorder < bestZorder:
          continue

        var cell = layer.grid[px, py]
        if cell != LayerCell(ch: 0, fg: 0, bg: 0):
          bestZorder = layerInfo.zorder
          ch = cell.ch
          fgcolor = cell.fg
          bgcolor = cell.bg

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
