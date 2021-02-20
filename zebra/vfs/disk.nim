import os
import streams
import strutils

import ./types

proc newDiskFs*(rootDir: string): DiskFs
method openReadStream*(vfs: DiskFs, path: seq[string]): Stream
method vfsDirList*(vfs: DiskFs, path: seq[string]): seq[string]

proc newDiskFs(rootDir: string): DiskFs =
  DiskFs(
    rootDir: rootDir,
  )

method vfsDirList*(vfs: DiskFs, path: seq[string]): seq[string] =
  var realpattern = (vfs.rootDir & "/" & path.join("/") & "/*").replace("//", "/")
  result = @[]
  for dirName in walkDirs(realpattern):
    result.add(dirName.split("/")[^1])

method vfsFileList*(vfs: DiskFs, path: seq[string]): seq[string] =
  var realpattern = (vfs.rootDir & "/" & path.join("/") & "/*").replace("//", "/")
  result = @[]
  for fileName in walkFiles(realpattern):
    result.add(fileName.split("/")[^1])

method openReadStream*(vfs: DiskFs, path: seq[string]): Stream =
  var realfname = vfs.rootDir & "/" & path.join("/")
  newFileStream(realfname, fmRead)
