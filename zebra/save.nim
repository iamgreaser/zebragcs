# FIXME: THIS NEEDS TO USE VFS --GM
import macros
import streams
import strformat
import tables

# Only used for getting the name of a type for debugging... and all that's commented out for now --GM
#import typetraits # WARNING: This is considered by the Nim developers to be unsafe and an unstable API.

#import ./game
import ./interntables
#import ./types

type
  SaveTrackerObj = object
    strm*: Stream
    refs*: Table[pointer, uint32]
    nextRef*: uint32
  SaveTracker* = ref SaveTrackerObj

  LoadTrackerObj = object
    strm*: Stream
    refs*: Table[uint32, pointer]
  LoadTracker* = ref LoadTrackerObj

  SaveNodeType* = enum
    # [] - Ends a list
    saveEnd = 0x00

    # [u64]
    saveUInt64 = 0x01

    # (-1)-[u64]
    saveNegInt64 = 0x02

    # [node u64 length] [raw, unterminated string data]
    saveString = 0x03

    # [u32 ref] [node]
    saveRefSet = 0x04

    # [u32 ref]
    saveRefGet = 0x05

    # []... TODO
    saveObject = 0x07

    # []
    saveNil = 0x08

    # []... TODO
    saveSequence = 0x0B

    # []... TODO
    saveMapping = 0x0C

proc save*[T](x: var T, fname: string)
proc load*[T](x: var T, fname: string)

proc saveAdd*[T](st: SaveTracker, x: var T)
proc saveAdd*[T](st: SaveTracker, x: var seq[T])
proc saveAdd*(st: SaveTracker, x: var (bool or uint8 or uint16 or uint32 or uint64 or uint))
proc saveAdd*(st: SaveTracker, x: var (int8 or int16 or int32 or int64 or int))
proc saveAdd*(st: SaveTracker, x: var string)
proc saveAdd*(st: SaveTracker, x: var InternKey)
proc saveAdd*[T](st: SaveTracker, x: var InternTable[T])
proc saveAdd*[T](st: SaveTracker, x: var (ref[T] or ptr[T]))

proc loadTag*(lt: LoadTracker): SaveNodeType
proc loadPackedUInt*(lt: LoadTracker): uint64
proc loadAdd*[T](lt: LoadTracker, x: var T)
proc loadAdd*[T](lt: LoadTracker, x: var seq[T])
proc loadAdd*(lt: LoadTracker, x: var (bool or uint or uint8 or uint16 or uint32 or uint64))
proc loadAdd*(lt: LoadTracker, x: var (int or int8 or int16 or int32 or int64))
proc loadAdd*(lt: LoadTracker, x: var string)
proc loadAdd*(lt: LoadTracker, x: var InternKey)
proc loadAdd*[T](lt: LoadTracker, x: var InternTable[T])
proc loadAdd*[T](lt: LoadTracker, x: var (ref[T] or ptr[T]))

proc saveLoadAddPair*[T](st: SaveTracker, key: string, x: var T) =
  var keyv: string = key
  st.saveAdd(keyv)
  st.saveAdd(x)
proc saveLoadAddPair*[T](lt: LoadTracker, key: string, x: var T) =
  var gotKey: string = ""
  lt.loadAdd(gotKey)
  assert key == gotKey, &"Key mismatch: Got [{gotKey}], expected [{key}]"
  #echo &"Loading key [{key}]"
  lt.loadAdd(x)

macro saveLoadAddKindPair*[R, T](st: SaveTracker, key: string, xRoot: var R, x: T) =
  quote:
    var keyv: string = `key`
    `st`.saveAdd(keyv)
    var xv: `T` = `x`
    `st`.saveAdd(xv)
macro saveLoadAddKindPair*[R, T](lt: LoadTracker, key: string, xRoot: var R, x: T) =
  var keyNameNode = ident(key.strVal)
  var xt = x.getType()
  #echo &"Implementing {xt.treeRepr}"

  #raise newException(Exception, "TODO: Enums")
  quote:
    var needKey: string = `key`
    var gotKey: string = ""
    `lt`.loadAdd(gotKey)
    assert needKey == gotKey, "Key mismatch: Got [" & $gotKey & ", expected [" & $needKey & "]"
    var xv: typeof(`x`)
    `lt`.loadAdd(xv)
    `xRoot` = typeof(`xRoot`)(
      `keyNameNode`: xv,
    )

