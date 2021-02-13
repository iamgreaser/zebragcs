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

type
  SDLException = object of CatchableError
  GfxState = object
    renderer: sdl2.RendererPtr
    window: sdl2.WindowPtr
    fontTex: sdl2.TexturePtr

import strformat

import types

proc openGfx*(): GfxState
proc close*(gfx: GfxState)
proc draw*(gfx: GfxState, board: Board)

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
    title = "gcs",
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

proc drawChar(gfx: GfxState, x: int, y: int, bg: tuple[r: uint8, g: uint8, b: uint8], fg: tuple[r: uint8, g: uint8, b: uint8], ch: int) =
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

proc draw(gfx: GfxState, board: Board) =
  # TODO: Not hardcode the width and height --GM
  var renderer = gfx.renderer

  renderer.setDrawColor(0, 0, 170, 255)
  renderer.fillRect()

  for y in 0..24:
    for x in 0..59:
      var gridseq = board.grid[y][x]
      var (col, ch) = if gridseq.len >= 1:
          var entity = gridseq[gridseq.len-1]
          var execState = entity.execState
          assert execState != nil
          var execBase = execState.execBase
          assert execBase != nil
          case execBase.entityName
            # FIXME: Handle this in execState --GM
            of "player": (0x4F, int('\x02'))
            of "bullet": (0x0F, int('\xF8'))
            else: (0x0F, int('?'))
        else:
          (0x0F, int(' '))
      discard col
      gfx.drawChar(
        x = x, y = y,
        bg = defaultPalette[col shr 4],
        fg = defaultPalette[col and 0xF],
        ch = ch,
      )

  renderer.present()
  sdl2.delay(100)
