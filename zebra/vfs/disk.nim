import os
import streams
import strformat
import strutils

import ./types

proc newDiskFs*(rootDir: string): DiskFs
method openReadStream*(vfs: DiskFs, fname: string): Stream
method vfsGlob*(vfs: DiskFs, pattern: string): seq[string]

proc newDiskFs(rootDir: string): DiskFs =
  DiskFs(
    rootDir: rootDir,
  )

method vfsGlob*(vfs: DiskFs, pattern: string): seq[string] =
  var realpattern = (&"{vfs.rootDir}/{pattern}").replace("//", "/")
  result = @[]
  for dirName in walkDirs(realpattern):
    result.add(dirName)

method openReadStream*(vfs: DiskFs, fname: string): Stream =
  var realfname = (&"{vfs.rootDir}/{fname}").replace("//", "/")
  newFileStream(realfname, fmRead)
