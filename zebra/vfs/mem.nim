import streams
import tables

import ./types

proc newMemFs*(): MemFs
method openReadStream*(vfs: MemFs, path: seq[string]): Stream

proc newMemFs(): MemFs =
  MemFs(
    dirTable: initTable[string, string](),
    fileTable: initTable[string, string](),
  )

method openReadStream*(vfs: MemFs, path: seq[string]): Stream =
  var fileData = vfs.files[path.join("/")]
  newStringStream(fileData)
