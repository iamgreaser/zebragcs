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
  GfxStateObj = object
    renderer: sdl2.RendererPtr
    window: sdl2.WindowPtr
    fontTex: sdl2.TexturePtr
    grid: array[0..(gfxHeight-1), array[0..(gfxWidth-1), GfxCell]]
  GfxState* = ref GfxStateObj

  GfxCropObj = object
    gfx*: GfxState
    parent*: GfxCrop
    x*, y*: int64
    w*, h*: int64
  GfxCrop* = ref GfxCropObj

import strformat

import ./types

proc clearToState*(crop: GfxCrop, bg: uint8, fg: uint8, ch: uint16)
proc close*(gfx: GfxState)
proc drawChar*(crop: GfxCrop, x: int64, y: int64, bg: uint8, fg: uint8, ch: uint16)
proc drawChar*(gfx: GfxState, x: int64, y: int64, bg: uint8, fg: uint8, ch: uint16)
proc drawCharArray*(crop: GfxCrop, x: int64, y: int64, bg: uint8, fg: uint8, chs: openArray[uint16])
proc drawCharArray*(crop: GfxCrop, x: int64, y: int64, bg: uint8, fg: uint8, chs: string)
proc getNextInput*(gfx: GfxState): InputEvent
proc openGfx*(): GfxState
proc present*(gfx: GfxState)

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

proc drawChar(crop: GfxCrop, x: int64, y: int64, bg: uint8, fg: uint8, ch: uint16) =
  # Clip out-of-range coordinates
  if y < 0 or y >= crop.h:
    return
  if x < 0 or x >= crop.w:
    return

  if crop.parent != nil:
    assert crop.gfx == nil
    drawChar(crop.parent, x + crop.x, y + crop.y, bg, fg, ch)
  else:
    assert crop.gfx != nil
    drawChar(crop.gfx, x + crop.x, y + crop.y, bg, fg, ch)

proc drawCharArray(crop: GfxCrop, x: int64, y: int64, bg: uint8, fg: uint8, chs: openArray[uint16]) =
  for i in low(chs)..high(chs):
    crop.drawChar(
      x = x+i-low(chs), y = y,
      bg = bg, fg = fg,
      ch = chs[i],
    )

proc drawCharArray(crop: GfxCrop, x: int64, y: int64, bg: uint8, fg: uint8, chs: string) =
  for i in low(chs)..high(chs):
    crop.drawChar(
      x = x+i-low(chs), y = y,
      bg = bg, fg = fg,
      ch = uint16(chs[i]),
    )

proc clearToState(crop: GfxCrop, bg: uint8, fg: uint8, ch: uint16) =
  for y in 0..(crop.h-1):
    for x in 0..(crop.w-1):
      crop.drawChar(
        x = x, y = y,
        bg = bg, fg = fg,
        ch = ch,
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
