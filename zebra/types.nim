import streams
import strformat
import tables

type
  ScriptCompileError* = object of CatchableError
  ScriptExecError* = object of CatchableError
  ScriptParseError* = object of CatchableError

  BoardLoadError* = object of CatchableError

  GridObj[T] = object
    w*, h*: int64
    body*: seq[T]
  Grid*[T] = ref GridObj[T]

  ScriptParseState* = ref ScriptParseStateObj
  ScriptParseStateObj = object
    strm*: Stream
    fname*: string
    row*, col*: int64
    tokenPushStack*: seq[ScriptToken]

  ScriptGlobalBase* = ref ScriptGlobalBaseObj
  ScriptParamBase* = ref ScriptParamBaseObj
  ScriptLocalBase* = ref ScriptLocalBaseObj
  ScriptStateBase* = ref ScriptStateBaseObj
  ScriptEventBase* = ref ScriptEventBaseObj
  ScriptGlobalBaseObj = object
    varType*: ScriptValKind
  ScriptParamBaseObj = object
    varType*: ScriptValKind
    varDefault*: ScriptNode
  ScriptLocalBaseObj = object
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
    locals*: Table[string, ScriptLocalBase]
    states*: Table[string, ScriptStateBase]
    events*: Table[string, ScriptEventBase]
    initState*: string

  ScriptContinuation* = ref ScriptContinuationObj
  ScriptContinuationObj = object
    codeBlock*: seq[ScriptNode]
    codePc*: int64

  ScriptSharedExecState* = ref ScriptSharedExecStateObj
  ScriptSharedExecStateObj = object
    globals*: Table[string, ScriptVal]
    entityTypes*: Table[string, ScriptExecBase]
    boardControllers*: Table[string, ScriptExecBase]
    worldController*: ScriptExecBase
    world*: World
    rootDir*: string
    seed*: uint64

  ScriptExecStateObj = object of RootObj
    share*: ScriptSharedExecState
    execBase*: ScriptExecBase
    activeState*: string
    locals*: Table[string, ScriptVal]
    params*: Table[string, ScriptVal]
    continuations*: seq[ScriptContinuation]
    sleepTicksLeft*: int64
    alive*: bool
  ScriptExecState* = ref ScriptExecStateObj

  WorldObj = object of ScriptExecStateObj
    boards*: Table[string, Board]
    players*: seq[Player]
  World* = ref WorldObj

  PlayerObj = object
    entity*: Entity
  Player* = ref PlayerObj

  BoardInfoObj = object
    boardName*: string
    controllerName*: string
    w*, h*: int64
  BoardInfo* = ref BoardInfoObj

  BoardObj = object of ScriptExecStateObj
    world*: World
    boardName*: string
    grid*: Grid[seq[Entity]]
    entities*: seq[Entity]
  Board* = ref BoardObj

  EntityObj = object of ScriptExecStateObj
    board*: Board
    x*, y*: int64
  Entity* = ref EntityObj

  ScriptTokenKind* = enum
    stkBraceClosed,
    stkBraceOpen,
    stkEof,
    stkEol,
    stkGlobalVar,
    stkInt,
    stkLocalVar,
    stkParamVar,
    stkParenClosed,
    stkParenOpen,
    stkString,
    stkWord,
  ScriptToken* = ref ScriptTokenObj
  ScriptTokenObj = object
    case kind*: ScriptTokenKind
    of stkBraceOpen, stkBraceClosed: discard
    of stkEof: discard
    of stkEol: discard
    of stkGlobalVar: globalName*: string
    of stkInt: intVal*: int64
    of stkLocalVar: localName*: string
    of stkParamVar: paramName*: string
    of stkParenOpen, stkParenClosed: discard
    of stkString: strVal*: string
    of stkWord: wordVal*: string

  InputKeyType* = enum
    ikNone = ""
    ikUp = "up"
    ikDown = "down"
    ikLeft = "left"
    ikRight = "right"
    ikShift = "shift"
    ikCtrl = "ctrl"
    ikEsc = "esc"

    ik0 = "0",
    ik1 = "1",
    ik2 = "2",
    ik3 = "3",
    ik4 = "4",
    ik5 = "5",
    ik6 = "6",
    ik7 = "7",
    ik8 = "8",
    ik9 = "9",

    ikA = "a",
    ikB = "b",
    ikC = "c",
    ikD = "d",
    ikE = "e",
    ikF = "f",
    ikG = "g",
    ikH = "h",
    ikI = "i",
    ikJ = "j",
    ikK = "k",
    ikL = "l",
    ikM = "m",
    ikN = "n",
    ikO = "o",
    ikP = "p",
    ikQ = "q",
    ikR = "r",
    ikS = "s",
    ikT = "t",
    ikU = "u",
    ikV = "v",
    ikW = "w",
    ikX = "x",
    ikY = "y",
    ikZ = "z",


  InputEventType* = enum
    ievKeyPress
    ievKeyRelease
    ievNone
    ievQuit
  InputEvent* = ref InputEventObj
  InputEventObj = object
    case kind*: InputEventType
      of ievKeyPress, ievKeyRelease:
        keyType*: InputKeyType
      of ievNone: discard
      of ievQuit: discard

  ScriptAssignType* = enum
    satDec,
    satFDiv,
    satInc,
    satMul,
    satSet,

  ScriptFuncType* = enum
    sftAt,
    sftAtBoard,
    sftCcw,
    sftCw,
    sftDirX,
    sftDirY,
    sftEq,
    sftGe,
    sftGt,
    sftLe,
    sftLt,
    sftNe,
    sftNot,
    sftOpp,
    sftRandom,
    sftRandomDir,
    sftSeek,
    sftSelf,
    sftThispos,

  ScriptNodeKind* = enum
    snkAssign,
    snkBroadcast,
    snkConst,
    snkDie,
    snkForceMove,
    snkFunc,
    snkGlobalDef,
    snkGlobalVar,
    snkGoto,
    snkIfBlock,
    snkLocalDef,
    snkLocalVar,
    snkMove,
    snkOnStateBlock,
    snkOnEventBlock,
    snkParamDef,
    snkParamVar,
    snkRootBlock,
    snkSay,
    snkSend,
    snkSleep,
    snkSpawn,
    snkWhileBlock,
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
    of snkWhileBlock:
      whileTest*: ScriptNode
      whileBody*: seq[ScriptNode]
    of snkConst:
      constVal*: ScriptVal
    of snkAssign:
      assignType*: ScriptAssignType
      assignDstExpr*: ScriptNode
      assignSrcExpr*: ScriptNode
    of snkForceMove:
      forceMoveDirExpr*: ScriptNode
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
    of snkSay:
      sayExpr*: ScriptNode
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
    of snkLocalDef:
      localDefType*: ScriptValKind
      localDefName*: string
      localDefInitValue*: ScriptNode
    of snkLocalVar:
      localVarName*: string

  ScriptValKind* = enum
    svkBool,
    svkDir,
    svkEntity,
    svkInt,
    svkPos,
    svkStr,
  ScriptVal* = ref ScriptValObj
  ScriptValObj = object
    case kind*: ScriptValKind
    of svkBool: boolVal*: bool
    of svkDir: dirValX*, dirValY*: int64
    of svkEntity: entityRef*: Entity
    of svkInt: intVal*: int64
    of svkPos:
      posBoardName*: string
      posValX*, posValY*: int64
    of svkStr: strVal*: string

