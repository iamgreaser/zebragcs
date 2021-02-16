# This reference helped:
# https://hookrace.net/blog/writing-a-2d-platform-game-in-nim-with-sdl2/

const defaultCharset = staticRead("dat/ascii.chr")

const defaultPalette: array[0..(16-1), tuple[r: uint8, g: uint8, b: uint8]] = [
  (uint8(0x00), uint8(0x00), uint8(0x00)),
  (uint8(0x00), uint8(0x00), uint8(0xAA)),
  (uint8(0x00), uint8(0xAA), uint8(0x00)),
  (uint8(0x00), uint8(0xAA), uint8(0xAA)),
  (uint8(0xAA), uint8(0x00), uint8(0x00)),
  (uint8(0xAA), uint8(0x00), uint8(0xAA)),
  (uint8(0xAA), uint8(0x55), uint8(0x00)),
  (uint8(0xAA), uint8(0xAA), uint8(0xAA)),
  (uint8(0x55), uint8(0x55), uint8(0x55)),
  (uint8(0x55), uint8(0x55), uint8(0xFF)),
  (uint8(0x55), uint8(0xFF), uint8(0x55)),
  (uint8(0x55), uint8(0xFF), uint8(0xFF)),
  (uint8(0xFF), uint8(0x55), uint8(0x55)),
  (uint8(0xFF), uint8(0x55), uint8(0xFF)),
  (uint8(0xFF), uint8(0xFF), uint8(0x55)),
  (uint8(0xFF), uint8(0xFF), uint8(0xFF)),
]

import sdl2

const gfxWidth* = 80
const gfxHeight* = 25
type
  SDLException = object of CatchableError
  GfxCell = object
    ch: uint16
    fg, bg: uint8
  GfxState* = ref GfxStateObj
  GfxStateObj = object
    renderer: sdl2.RendererPtr
    window: sdl2.WindowPtr
    fontTex: sdl2.TexturePtr
    grid: array[0..(gfxHeight-1), array[0..(gfxWidth-1), GfxCell]]

import strformat
import tables

import ./types

proc close*(gfx: GfxState)
proc draw*(gfx: GfxState, board: Board)
proc drawChar*(gfx: GfxState, x: int64, y: int64, bg: uint8, fg: uint8, ch: uint16)
proc drawCharArray*(gfx: GfxState, x: int64, y: int64, bg: uint8, fg: uint8, chs: openArray[uint16])
proc drawCharArray*(gfx: GfxState, x: int64, y: int64, bg: uint8, fg: uint8, chs: string)
proc present*(gfx: GfxState)
proc getNextInput*(gfx: GfxState): InputEvent
proc openGfx*(): GfxState

import ./script/exprs

template withOpenGfx*(gfx: untyped, body: untyped): untyped =
  block:
    var gfx: GfxState = openGfx()
    try:
      body
    finally:
      gfx.close()

proc sdlAssertTrue(test: bool, failMsg: string) =
  if not test:
    var err = sdl2.getError()
    raise newException(SDLException, &"{failMsg}: {err}")

proc openGfx(): GfxState =
  sdlAssertTrue(sdl2.init(INIT_VIDEO or INIT_TIMER or INIT_EVENTS), &"sdl2.init failed")
  let window = sdl2.createWindow(
    title = "ZebraGCS",
    x = SDL_WINDOWPOS_UNDEFINED,
    y = SDL_WINDOWPOS_UNDEFINED,
    w = 640,
    h = 350,
    flags = 0,
  )
  let renderer = window.createRenderer(
    index = -1,
    flags = 0,
  )

  # Now load the font
  let fontTex = renderer.createTexture(
    format = SDL_PIXELFORMAT_BGRA8888,
    access = SDL_TEXTUREACCESS_STREAMING,
    w = 8*16,
    h = 14*16,
  )
  block:
    var pixelsPtr: pointer = nil
    var pitch: cint = 0
    let didlock = fontTex.lockTexture(
      rect = nil,
      pixels = addr(pixelsPtr),
      pitch = addr(pitch),
    )
    assert didlock
    defer: fontTex.unlockTexture()

    for i in 0..(256-1):
      for y in 0..(14-1):
        for x in 0..(8-1):
          let color: uint32 = if ((int(defaultCharset[i*14+y]) shr (7-x)) and 0x1) != 0:
              uint32(0xFFFFFFFF)
            else:
              uint32(0x00000000)
          let pidx = (y + 14*(i shr 4))*(pitch shr 2) + (x + 8*(i and 0xF))
          cast[ptr uint32](cast[int](pixelsPtr) + pidx*4)[] = color

  var gfx = GfxState(
    window: window,
    renderer: renderer,
    fontTex: fontTex,
  )

  gfx