proc saveLoadAdd*[T](st: SaveTracker, x: var T) =
  st.saveAdd(x)
proc saveLoadAdd*[T](lt: LoadTracker, x: var T) =
  lt.loadAdd(x)

proc saveLoadAddEnum*[T](st: SaveTracker, x: var T) =
  # This one's easy.
  var xv: string = $x
  st.saveAdd(xv)
macro saveLoadAddEnum*[T](lt: LoadTracker, x: var T) =
  # This one's hard so I have to do it as a macro.
  var xt = x.getType()
  assert xt.len >= 2
  var pragmas = xt[0]

  var xvTok = ident("xv")
  var output = quote:
    var `xvTok`: string = ""
    lt.loadAdd(`xvTok`)

  case pragmas.kind
  of nnkEmpty: discard # OK!
  else:
    echo &"TODO: {pragmas.treeRepr} {xt.treeRepr}"
    raise newException(Exception, &"TODO: Enum pragmas")

  var caseBlock = newTree(nnkCaseStmt, xvTok)
  output.add(caseBlock)
  for idx in (1..(xt.len-1)):
    var field = xt[idx]
    case field.kind
    of nnkSym:
      caseBlock.add(
        newTree(
          nnkOfBranch,
          newStrLitNode(field.strVal),
          newTree(
            nnkStmtList,
            newAssignment(x, ident(field.strVal)),
            #newNimNode(nnkDiscardStmt),
          )
        )
      )
      discard

    else:
      echo &"Field {idx:3d}: {field.treeRepr}"
      raise newException(Exception, &"TODO: Enum load field")

  #echo &"out: {output.treeRepr} / {output[^1].treeRepr} / {output.len}"
  #echo &"out: {output.treeRepr}"
  #raise newException(Exception, &"TODO: Enum loads")
  #x = typeof(x)(xv)

  return output

proc saveAddPackedUInt*(st: SaveTracker, x: uint64) =
  var v: uint64 = x
  while v >= 0x80:
    st.strm.write(uint8((v and 0x7F) or 0x80))
    v = v shr 7
  st.strm.write(uint8(v))


