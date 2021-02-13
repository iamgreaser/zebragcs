import streams
import strformat
import tables

import types

proc newScriptParseState*(strm: Stream): ScriptParseState
proc newScriptSharedExecState*(): ScriptSharedExecState
proc loadEntityTypeFromFile*(share: ScriptSharedExecState, entityName: string, fname: string)

import scriptnodes


proc newScriptParseState(strm: Stream): ScriptParseState =
  ScriptParseState(
    strm: strm,
    row: 1, col: 1,
  )

proc newScriptSharedExecState(): ScriptSharedExecState =
  ScriptSharedExecState(
    globals: initTable[string, ScriptVal](),
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

proc loadEntityTypeFromFile(share: ScriptSharedExecState, entityName: string, fname: string) =
  var strm = newFileStream(fname, fmRead)
  try:
    share.loadEntityType(entityName, strm)
  finally:
    strm.close()
