# FIXME: THIS NEEDS TO USE VFS --GM
import macros
import streams
import strformat
import tables

#import typeinfo # WARNING: This is considered by the Nim developers to be unsafe and an unstable API.
import typetraits # WARNING: This is considered by the Nim developers to be unsafe and an unstable API.

#import ./game
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
    saveTuple = 0x06

    # []... TODO
    saveObject = 0x07

    # []
    saveNil = 0x08

    # []... TODO
    saveSequence = 0x0B

proc save*[T](x: var T, fname: string)
proc load*[T](x: var T, fname: string)

proc loadAdd*[T](lt: var LoadTracker, x: var T)

proc saveAdd*[T](st: SaveTracker, x: T)
proc saveAdd*[T](st: SaveTracker, x: seq[T])
proc saveAdd*(st: SaveTracker, x: bool or uint8 or uint16 or uint32 or uint64 or uint or enum)
proc saveAdd*(st: SaveTracker, x: int8 or int16 or int32 or int64 or int)
proc saveAdd*(st: SaveTracker, x: string)
proc saveAdd*[T](st: SaveTracker, x: ref[T] or ptr[T])

proc saveAddPair*[T](st: SaveTracker, key: string, x: T) =
  st.saveAdd(key)
  st.saveAdd(x)

proc saveAddPackedUInt*(st: SaveTracker, x: uint64) =
  var v: uint64 = x
  while v >= 0x80:
    st.strm.write(uint8((v and 0x7F) or 0x80))
    v = v shr 7
  st.strm.write(uint8(v))


macro saveAddImpl*[T](st: SaveTracker, x: T): untyped =
  var xt = x.getType()
  echo &"Implementing {xt.treeRepr}"

  case xt.kind
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
            ident("saveAdd"),
            st,
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
      for field in entries.children():
        case field.kind

        of nnkSym:
          output.add(
            newCall(
              ident("saveAddPair"),
              st,
              newStrLitNode(field.strVal),
              newDotExpr(x, field),
            )
          )
          discard

        of nnkRecCase:
          assert field.len >= 2

          output.add(
            newCall(
              ident("saveAddPair"),
              st,
              newStrLitNode(field[0].strVal),
              newDotExpr(x, field[0]),
            )
          )
          discard
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
                    ident("saveAddPair"),
                    st,
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
                        ident("saveAddPair"),
                        st,
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

    echo &"Output:\n{output.treeRepr}\n\n"
    return output

  else:
    echo &"TODO: {xt.treeRepr}"
    raise newException(Exception, &"TODO: Type")

proc saveAdd[T](st: SaveTracker, x: T) =
  st.strm.write(uint8(saveObject))
  st.saveAddImpl(x)
  st.strm.write(uint8(saveEnd))

proc saveAdd*[T](st: SaveTracker, x: seq[T]) =
  st.strm.write(uint8(saveSequence))
  st.saveAdd(uint64(x.len))
  if x.len >= 1:
    for child in x:
      st.saveAdd(child)

proc saveAdd(st: SaveTracker, x: bool or uint8 or uint16 or uint32 or uint64 or uint or enum) =
  st.strm.write(uint8(saveUInt64))
  st.saveAddPackedUInt(uint64(x))

proc saveAdd(st: SaveTracker, x: int8 or int16 or int32 or int64 or int) =
  if x >= 0:
    st.strm.write(uint8(saveUInt64))
    st.saveAddPackedUInt(uint64(x))
  else:
    st.strm.write(uint8(saveNegInt64))
    st.saveAddPackedUInt(uint64((-1'i64)-int64(x)))

proc saveAdd(st: SaveTracker, x: string) =
  st.saveAdd(uint64(x.len))
  st.strm.write(x)

proc saveAdd[T](st: SaveTracker, x: ref[T] or ptr[T]) =
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
    echo "Saving game..."
    st.saveAdd(x)
    echo "Game saved!"
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

proc loadAdd[T](lt: var LoadTracker, x: var T) =
  #var a = x.toAny()
  #lt.loadAdd(a)
  discard # TODO!