# Forward declarations
proc `$`*(x: Entity): string

proc `$`*(x: ScriptVal): string =
  case x.kind
  of svkBool: &"BoolV({x.boolVal})"
  of svkDir: &"DirV({x.dirValX}, {x.dirValY})"
  of svkEntity:
    if x.entityRef != nil:
      &"EntityV({x.entityRef})"
    else:
      &"EntityV(nil)"
  of svkInt: &"IntV({x.intVal})"
  of svkPos: &"PosV({x.posBoardName}, {x.posValX}, {x.posValY})"
  of svkStr: &"StrV({x.strVal})"

proc `$`*(x: ScriptNode): string =
  case x.kind
  of snkAssign: return &"Assign({x.assignType}: {x.assignDstExpr} <:- {x.assignSrcExpr})"
  of snkBroadcast: return &"Broadcast({x.broadcastEventName})"
  of snkConst: return &"Const({x.constVal})"
  of snkDie: return &"Die"
  of snkForceMove: return &"ForceMove({x.moveDirExpr})"
  of snkFunc: return &"Func:{x.funcType}({x.funcArgs})"
  of snkGlobalDef: return &"GlobalDef(${x.globalDefName}: {x.globalDefType})"
  of snkGlobalVar: return &"GlobalVar(${x.globalVarName})"
  of snkGoto: return &"Goto({x.gotoStateName})"
  of snkIfBlock: return &"If({x.ifTest}, then {x.ifBody}, else {x.ifElse})"
  of snkLocalDef: return &"LocalDef(@{x.localDefName}: {x.localDefType} := {x.localDefInitValue})"
  of snkLocalVar: return &"LocalVar(@{x.localVarName})"
  of snkMove: return &"Move({x.moveDirExpr} else {x.moveElse})"
  of snkOnEventBlock: return &"OnEvent({x.onEventName}: {x.onEventBody})"
  of snkOnStateBlock: return &"OnState({x.onStateName}: {x.onStateBody})"
  of snkParamDef: return &"ParamDef(@{x.paramDefName}: {x.paramDefType} := {x.paramDefInitValue})"
  of snkParamVar: return &"ParamVar(@{x.paramVarName})"
  of snkRootBlock: return &"Root({x.rootBody})"
  of snkSay: return &"Say({x.sayExpr})"
  of snkSend: return &"Send({x.sendEventName} -> {x.sendPos})"
  of snkSleep: return &"Sleep({x.sleepTimeExpr})"
  of snkSpawn: return &"Spawn({x.spawnEntityName} -> {x.spawnPos}: {x.spawnBody} else {x.spawnElse})"
  of snkWhileBlock: return &"While({x.whileTest}: {x.whileBody})"