proc close(gfx: GfxState) =
  gfx.fontTex.destroy()
  gfx.renderer.destroy()
  gfx.window.destroy()
  sdl2.quit()

proc getNextInput*(gfx: GfxState): InputEvent =
  var sev: sdl2.Event
  while sdl2.pollEvent(sev):
    case sev.kind

    of QuitEvent:
      return InputEvent(kind: ievQuit)

    of KeyDown, KeyUp:
      var sevKey = cast[sdl2.KeyboardEventPtr](addr(sev))

      var keyType = case sevKey.keysym.scancode
        of SDL_SCANCODE_UP: ikUp
        of SDL_SCANCODE_DOWN: ikDown
        of SDL_SCANCODE_LEFT: ikLeft
        of SDL_SCANCODE_RIGHT: ikRight
        of SDL_SCANCODE_LSHIFT: ikShift
        of SDL_SCANCODE_LCTRL: ikCtrl
        of SDL_SCANCODE_ESCAPE: ikEsc

        of SDL_SCANCODE_0: ik0
        of SDL_SCANCODE_1: ik1
        of SDL_SCANCODE_2: ik2
        of SDL_SCANCODE_3: ik3
        of SDL_SCANCODE_4: ik4
        of SDL_SCANCODE_5: ik5
        of SDL_SCANCODE_6: ik6
        of SDL_SCANCODE_7: ik7
        of SDL_SCANCODE_8: ik8
        of SDL_SCANCODE_9: ik9

        of SDL_SCANCODE_A: ikA
        of SDL_SCANCODE_B: ikB
        of SDL_SCANCODE_C: ikC
        of SDL_SCANCODE_D: ikD
        of SDL_SCANCODE_E: ikE
        of SDL_SCANCODE_F: ikF
        of SDL_SCANCODE_G: ikG
        of SDL_SCANCODE_H: ikH
        of SDL_SCANCODE_I: ikI
        of SDL_SCANCODE_J: ikJ
        of SDL_SCANCODE_K: ikK
        of SDL_SCANCODE_L: ikL
        of SDL_SCANCODE_M: ikM
        of SDL_SCANCODE_N: ikN
        of SDL_SCANCODE_O: ikO
        of SDL_SCANCODE_P: ikP
        of SDL_SCANCODE_Q: ikQ
        of SDL_SCANCODE_R: ikR
        of SDL_SCANCODE_S: ikS
        of SDL_SCANCODE_T: ikT
        of SDL_SCANCODE_U: ikU
        of SDL_SCANCODE_V: ikV
        of SDL_SCANCODE_W: ikW
        of SDL_SCANCODE_X: ikX
        of SDL_SCANCODE_Y: ikY
        of SDL_SCANCODE_Z: ikZ

        else: continue

      if sev.kind == KeyDown:
        return InputEvent(kind: ievKeyPress, keyType: keyType)
      else:
        return InputEvent(kind: ievKeyRelease, keyType: keyType)

    else:
      discard # Continue through the loop

  InputEvent(kind: ievNone)

proc drawCharDirect(gfx: GfxState, x: int64, y: int64, bg: tuple[r: uint8, g: uint8, b: uint8], fg: tuple[r: uint8, g: uint8, b: uint8], ch: uint16) =
  var renderer = gfx.renderer

  var dstrect = rect(
    x = cint(x*8),
    y = cint(y*14),
    w = cint(8), h = cint(14),
  )

  renderer.setDrawColor(bg.r, bg.g, bg.b, 255)
  renderer.fillRect(dstrect)
  renderer.setDrawColor(fg.r, fg.g, fg.b, 255)
  var srcrect = rect(
    x = cint(ch and 0xF)*8,
    y = cint(ch shr 4)*14,
    w = cint(8), h = cint(14),
  )
  discard gfx.fontTex.setTextureBlendMode(BlendMode_Blend)
  discard gfx.fontTex.setTextureColorMod(fg.r, fg.g, fg.b)
  renderer.copy(
    texture = gfx.fontTex,
    srcrect = addr(srcrect),
    dstrect = addr(dstrect),
  )

proc drawChar(gfx: GfxState, x: int64, y: int64, bg: uint8, fg: uint8, ch: uint16) =
  # Clip out-of-range coordinates
  if y < low(gfx.grid) or y > high(gfx.grid):
    return
  if x < low(gfx.grid[y]) or x > high(gfx.grid[y]):
    return

  gfx.grid[y][x] = GfxCell(
    ch: ch,
    fg: fg,
    bg: bg,
  )

