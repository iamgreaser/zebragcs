import strformat
import streams
import tables

type
  VfsError* = object of CatchableError

  FsBaseObj = object of RootObj
  FsBase* = ref FsBaseObj

  DiskFsObj = object of FsBaseObj
    rootDir*: string
  DiskFs* = ref DiskFsObj

  RamFsObj = object of FsBaseObj
    fileTable*: Table[string, string]
  RamFs* = ref RamFsObj

proc `$`*(x: FsBase): string =
  &"FsBase()"
proc `$`*(x: DiskFs): string =
  &"DiskFs(rootDir={x.rootDir})"
proc `$`*(x: RamFs): string =
  &"RamFs()"

method openReadStream*(vfs: FsBase, path: seq[string]): Stream {.base.} =
  raise newException(VfsError, &"unimplemented openReadStream for VFS {vfs}")
method vfsDirList*(vfs: FsBase, path: seq[string]): seq[string] {.base.} =
  raise newException(VfsError, &"unimplemented vfsDirList for VFS {vfs}")
