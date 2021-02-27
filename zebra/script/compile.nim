import streams
import strformat
import strutils
import times

import ../interntables
import ../types
import ../vfs/types as vfsTypes

proc newScriptParseState*(strm: Stream, fname: string): ScriptParseState
proc newScriptSharedExecState*(vfs: FsBase): ScriptSharedExecState
proc newScriptSharedExecState*(vfs: FsBase, seed: uint64): ScriptSharedExecState
proc loadEntityTypeFromFile*(share: ScriptSharedExecState, entityName: string)
proc loadBoardControllerFromFile*(share: ScriptSharedExecState, controllerName: string)
proc loadWorldControllerFromFile*(share: ScriptSharedExecState)
proc loadPlayerControllerFromFile*(share: ScriptSharedExecState)

import ./nodes


proc newScriptParseState(strm: Stream, fname: string): ScriptParseState =
  ScriptParseState(
    strm: strm,
    fname: fname,
    row: 1, col: 1,
  )

proc newScriptSharedExecState(vfs: FsBase): ScriptSharedExecState =
  var t = getTime()
  ScriptSharedExecState(
    globals: initInternTable[ScriptVal](),
    entityTypes: initInternTable[ScriptExecBase](),
    boardControllers: initInternTable[ScriptExecBase](),
    vfs: vfs,
    seed: uint64(t.toUnix())*1000000000'u64 + uint64(t.nanosecond),
  )

proc newScriptSharedExecState(vfs: FsBase, seed: uint64): ScriptSharedExecState =
  ScriptSharedExecState(
    globals: initInternTable[ScriptVal](),
    entityTypes: initInternTable[ScriptExecBase](),
    boardControllers: initInternTable[ScriptExecBase](),
    vfs: vfs,
    seed: seed,
  )

proc compileRoot(node: ScriptNode, entityName: string): ScriptExecBase =
  var execBase = ScriptExecBase(
    entityNameIdx: internKey(entityName),
    globals: initInternTable[ScriptGlobalBase](),
    params: initInternTable[ScriptParamBase](),
    locals: initInternTable[ScriptLocalBase](),
    states: initInternTable[ScriptStateBase](),
    events: initInternTable[ScriptEventBase](),
    initStateIdx: -1,
  )

  if node.kind != snkRootBlock:
    raise newException(ScriptCompileError, &"EDOOFUS: compileRoot needs a root, not kind {node.kind}")

  for node in node.rootBody:
    case node.kind
    of snkGlobalDef:
      execBase.globals[node.globalDefNameIdx] = ScriptGlobalBase(
        varType: node.globalDefType,
      )

    of snkParamDef:
      execBase.params[node.paramDefNameIdx] = ScriptParamBase(
        varType: node.paramDefType,
        varDefault: node.paramDefInitValue,
      )

    of snkLocalDef:
      execBase.locals[node.localDefNameIdx] = ScriptLocalBase(
        varType: node.localDefType,
        varDefault: node.localDefInitValue,
      )

    of snkOnStateBlock:
      if execBase.initStateIdx == -1:
        execBase.initStateIdx = node.onStateNameIdx

      execBase.states[node.onStateNameIdx] = ScriptStateBase(
        stateBody: node.onStateBody,
      )

    of snkOnEventBlock:
      execBase.events[node.onEventNameIdx] = ScriptEventBase(
        eventBody: node.onEventBody,
        eventParams: node.onEventParams,
      )

    else:
      raise newException(ScriptCompileError, &"Unhandled root node kind {node.kind}")
    #raise newException(ScriptCompileError, &"TODO: Compile things")

  # Validate a few things
  if execBase.initStateIdx == -1:
    raise newException(ScriptCompileError, &"No states defined - define something using \"on state\"!")

  # TODO: Validate state names

  return execBase

proc loadEntityType(share: ScriptSharedExecState, entityName: string, strm: Stream, fname: string) =
  var sps = newScriptParseState(strm, fname)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot(entityName)

  # Preset a few things
  if not execBase.params.contains("physblock"):
    execBase.params["physblock"] = ScriptParamBase(
      varType: svkBool,
      varDefault: ScriptNode(
        kind: snkConst,
        constVal: ScriptVal(kind: svkBool, boolVal: true),
      ),
    )
  if not execBase.params.contains("physghost"):
    execBase.params["physghost"] = ScriptParamBase(
      varType: svkBool,
      varDefault: ScriptNode(
        kind: snkConst,
        constVal: ScriptVal(kind: svkBool, boolVal: false),
      ),
    )

  #echo &"exec base: {execBase}\n"
  share.entityTypes[internKey(entityName)] = execBase

proc loadEntityTypeFromFile(share: ScriptSharedExecState, entityName: string) =
  var fname = @["scripts", "entities", &"{entityName}.script"]
  var strm = share.vfs.openReadStream(fname)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    share.loadEntityType(entityName, strm, fname.join("/"))
  finally:
    strm.close()

proc loadBoardController(share: ScriptSharedExecState, controllerName: string, strm: Stream, fname: string) =
  var sps = newScriptParseState(strm, fname)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot(controllerName)
  #echo &"exec base: {execBase}\n"
  share.boardControllers[controllerName] = execBase

proc loadBoardControllerFromFile*(share: ScriptSharedExecState, controllerName: string) =
  var fname = @["scripts", "boards", &"{controllerName}.script"]
  var strm = share.vfs.openReadStream(fname)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    share.loadBoardController(controllerName, strm, fname.join("/"))
  finally:
    strm.close()

proc loadWorldController(share: ScriptSharedExecState, strm: Stream, fname: string) =
  var sps = newScriptParseState(strm, fname)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot("world")
  #echo &"exec base: {execBase}\n"
  assert execBase != nil
  share.worldController = execBase

proc loadWorldControllerFromFile*(share: ScriptSharedExecState) =
  var fname = @["scripts", "world.script"]
  var strm = share.vfs.openReadStream(fname)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    share.loadWorldController(strm, fname.join("/"))
  finally:
    strm.close()

proc loadPlayerController(share: ScriptSharedExecState, strm: Stream, fname: string) =
  var sps = newScriptParseState(strm, fname)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot("player")
  #echo &"exec base: {execBase}\n"
  assert execBase != nil
  share.playerController = execBase

proc loadPlayerControllerFromFile*(share: ScriptSharedExecState) =
  var fname = @["scripts", "player.script"]
  var strm = share.vfs.openReadStream(fname)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    share.loadPlayerController(strm, fname.join("/"))
  finally:
    strm.close()