proc drawCharArray(gfx: GfxState, x: int64, y: int64, bg: uint8, fg: uint8, chs: openArray[uint16]) =
  for i in low(chs)..high(chs):
    gfx.drawChar(
      x = x+i-low(chs), y = y,
      bg = bg, fg = fg,
      ch = chs[i],
    )

proc drawCharArray(gfx: GfxState, x: int64, y: int64, bg: uint8, fg: uint8, chs: string) =
  for i in low(chs)..high(chs):
    gfx.drawChar(
      x = x+i-low(chs), y = y,
      bg = bg, fg = fg,
      ch = uint16(chs[i]),
    )

proc draw(gfx: GfxState, board: Board) =
  # TODO: Not hardcode the width and height --GM

  # Fill the screen with blue
  for y in 0..(gfxHeight-1):
    for x in 0..(gfxWidth-1):
      gfx.drawChar(
        x = x, y = y,
        bg = uint8(1),
        fg = uint8(14),
        ch = uint16(' '),
      )

  # Draw a status bar
  gfx.drawCharArray(x = 66, y =  0, bg =  1, fg =  8, chs = "\xDC\xDC\xDC\xDC\xDC\xDC\xDC")
  gfx.drawCharArray(x = 63, y =  1, bg =  1, fg =  8, chs = "\xDC 123456789 \xDC")
  gfx.drawCharArray(x = 62, y =  2, bg =  1, fg =  7, chs = "\xDE  123456789  \xDD")
  gfx.drawCharArray(x = 62, y =  4, bg =  1, fg =  7, chs = "\xDE  123456789  \xDD")
  gfx.drawCharArray(x = 64, y =  1, bg =  8, fg = 15, chs = " Z E B R A ")
  gfx.drawCharArray(x = 63, y =  2, bg =  7, fg =  0, chs = " \xDA\xC4\xC4\xC4\xDA\xC4\xC4\xDA\xC4\xC4\xBF ")
  gfx.drawCharArray(x = 62, y =  3, bg =  7, fg =  0, chs = "  \xB3 \xC4\xBF\xB3  \xC0\xC4\xC4\xBF  ")
  gfx.drawCharArray(x = 63, y =  4, bg =  7, fg =  0, chs = " \xC0\xC4\xC4\xD9\xC0\xC4\xC4\xD9\xC4\xC4\xD9 ")
  gfx.drawCharArray(x = 64, y =  5, bg =  1, fg =  8, chs = "\xDF\xDF\xDB\xDB\xDB\xDB\xDB\xDB\xDB\xDF\xDF")

  gfx.drawCharArray(x = 63, y =  7, bg =  1, fg = 14, chs = "Score:")
  gfx.drawCharArray(x = 63, y =  8, bg =  1, fg = 14, chs = "             0")
  gfx.drawCharArray(x = 63, y = 10, bg =  1, fg = 14, chs = "Health:    100")
  gfx.drawCharArray(x = 63, y = 11, bg =  1, fg = 14, chs = "Ammo:        0")
  gfx.drawCharArray(x = 63, y = 12, bg =  1, fg = 14, chs = "Gems:        0")
  gfx.drawCharArray(x = 63, y = 14, bg =  1, fg = 14, chs = "Status Bar    ")
  gfx.drawCharArray(x = 63, y = 15, bg =  1, fg = 14, chs = "Fakeness: 100%")

  # Draw the board
  for y in 0..(boardHeight-1):
    for x in 0..(boardWidth-1):
      var gridseq = board.grid[y][x]
      var (fgcolor, bgcolor, ch) = if gridseq.len >= 1:
          var entity = gridseq[gridseq.len-1]
          var execBase = entity.execBase
          assert execBase != nil

          var ch = try: uint64(entity.params["char"].asInt())
            except KeyError: uint64('?')
          var fgcolor = try: uint64(entity.params["fgcolor"].asInt())
            except KeyError: 0x07'u64
          var bgcolor = try: uint64(entity.params["bgcolor"].asInt())
            except KeyError: 0x00'u64

          (fgcolor, bgcolor, ch)

        else:
          (0x07'u64, 0x00'u64, uint64(' '))
      gfx.drawChar(
        x = x, y = y,
        bg = uint8(bgcolor),
        fg = uint8(fgcolor),
        ch = uint16(ch),
      )

proc present(gfx: GfxState) =
  # TODO: Not hardcode the width and height --GM
  var renderer = gfx.renderer

  # Draw the grid for real
  for y in 0..(gfxHeight-1):
    for x in 0..(gfxWidth-1):
      var cell = gfx.grid[y][x]
      gfx.drawCharDirect(
        x = x, y = y,
        bg = defaultPalette[cell.bg and 0xF],
        fg = defaultPalette[cell.fg and 0xF],
        ch = cell.ch,
      )

  renderer.present()
  sdl2.delay(50)
