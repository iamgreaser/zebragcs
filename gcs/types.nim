import streams
import strformat
import tables

const boardWidth* = 60
const boardHeight* = 25

type
  ScriptCompileError* = object of CatchableError
  ScriptExecError* = object of CatchableError
  ScriptParseError* = object of CatchableError

  Board* = ref BoardObj
  BoardObj = object
    grid*: array[0..(boardHeight-1), array[0..(boardWidth-1), seq[Entity]]]
    entities*: seq[Entity]
    share*: ScriptSharedExecState

  Entity* = ref EntityObj
  EntityObj = object
    board*: Board
    execState*: ScriptExecState
    x*, y*: int
    params*: Table[string, ScriptVal]
    alive*: bool

  ScriptParseState* = ref ScriptParseStateObj
  ScriptParseStateObj = object
    strm*: Stream
    row*, col*: int

  ScriptGlobalBase* = ref ScriptGlobalBaseObj
  ScriptParamBase* = ref ScriptParamBaseObj
  ScriptStateBase* = ref ScriptStateBaseObj
  ScriptEventBase* = ref ScriptEventBaseObj
  ScriptGlobalBaseObj = object
    varType*: ScriptValKind
  ScriptParamBaseObj = object
    varType*: ScriptValKind
    varDefault*: ScriptNode
  ScriptStateBaseObj = object
    stateBody*: seq[ScriptNode]
  ScriptEventBaseObj = object
    eventBody*: seq[ScriptNode]

  ScriptExecBase* = ref ScriptExecBaseObj
  ScriptExecBaseObj = object
    entityName*: string
    globals*: Table[string, ScriptGlobalBase]
    params*: Table[string, ScriptParamBase]
    states*: Table[string, ScriptStateBase]
    events*: Table[string, ScriptEventBase]
    initState*: string

  ScriptContinuation* = ref ScriptContinuationObj
  ScriptContinuationObj = object
    codeBlock*: seq[ScriptNode]
    codePc*: int

  ScriptSharedExecState* = ref ScriptSharedExecStateObj
  ScriptSharedExecStateObj = object
    globals*: Table[string, ScriptVal]
    entityTypes*: Table[string, ScriptExecBase]
    scriptRootDir*: string

  ScriptExecState* = ref ScriptExecStateObj
  ScriptExecStateObj = object
    share*: ScriptSharedExecState
    entity*: Entity
    execBase*: ScriptExecBase
    activeState*: string
    continuations*: seq[ScriptContinuation]
    sleepTicksLeft*: int
    alive*: bool

  ScriptTokenKind* = enum
    stkBraceClosed,
    stkBraceOpen,
    stkEof,
    stkEol,
    stkGlobalVar,
    stkInt,
    stkParamVar,
    stkParenClosed,
    stkParenOpen,
    stkWord,
  ScriptToken* = ref ScriptTokenObj
  ScriptTokenObj = object
    case kind*: ScriptTokenKind
    of stkBraceOpen, stkBraceClosed: discard
    of stkEof: discard
    of stkEol: discard
    of stkGlobalVar: globalName*: string
    of stkInt: intVal*: int
    of stkParamVar: paramName*: string
    of stkParenOpen, stkParenClosed: discard
    of stkWord: strVal*: string

  ScriptAssignType* = enum
    satDec,
    satFDiv,
    satInc,
    satMul,
    satSet,

  ScriptFuncType* = enum
    sftAt,
    sftCcw,
    sftCw,
    sftEq,
    sftGe,
    sftGt,
    sftLe,
    sftLt,
    sftNe,
    sftOpp,
    sftThispos,

  ScriptNodeKind* = enum
    snkAssign,
    snkBroadcast,
    snkConst,
    snkDie,
    snkFunc,
    snkGlobalDef,
    snkGlobalVar,
    snkGoto,
    snkMove,
    snkOnStateBlock,
    snkOnEventBlock,
    snkIfBlock,
    snkParamDef,
    snkParamVar,
    snkRootBlock,
    snkSend,
    snkSleep,
    snkSpawn,
  ScriptNode* = ref ScriptNodeObj
  ScriptNodeObj = object
    case kind*: ScriptNodeKind
    of snkRootBlock:
      rootBody*: seq[ScriptNode]
    of snkOnStateBlock:
      onStateName*: string
      onStateBody*: seq[ScriptNode]
    of snkOnEventBlock:
      onEventName*: string
      onEventBody*: seq[ScriptNode]
    of snkIfBlock:
      ifTest*: ScriptNode
      ifBody*: seq[ScriptNode]
      ifElse*: seq[ScriptNode]
    of snkConst:
      constVal*: ScriptVal
    of snkAssign:
      assignType*: ScriptAssignType
      assignDstExpr*: ScriptNode
      assignSrcExpr*: ScriptNode
    of snkFunc:
      funcType*: ScriptFuncType
      funcArgs*: seq[ScriptNode]
    of snkDie: discard
    of snkMove:
      moveDirExpr*: ScriptNode
      moveElse*: seq[ScriptNode]
    of snkSleep:
      sleepTimeExpr*: ScriptNode
    of snkBroadcast:
      broadcastEventName*: string
    of snkSend:
      sendEventName*: string
      sendPos*: ScriptNode
    of snkSpawn:
      spawnEntityName*: string
      spawnPos*: ScriptNode
      spawnBody*: seq[ScriptNode]
      spawnElse*: seq[ScriptNode]
    of snkGoto:
      gotoStateName*: string
    of snkGlobalDef:
      globalDefType*: ScriptValKind
      globalDefName*: string
    of snkGlobalVar:
      globalVarName*: string
    of snkParamDef:
      paramDefType*: ScriptValKind
      paramDefName*: string
      paramDefInitValue*: ScriptNode
    of snkParamVar:
      paramVarName*: string

  ScriptValKind* = enum
    svkBool,
    svkDir,
    svkInt,
    svkPos,
  ScriptVal* = ref ScriptValObj
  ScriptValObj = object
    case kind*: ScriptValKind
    of svkBool: boolVal*: bool
    of svkDir: dirValX*, dirValY*: int
    of svkInt: intVal*: int
    of svkPos: posValX*, posValY*: int

