import streams
import tables

import ./types

proc newMemFs*(): MemFs
method openReadStream*(vfs: MemFs, fname: string): Stream

proc newMemFs(): MemFs =
  MemFs(
    fileTable: initTable[string, string](),
  )

method openReadStream*(vfs: MemFs, fname: string): Stream =
  var fileData = vfs.files[fname]
  newStringStream(fileData)