macro saveLoadAddImpl*[T](slt: (SaveTracker or LoadTracker), x: var T): untyped =
  var xt = x.getType()
  #echo &"Implementing {xt.treeRepr}"

  case xt.kind
  of nnkEnumTy:
    var output = newNimNode(nnkStmtList)
    assert xt.len >= 2
    output.add(
      newCall(
        ident("saveLoadAddEnum"),
        slt,
        x,
      )
    )
    return output

  of nnkObjectTy:
    var output = newNimNode(nnkStmtList)
    assert xt.len == 3
    var pragmas = xt[0]
    var parents = xt[1]
    var entries = xt[2]

    case pragmas.kind
    of nnkEmpty: discard # OK!
    else:
      echo &"TODO: {pragmas.treeRepr} {parents.treeRepr} {entries.treeRepr}"
      raise newException(Exception, &"TODO: Object pragmas")

    case parents.kind
    of nnkEmpty: discard # OK!
    of nnkSym:
      output.add(
        newCall(
          ident("procCall"),
          newCall(
            ident("saveLoadAdd"),
            slt,
            newCall(
              parents,
              x,
            ),
          ),
        )
      )
    else:
      echo &"TODO: {pragmas.treeRepr} {parents.treeRepr} {entries.treeRepr}"
      raise newException(Exception, &"TODO: Object parents")

    case entries.kind
    of nnkRecList:
      var kindFields: seq[NimNode] = @[]

      # Scan case kinds
      for field in entries.children():
        case field.kind

        of nnkSym:
          discard

        of nnkRecCase:
          assert field.len >= 2

          kindFields.add(field[0])
          discard

        else:
          echo &"TODO: {pragmas.treeRepr} {parents.treeRepr} {entries.treeRepr}"
          echo &"TODO specifically: {field.treeRepr}"
          raise newException(Exception, &"TODO: Object field (kinds check)")

      #echo &"TODO: {pragmas.treeRepr} {parents.treeRepr} {entries.treeRepr}"
      #raise newException(Exception, &"TODO: Object type")

      for field in kindFields:
        output.add(
          newCall(
            ident("saveLoadAddKindPair"),
            slt,
            newStrLitNode(field.strVal),
            x,
            newDotExpr(x, field),
          )
        )

      # Scan main entries
      for field in entries.children():
        case field.kind

        of nnkSym:
          output.add(
            newCall(
              ident("saveLoadAddPair"),
              slt,
              newStrLitNode(field.strVal),
              newDotExpr(x, field),
            )
          )
          discard

        of nnkRecCase:
          assert field.len >= 2

          var caseBlock = newTree(
            nnkCaseStmt,
            newDotExpr(x, field[0]),
          )
          for subidx in (1..(field.len-1)):
            var subfield = field[subidx]
            case subfield.kind
            of nnkOfBranch:
              assert subfield.len >= 2
              var ofNode = newTree(nnkOfBranch)
              for i in (0..(subfield.len-2)):
                ofNode.add(subfield[i])
              var ofBlock = newNimNode(nnkStmtList)
              ofNode.add(ofBlock)
              var ofField = subfield[subfield.len-1]
              case ofField.kind
              of nnkSym:
                ofBlock.add(
                  newCall(
                    ident("saveLoadAddPair"),
                    slt,
                    newStrLitNode(ofField.strVal),
                    newDotExpr(x, ofField),
                  )
                )
                discard

              of nnkRecList:
                for field in ofField.children():
                  case field.kind
                  of nnkSym:
                    ofBlock.add(
                      newCall(
                        ident("saveLoadAddPair"),
                        slt,
                        newStrLitNode(field.strVal),
                        newDotExpr(x, field),
                      )
                    )
                    discard

                  else:
                    echo &"TODO specifically: {field.treeRepr}"
                    raise newException(Exception, &"TODO: Object case field list field")

              else:
                echo &"TODO specifically: {ofField.treeRepr}"
                raise newException(Exception, &"TODO: Object case field field")

              caseBlock.add(ofNode)
              discard

            else:
              echo &"TODO specifically: {subfield.treeRepr}"
              raise newException(Exception, &"TODO: Object case field")

          output.add(caseBlock)
          discard

        else:
          echo &"TODO: {pragmas.treeRepr} {parents.treeRepr} {entries.treeRepr}"
          echo &"TODO specifically: {field.treeRepr}"
          raise newException(Exception, &"TODO: Object field")

      #echo &"TODO: {pragmas.treeRepr} {parents.treeRepr} {entries.treeRepr}"
      #raise newException(Exception, &"TODO: Object type")
    else:
      echo &"TODO: {pragmas.treeRepr} {parents.treeRepr} {entries.treeRepr}"
      raise newException(Exception, &"TODO: Object entries")

    #echo &"Output:\n{output.treeRepr}\n\n"
    return output

  else:
    echo &"TODO: {xt.treeRepr}"
    raise newException(Exception, &"TODO: Type")

proc saveAdd[T](st: SaveTracker, x: var T) =
  st.strm.write(uint8(saveObject))
  st.saveLoadAddImpl(x)
  st.strm.write(uint8(saveEnd))

proc saveAdd*[T](st: SaveTracker, x: var seq[T]) =
  st.strm.write(uint8(saveSequence))
  var xlen: uint64 = uint64(x.len)
  st.saveAdd(xlen)
  if xlen >= 1:
    for i in (0..(xlen-1)):
      st.saveAdd(x[i])

proc saveAdd(st: SaveTracker, x: var (bool or uint8 or uint16 or uint32 or uint64 or uint)) =
  st.strm.write(uint8(saveUInt64))
  st.saveAddPackedUInt(uint64(x))

