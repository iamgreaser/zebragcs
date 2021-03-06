# We need something that can actually intern keys consistently.

import macros
import strformat
import tables

type
  InternTableError* = object of CatchableError

  InternKey* = distinct int

  InternTableBaseObj = object
    idxToStr: seq[string]
    strToIdx: Table[string, InternKey]
  InternTableBase* = ref InternTableBaseObj

  InternTableObj[V] = object
    values: seq[V]
    presence: seq[bool]
  InternTable*[V] = ref InternTableObj[V]


var globalInternInitStrings* {.compileTime.}: seq[string]
var globalInternBase*: InternTableBase


proc initInternTable*[V](): InternTable[V] =
  var itab = InternTable[V](
    values: @[],
    presence: @[],
  )
  itab

proc internKey*(key: string): InternKey =
  try:
    #echo "Grabbing interned key " & $key
    globalInternBase.strToIdx[key]
  except KeyError:
    var r: InternKey = InternKey(globalInternBase.idxToStr.len)
    globalInternBase.idxToStr.add(key)
    echo "Interning key " & $key
    globalInternBase.strToIdx[key] = r
    r

proc internKeyCT*(key: string): InternKey {.compileTime.} =
  if not globalInternInitStrings.contains(key):
    globalInternInitStrings.add(key)
    echo "Pre-interning key " & $key

  let k = globalInternInitStrings.find(key)
  assert k >= 0
  return InternKey(k)

proc `==`*(a, b: InternKey): bool =
  return int(a) == int(b)


proc `[]`*[V](itab: InternTable[V], idx: InternKey): var V =
  if int(idx) < itab.presence.len and itab.presence[int(idx)]:
    result = itab.values[int(idx)]
  else:
    raise newException(KeyError, &"index {idx} not found")

proc `[]=`*[V](itab: var InternTable[V], idx: InternKey, val: V) =
  assert itab != nil
  while itab.presence.len <= int(idx):
    itab.presence.add(false)
    itab.values.add(nil)
  itab.presence[int(idx)] = true
  itab.values[int(idx)] = val

macro `[]`*[V](itab: InternTable[V], key: string): var V =
  if key.kind == nnkStrLit:
    let idx: InternKey = internKeyCT(key.strVal)
    quote: `itab`[InternKey(`idx`)]
  else:
    quote: `itab`[internKey(`key`)]

macro `[]=`*[V](itab: var InternTable[V], key: string, val: V) =
  if key.kind == nnkStrLit:
    let idx = internKeyCT(key.strVal)
    quote: `itab`[InternKey(`idx`)] = `val`
  else:
    quote: `itab`[internKey(`key`)] = `val`

iterator indexedPairs*[V](itab: InternTable[V]): tuple[idx: InternKey, val: V] =
  assert itab != nil
  for i in 0..itab.presence.high:
    if itab.presence[i]:
      yield (InternKey(i), itab.values[i])

iterator values*[V](itab: InternTable[V]): V =
  assert itab != nil
  for i in 0..itab.presence.high:
    if itab.presence[i]:
      yield itab.values[i]

proc contains*[V](itab: InternTable[V], idx: InternKey): bool =
  assert int(idx) >= 0
  (int(idx) < itab.presence.len and itab.presence[int(idx)])

proc contains*[V](itab: InternTable[V], key: string): bool =
  try:
    var idx = int(globalInternBase.strToIdx[key])
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

macro internCase*(body: untyped): untyped =
  var caseRoot = case body.kind
    of nnkStmtListExpr:
      assert body.len == 1
      case body[0].kind
      of nnkCaseStmt: body[0]
      else:
        echo body.treeRepr
        raise newException(Exception, "Expected case block")
    of nnkCaseStmt: body
    else:
      echo body.treeRepr
      raise newException(Exception, "Expected case block")

  assert caseRoot.kind == nnkCaseStmt

  for caseIdx in (1..(caseRoot.len-1)):
    var caseNode = caseRoot[caseIdx]
    case caseNode.kind
    of nnkOfBranch:
      for ofIdx in (0..(caseNode.len-1-1)):
        var ofNode = caseNode[ofIdx]
        caseNode[ofIdx] = case ofNode.kind
          of nnkStrLit: newTree(nnkCall, ident("internKeyCT"), ofNode)
          else:
            echo ofNode.treeRepr
            raise newException(Exception, "Unhandled case comparison")
      #echo caseNode.treeRepr

    of nnkElse: discard

    else:
      echo caseNode.treeRepr
      raise newException(Exception, "Unhandled case node")

  body

proc getInternName*(x: InternKey): string =
  globalInternBase.idxToStr[int(x)]

proc initInternTableBase*(initStrings: seq[string]) =
  globalInternBase = InternTableBase(
    idxToStr: @[],
    strToIdx: initTable[string, InternKey](),
  )
  echo "Setting up intern table base..."
  for i in 0..initStrings.high:
    let k = initStrings[i]
    globalInternBase.idxToStr.add(k)
    globalInternBase.strToIdx[k] = InternKey(i)
  echo "Globals: " & $globalInternBase
  echo "Base done."

proc `$`*(x: InternKey): string =
  &"IK({int(x)}: {x.getInternName()})"
