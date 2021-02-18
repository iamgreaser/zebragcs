import streams
import strformat
import strutils
import tables
import times

import ../types

proc newScriptParseState*(strm: Stream): ScriptParseState
proc newScriptSharedExecState*(rootDir: string): ScriptSharedExecState
proc loadEntityTypeFromFile*(share: ScriptSharedExecState, entityName: string)
proc loadBoardControllerFromFile*(share: ScriptSharedExecState, controllerName: string)
proc loadWorldControllerFromFile*(share: ScriptSharedExecState)

import ./nodes


proc newScriptParseState(strm: Stream): ScriptParseState =
  ScriptParseState(
    strm: strm,
    row: 1, col: 1,
  )

proc newScriptSharedExecState(rootDir: string): ScriptSharedExecState =
  var t = getTime()
  ScriptSharedExecState(
    globals: initTable[string, ScriptVal](),
    rootDir: (rootDir & "/").replace("//", "/"),
    seed: uint64(t.toUnix())*1000000000'u64 + uint64(t.nanosecond),
  )

proc compileRoot(node: ScriptNode, entityName: string): ScriptExecBase =
  var execBase = ScriptExecBase(
    entityName: entityName,
    globals: initTable[string, ScriptGlobalBase](),
    params: initTable[string, ScriptParamBase](),
    states: initTable[string, ScriptStateBase](),
    events: initTable[string, ScriptEventBase](),
  )

  if node.kind != snkRootBlock:
    raise newException(ScriptCompileError, &"EDOOFUS: compileRoot needs a root, not kind {node.kind}")

  for node in node.rootBody:
    case node.kind
    of snkGlobalDef:
      execBase.globals[node.globalDefName] = ScriptGlobalBase(
        varType: node.globalDefType,
      )

    of snkParamDef:
      execBase.params[node.paramDefName] = ScriptParamBase(
        varType: node.paramDefType,
        varDefault: node.paramDefInitValue,
      )

    of snkLocalDef:
      execBase.locals[node.localDefName] = ScriptLocalBase(
        varType: node.localDefType,
        varDefault: node.localDefInitValue,
      )

    of snkOnStateBlock:
      if execBase.initState == "":
        execBase.initState = node.onStateName

      execBase.states[node.onStateName] = ScriptStateBase(
        stateBody: node.onStateBody,
      )

    of snkOnEventBlock:
      execBase.events[node.onEventName] = ScriptEventBase(
        eventBody: node.onEventBody,
      )

    else:
      raise newException(ScriptCompileError, &"Unhandled root node kind {node.kind}")
    #raise newException(ScriptCompileError, &"TODO: Compile things")

  # Validate a few things
  if execBase.initState == "":
    raise newException(ScriptCompileError, &"No states defined - define something using \"on state\"!")

  # TODO: Validate state names

  return execBase

proc loadEntityType(share: ScriptSharedExecState, entityName: string, strm: Stream) =
  var sps = newScriptParseState(strm)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot(entityName)
  #echo &"exec base: {execBase}\n"
  share.entityTypes[entityName] = execBase

proc loadEntityTypeFromFile(share: ScriptSharedExecState, entityName: string) =
  var fname = (&"{share.rootDir}/scripts/entities/{entityName}.script").replace("//", "/")
  var strm = newFileStream(fname, fmRead)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    share.loadEntityType(entityName, strm)
  finally:
    strm.close()

proc loadBoardController(share: ScriptSharedExecState, controllerName: string, strm: Stream) =
  var sps = newScriptParseState(strm)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot(controllerName)
  #echo &"exec base: {execBase}\n"
  share.boardControllers[controllerName] = execBase

proc loadBoardControllerFromFile*(share: ScriptSharedExecState, controllerName: string) =
  var fname = (&"{share.rootDir}/scripts/boards/{controllerName}.script").replace("//", "/")
  var strm = newFileStream(fname, fmRead)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    share.loadBoardController(controllerName, strm)
  finally:
    strm.close()

proc loadWorldController(share: ScriptSharedExecState, strm: Stream) =
  var sps = newScriptParseState(strm)
  var node = sps.parseRoot(stkEof)
  #echo &"node: {node}\n"
  var execBase = node.compileRoot("world")
  #echo &"exec base: {execBase}\n"
  assert execBase != nil
  share.worldController = execBase

proc loadWorldControllerFromFile*(share: ScriptSharedExecState) =
  var fname = (&"{share.rootDir}/scripts/world.script").replace("//", "/")
  var strm = newFileStream(fname, fmRead)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    share.loadWorldController(strm)
  finally:
    strm.close()