proc saveAdd(st: SaveTracker, x: var (int8 or int16 or int32 or int64 or int)) =
  if x >= 0:
    st.strm.write(uint8(saveUInt64))
    st.saveAddPackedUInt(uint64(x))
  else:
    st.strm.write(uint8(saveNegInt64))
    st.saveAddPackedUInt(uint64((-1'i64)-int64(x)))

proc saveAdd(st: SaveTracker, x: var string) =
  var xlen: uint64 = uint64(x.len)
  st.strm.write(uint8(saveString))
  st.saveAdd(xlen)
  st.strm.write(x)

proc saveAdd(st: SaveTracker, x: var InternKey) =
  var xv: string = x.getInternName()
  st.saveAdd(xv)

proc saveAdd[T](st: SaveTracker, x: var InternTable[T]) =
  st.strm.write(uint8(saveMapping))
  for k, v in x.indexedPairs():
    var name: string = k.getInternName()
    st.saveAdd(name)
    st.saveAdd(x[k])
  st.strm.write(uint8(saveEnd))

proc saveAdd[T](st: SaveTracker, x: var (ref[T] or ptr[T])) =
  if x == nil:
    st.strm.write(uint8(saveNil))
  else:
    let key = addr(x[])
    #let key = addr(x)
    if st.refs.hasKey(key):
      var refIdx: uint32 = st.refs[key]
      st.strm.write(uint8(saveRefGet))
      #echo &"Saving ref {refIdx}"
      st.saveAdd(uint32(refIdx))
      #echo &"Ref {refIdx} saved"
    else:
      st.strm.write(uint8(saveRefSet))
      var refIdx: uint32 = st.nextRef
      st.nextRef += 1'u32
      #echo &"Adding ref {refIdx}"
      st.refs[key] = refIdx
      st.saveAdd(uint32(refIdx))
      st.saveAdd(x[])

proc save[T](x: var T, fname: string) =
  var strm = newFileStream(fname, fmWrite)
  try:
    var st = SaveTracker(
      strm: strm,
      refs: initTable[pointer, uint32](),
    )
    st.saveAdd(x)
  finally:
    strm.close()

proc load[T](x: var T, fname: string) =
  var strm = newFileStream(fname, fmRead)
  try:
    var lt = LoadTracker(
      strm: strm,
      refs: initTable[uint32, pointer](),
    )
    lt.loadAdd(x)
  finally:
    strm.close()

proc loadTag(lt: LoadTracker): SaveNodeType =
  var tag = lt.strm.readUInt8()
  #echo &"Tag value: {tag:02X}"
  SaveNodeType(tag)

proc loadPackedUInt(lt: LoadTracker): uint64 =
  var accum: uint64 = 0
  var shift: uint64 = 0
  while true:
    var v: uint64 = lt.strm.readUInt8()
    accum += (v and 0x7F'u64) shl shift
    shift += 7
    if (v and 0x80) == 0: break
    assert shift < 64
  return accum

proc loadAdd(lt: LoadTracker, x: var (bool or uint or uint8 or uint16 or uint32 or uint64)) =
  var tag = lt.loadTag()
  case tag
  of saveUInt64:
    var full: uint64 = lt.loadPackedUInt()
    #var typeName = static:
    #  typeof(x).name()
    #echo &"Int type: {typeName}"
    x = typeof(x)(full)
    var rebuilt: uint64 = uint64(x)
    if rebuilt != full:
      raise newException(Exception, &"UInt unpack lost information: {full:X} -> {rebuilt:X}")
  else:
    echo &"Tag: {tag}"
    raise newException(Exception, &"Unhandled uint tag {tag}")

proc loadAdd(lt: LoadTracker, x: var (int or int8 or int16 or int32 or int64)) =
  var tag = lt.loadTag()
  case tag
  # TODO: Negative ints --GM
  of saveUInt64:
    var full: uint64 = lt.loadPackedUInt()
    #var typeName = static:
    #  typeof(x).name()
    #echo &"Int type: {typeName}"
    x = typeof(x)(full)
    var rebuilt: uint64 = uint64(x)
    if rebuilt != full:
      raise newException(Exception, &"UInt unpack lost information: {full:X} -> {rebuilt:X}")

  of saveNegInt64:
    var fullUint: uint64 = lt.loadPackedUInt()
    var full: int64 = (-1'i64)-int64(fullUint)
    #var typeName = static:
    #  typeof(x).name()
    #echo &"Int type: {typeName}"
    x = typeof(x)(full)
    var rebuilt: int64 = int64(x)
    if rebuilt != full:
      raise newException(Exception, &"UInt unpack lost information: {full:X} -> {rebuilt:X}")

  else:
    echo &"Tag: {tag}"
    raise newException(Exception, &"Unhandled uint tag {tag}")

proc loadAdd(lt: LoadTracker, x: var string) =
  var tag = lt.loadTag()
  case tag
  of saveString:
    var xlen: uint64
    lt.loadAdd(xlen)
    x = lt.strm.readStr(int(xlen))
  else:
    echo &"Tag: {tag}"
    raise newException(Exception, &"Unhandled string tag {tag}")

proc loadAdd(lt: LoadTracker, x: var InternKey) =
  var xname: string
  lt.loadAdd(xname)
  x = internKey(xname)

proc loadAdd[T](lt: LoadTracker, x: var seq[T]) =
  var tag = lt.loadTag()
  case tag
  of saveSequence:
    var xlen: uint64
    lt.loadAdd(xlen)
    x = @[]
    x.setLen(xlen)
    if xlen >= 1:
      for idx in (0..(xlen-1)):
        lt.loadAdd(x[idx])
    #echo &"Tag sequence: {tag}"
    #raise newException(Exception, &"Unhandled tag {tag}")
  else:
    echo &"Tag: {tag}"
    raise newException(Exception, &"Unhandled tag {tag}")

proc loadAdd[T](lt: LoadTracker, x: var T) =
  var tag = lt.loadTag()
  case tag
  of saveObject:
    #echo &"Tag object: {tag}"
    lt.saveLoadAddImpl(x)
    var endTag = lt.loadTag()
    case endTag
    of saveEnd: discard # OK!
    else:
      echo &"Tag end: {endTag}"
      raise newException(Exception, &"Unhandled end tag {endTag}")
  else:
    echo &"Tag: {tag}"
    raise newException(Exception, &"Unhandled tag {tag}")

proc loadAdd*[T](lt: LoadTracker, x: var InternTable[T]) =
  var tag = lt.loadTag()
  case tag
  of saveMapping:
    #echo &"Tag object: {tag}"
    x = initInternTable[T]()
    while true:
      var childTag = lt.loadTag()
      case childTag
      of saveEnd: break

      of saveString:
        var namelen: uint64
        lt.loadAdd(namelen)
        var name = lt.strm.readStr(int(namelen))
        var v: T
        lt.loadAdd(v)
        x[internKey(name)] = v

      else:
        echo &"Tag: {childTag}"
        raise newException(Exception, &"Unhandled interntable child tag {childTag}")
  else:
    echo &"Tag: {tag}"
    raise newException(Exception, &"Unhandled interntable tag {tag}")

proc loadAdd[T](lt: LoadTracker, x: var (ref[T] or ptr[T])) =
  var tag = lt.loadTag()
  case tag
  of saveNil:
    x = nil

  of saveRefSet:
    var refIdx: uint32
    lt.loadAdd(refIdx)
    #echo &"Tag set {refIdx}"
    assert not lt.refs.hasKey(refIdx)
    x = new(typeof(x[]))
    lt.refs[refIdx] = addr(x[])
    lt.loadAdd(x[])

  of saveRefGet:
    var refIdx: uint32
    lt.loadAdd(refIdx)
    #echo &"Tag get {refIdx}"
    #assert lt.refs.hasKey(refIdx)
    x = cast[ref[T]](lt.refs[refIdx])

  else:
    echo &"Tag: {tag}"
    raise newException(Exception, &"Unhandled ref tag {tag}")