proc `$`*(x: ScriptVal): string =
  case x.kind
  of svkBool: &"BoolV({x.boolVal})"
  of svkDir: &"DirV({x.dirValX}, {x.dirValY})"
  of svkInt: &"IntV({x.intVal})"
  of svkPos: &"PosV({x.posValX}, {x.posValY})"

proc `$`*(x: ScriptNode): string =
  case x.kind
  of snkAssign: return &"Assign({x.assignType}: {x.assignDstExpr} <:- {x.assignSrcExpr})"
  of snkBroadcast: return &"Broadcast({x.broadcastEventName})"
  of snkConst: return &"Const({x.constVal})"
  of snkDie: return &"Die"
  of snkFunc: return &"Func:{x.funcType}({x.funcArgs})"
  of snkGlobalDef: return &"GlobalDef(${x.globalDefName}: {x.globalDefType})"
  of snkGlobalVar: return &"GlobalVar(${x.globalVarName})"
  of snkGoto: return &"Goto({x.gotoStateName})"
  of snkIfBlock: return &"If({x.ifTest}, then {x.ifBody}, else {x.ifElse})"
  of snkMove: return &"Move({x.moveDirExpr})"
  of snkOnEventBlock: return &"OnEvent({x.onEventName}: {x.onEventBody})"
  of snkOnStateBlock: return &"OnState({x.onStateName}: {x.onStateBody})"
  of snkParamDef: return &"ParamDef(@{x.paramDefName}: {x.paramDefType} := {x.paramDefInitValue})"
  of snkParamVar: return &"ParamVar(@{x.paramVarName})"
  of snkRootBlock: return &"Root({x.rootBody})"
  of snkSend: return &"Send({x.sendEventName} -> {x.sendPos})"
  of snkSleep: return &"Sleep({x.sleepTimeExpr})"
  of snkSpawn: return &"Spawn({x.spawnEntityName} -> {x.spawnPos}: {x.spawnBody} else {x.spawnElse})"

proc `$`*(x: ScriptToken): string =
  case x.kind
  of stkBraceClosed: return "}T"
  of stkBraceOpen: return "{T"
  of stkEof: return "EofT"
  of stkEol: return "EolT"
  of stkGlobalVar: return &"GlobalT({x.globalName})"
  of stkInt: return &"IntT({x.intVal})"
  of stkParamVar: return &"ParamT({x.paramName})"
  of stkParenClosed: return ")T"
  of stkParenOpen: return "(T"
  of stkWord: return &"WordT({x.strVal})"

proc `$`*(x: ScriptGlobalBase): string =
  &"Global({x.varType})"
proc `$`*(x: ScriptParamBase): string =
  &"Param({x.varType} := {x.varDefault})"
proc `$`*(x: ScriptStateBase): string =
  &"State({x.stateBody})"
proc `$`*(x: ScriptEventBase): string =
  &"Event({x.eventBody})"

proc `$`*(x: ScriptSharedExecState): string =
  &"SharedExecState(globals={x.globals})"

proc `$`*(x: ScriptExecBase): string =
  &"ExecBase(initState={x.initState}, globals={x.globals}, params={x.params}, states={x.states}, events={x.events})"

proc `$`*(x: ScriptContinuation): string =
  &"Continuation({x.codePc} in {x.codeBlock})"

proc `$`*(x: ScriptExecState): string =
  #&"ExecState(execBase={x.execBase}, activeState={x.activeState}, continuations={x.continuations})"
  #&"ExecState(activeState={x.activeState}, continuations={x.continuations})"
  &"ExecState(activeState={x.activeState}, alive={x.alive})"

proc `$`*(x: Entity): string =
  &"Entity(pos=({x.x}, {x.y}), execState={x.execState}, params={x.params}, alive={x.alive})"

proc `$`*(x: Board): string =
  &"Board(entities={x.entities}, share={x.share})"
