# We need something that can actually intern keys consistently.

import strformat
import tables

type
  InternTableError* = object of CatchableError

  InternKey* = int

  InternTableBaseObj = object
    idxToStr: seq[string]
    strToIdx: Table[string, InternKey]
  InternTableBase* = ref InternTableBaseObj

  InternTableObj[V] = object
    values: seq[V]
    presence: seq[bool]
  InternTable*[V] = ref InternTableObj[V]


var globalInternBase = InternTableBase(
  idxToStr: @[],
  strToIdx: initTable[string, InternKey](),
)


proc initInternTable*[V](): InternTable[V] =
  var itab = InternTable[V](
    values: @[],
    presence: @[],
  )
  itab

proc internKey*(key: string): InternKey =
  try:
    globalInternBase.strToIdx[key]
  except KeyError:
    var r = globalInternBase.idxToStr.len
    globalInternBase.idxToStr.add(key)
    globalInternBase.strToIdx[key] = r
    r

proc internKeyCT*(key: string): InternKey {.compileTime.} =
  internKey(key)

proc `[]`*[V](itab: InternTable[V], idx: int): var V =
  if idx < itab.presence.len and itab.presence[idx]:
    result = itab.values[idx]
  else:
    raise newException(KeyError, &"index {idx} not found")

proc `[]`*[V](itab: InternTable[V], key: string): var V =
  var idx = globalInternBase.strToIdx[key]
  itab[idx]

proc `[]=`*[V](itab: var InternTable[V], idx: int, val: V) =
  assert itab != nil
  while itab.presence.len <= idx:
    itab.presence.add(false)
    itab.values.add(nil)
  itab.presence[idx] = true
  itab.values[idx] = val

proc `[]=`*[V](itab: var InternTable[V], key: string, val: V) =
  itab[internKey(key)] = val

iterator indexedPairs*[V](itab: InternTable[V]): tuple[idx: InternKey, val: V] =
  assert itab != nil
  for i in 0..itab.presence.high:
    if itab.presence[i]:
      yield (i, itab.values[i])

iterator values*[V](itab: InternTable[V]): V =
  assert itab != nil
  for i in 0..itab.presence.high:
    if itab.presence[i]:
      yield itab.values[i]

proc contains*[V](itab: InternTable[V], idx: int): bool =
  assert idx >= 0
  (idx < itab.presence.len and itab.presence[idx])

proc contains*[V](itab: InternTable[V], key: string): bool =
  try:
    var idx = globalInternBase.strToIdx[key]
    (idx < itab.presence.len and itab.presence[idx])
  except KeyError:
    false

proc `$`*(x: InternTableBase): string =
  var accum = "InternTableBase("
  var i: int = 0;
  while i < x.idxToStr.len:
    var s = x.idxToStr[i]
    if i >= 1:
      accum &= ", "
    accum &= s
    i += 1
  accum &= ")"
  accum
  
proc `$`*[V](x: InternTable[V]): string =
  var accum = "InternTable[" & $V & "]{"
  var i: int = 0;
  var first: bool = true
  while i < x.presence.len:
    if x.presence[i]:
      if not first:
        accum &= ", "
      accum &= globalInternBase.idxToStr[i]
      accum &= ":"
      accum &= $(x.values[i])
      first = false
    i += 1
  accum &= "}"
  accum
