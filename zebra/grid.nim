import ./types

proc `[]`*[T](grid: Grid[T], x: int64, y: int64): var T
proc `[]=`*[T](grid: var Grid[T], x: int64, y: int64, val: T)
proc newGrid*[T](w: int64, h: int64, default: (proc(): T)): Grid[T]
proc newGrid*[T](w: int64, h: int64, default: (proc(x: int64, y: int64): T)): Grid[T]

proc newGrid[T](w: int64, h: int64, default: (proc(): T)): Grid[T] =
  newGrid[T](w, h, (proc(x: int64, y: int64): T =
    default()))

proc newGrid[T](w: int64, h: int64, default: (proc(x: int64, y: int64): T)): Grid[T] =
  var grid = Grid[T](
    w: w, h: h,
    body: @[],
  )

  for y in 0..(h-1):
    for x in 0..(w-1):
      grid.body.add(default(x, y))

  grid

proc `[]`[T](grid: Grid[T], x: int64, y: int64): var T =
  assert x >= 0 and x < grid.w and y >= 0 and y < grid.h
  grid.body[(y*grid.w) + x]

proc `[]=`[T](grid: var Grid[T], x: int64, y: int64, val: T) =
  assert x >= 0 and x < grid.w and y >= 0 and y < grid.h
  grid.body[(y*grid.w) + x] = val
