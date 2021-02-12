import streams
import tables


type
  ScriptCompileError* = object of CatchableError
  ScriptExecError* = object of CatchableError
  ScriptParseError* = object of CatchableError

  Board = ref BoardObj
  BoardObj = object
    grid*: array[0..24, array[0..59, seq[Entity]]]
    entities*: seq[Entity]
    share*: ScriptSharedExecState

  Entity = ref EntityObj
  EntityObj = object
    board*: Board
    execState*: ScriptExecState
    x*, y*: int
    params*: Table[string, ScriptVal]
    alive*: bool

  ScriptParseState = ref ScriptParseStateObj
  ScriptParseStateObj = object
    strm*: Stream
    row*, col*: int

  ScriptGlobalBase = ref ScriptGlobalBaseObj
  ScriptParamBase = ref ScriptParamBaseObj
  ScriptStateBase = ref ScriptStateBaseObj
  ScriptEventBase = ref ScriptEventBaseObj
  ScriptGlobalBaseObj = object
    varType*: ScriptValKind
  ScriptParamBaseObj = object
    varType*: ScriptValKind
    varDefault*: ScriptNode
  ScriptStateBaseObj = object
    stateBody*: seq[ScriptNode]
  ScriptEventBaseObj = object
    eventBody*: seq[ScriptNode]

  ScriptExecBase = ref ScriptExecBaseObj
  ScriptExecBaseObj = object
    globals*: Table[string, ScriptGlobalBase]
    params*: Table[string, ScriptParamBase]
    states*: Table[string, ScriptStateBase]
    events*: Table[string, ScriptEventBase]
    initState*: string

  ScriptContinuation = ref ScriptContinuationObj
  ScriptContinuationObj = object
    codeBlock*: seq[ScriptNode]
    codePc*: int

  ScriptSharedExecState = ref ScriptSharedExecStateObj
  ScriptSharedExecStateObj = object
    globals*: Table[string, ScriptVal]
    entityTypes*: Table[string, ScriptExecBase]

  ScriptExecState = ref ScriptExecStateObj
  ScriptExecStateObj = object
    share*: ScriptSharedExecState
    entity*: Entity
    execBase*: ScriptExecBase
    activeState*: string
    continuations*: seq[ScriptContinuation]
    sleepTicksLeft*: int
    alive*: bool

  ScriptTokenKind = enum
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
  ScriptToken = ref ScriptTokenObj
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

  ScriptAssignType = enum
    satDec,
    satFDiv,
    satInc,
    satMul,
    satSet,

  ScriptFuncType = enum
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

  ScriptNodeKind = enum
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
  ScriptNode = ref ScriptNodeObj
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

  ScriptValKind = enum
    svkBool,
    svkDir,
    svkInt,
    svkPos,
  ScriptVal = ref ScriptValObj
  ScriptValObj = object
    case kind*: ScriptValKind
    of svkBool: boolVal*: bool
    of svkDir: dirValX*, dirValY*: int
    of svkInt: intVal*: int
    of svkPos: posValX*, posValY*: int


export ScriptCompileError
export ScriptExecError
export ScriptParseError

export ScriptAssignType
export ScriptContinuation
export ScriptSharedExecState
export ScriptExecBase
export ScriptExecState
export ScriptFuncType
export ScriptNode
export ScriptNodeKind
export ScriptParseState
export ScriptToken
export ScriptTokenKind
export ScriptVal
export ScriptValKind

export ScriptGlobalBase
export ScriptParamBase
export ScriptStateBase
export ScriptEventBase

export Board
export Entity

