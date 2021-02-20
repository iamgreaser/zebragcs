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

method openReadStream*(vfs: FsBase, fname: string): Stream {.base.} =
  raise newException(VfsError, &"unimplemented openReadStream for VFS {vfs}")
method vfsGlob*(vfs: FsBase, pattern: string): seq[string] {.base.} =
  raise newException(VfsError, &"unimplemented vfsGlob for VFS {vfs}")
