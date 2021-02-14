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
import tables

import types

proc close*(gfx: GfxState)
proc draw*(gfx: GfxState, board: Board)
proc getNextInput*(gfx: GfxState): InputEvent
proc openGfx*(): GfxState

import scriptexprs

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
        of SDL_SCANCODE_ESCAPE: ikEsc
        else: continue

      if sev.kind == KeyDown:
        return InputEvent(kind: ievKeyPress, keyType: keyType)
      else:
        return InputEvent(kind: ievKeyRelease, keyType: keyType)

    else:
      discard # Continue through the loop

  InputEvent(kind: ievNone)

proc drawChar(gfx: GfxState, x: int64, y: int64, bg: tuple[r: uint8, g: uint8, b: uint8], fg: tuple[r: uint8, g: uint8, b: uint8], ch: uint64) =
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

  for y in 0..(boardHeight-1):
    for x in 0..(boardWidth-1):
      var gridseq = board.grid[y][x]
      var (fgcolor, bgcolor, ch) = if gridseq.len >= 1:
          var entity = gridseq[gridseq.len-1]
          var execState = entity.execState
          assert execState != nil
          var execBase = execState.execBase
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
        bg = defaultPalette[bgcolor and 0xF],
        fg = defaultPalette[fgcolor and 0xF],
        ch = ch,
      )

  renderer.present()
  sdl2.delay(50)
