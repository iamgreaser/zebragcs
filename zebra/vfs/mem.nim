import streams
import tables

import ./types

proc newMemFs*(): MemFs
method openReadStream*(vfs: MemFs, path: seq[string]): Stream

proc newMemFs(): MemFs =
  MemFs(
    fileTable: initTable[string, string](),
  )

method openReadStream*(vfs: MemFs, path: seq[string]): Stream =
  var fileData = vfs.files[path.join("/")]
  newStringStream(fileData)