proc `$`*(x: ScriptToken): string =
  case x.kind
  of stkBraceClosed: return "}T"
  of stkBraceOpen: return "{T"
  of stkEof: return "EofT"
  of stkEol: return "EolT"
  of stkGlobalVar: return &"GlobalT({x.globalName})"
  of stkInt: return &"IntT({x.intVal})"
  of stkLocalVar: return &"LocalT({x.localName})"
  of stkParamVar: return &"ParamT({x.paramName})"
  of stkParenClosed: return ")T"
  of stkParenOpen: return "(T"
  of stkString: return &"StringT({x.strVal})"
  of stkWord: return &"WordT({x.wordVal})"

proc `$`*(x: ScriptGlobalBase): string =
  &"Global({x.varType})"
proc `$`*(x: ScriptParamBase): string =
  &"Param({x.varType} := {x.varDefault})"
proc `$`*(x: ScriptLocalBase): string =
  &"Local({x.varType} := {x.varDefault})"
proc `$`*(x: ScriptStateBase): string =
  &"State({x.stateBody})"
proc `$`*(x: ScriptEventBase): string =
  &"Event({x.eventBody})"

proc `$`*(x: ScriptSharedExecState): string =
  &"SharedExecState(globals={x.globals}, rootDir={x.rootDir})"

proc `$`*(x: ScriptExecBase): string =
  &"ExecBase(initState={x.initState}, globals={x.globals}, params={x.params}, locals={x.locals}, states={x.states}, events={x.events})"

proc `$`*(x: ScriptContinuation): string =
  &"Continuation({x.codePc} in {x.codeBlock})"

proc `$`*(x: ScriptExecState): string =
  #&"ExecState(execBase={x.execBase}, activeState={x.activeState}, continuations={x.continuations})"
  #&"ExecState(activeState={x.activeState}, continuations={x.continuations})"
  &"ExecState(activeState={x.activeState}, params={x.params}, locals={x.locals}, alive={x.alive})"

proc `$`*(x: Entity): string =
  &"Entity(pos=({x.x}, {x.y}), activeState={x.activeState}, params={x.params}, locals={x.locals}, alive={x.alive})"

proc `$`*(x: Board): string =
  &"Board(entities={x.entities}, share={x.share}, activeState={x.activeState}, params={x.params}, locals={x.locals}, alive={x.alive})"

proc `$`*(x: Player): string =
  &"Player(entity={x.entity})"
