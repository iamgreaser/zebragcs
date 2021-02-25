import streams
import strformat
import tables

import ./interntables
import ./grid
import ./vfs/types

const boardVisWidth* = 60
const boardVisHeight* = 25

type
  ScriptCompileError* = object of CatchableError
  ScriptExecError* = object of CatchableError
  ScriptParseError* = object of CatchableError

  BoardLoadError* = object of CatchableError

  FullQuitException* = object of CatchableError

  ScriptParseState* = ref ScriptParseStateObj
  ScriptParseStateObj = object
    strm*: Stream
    fname*: string
    row*, col*: int64
    isParsingString*: bool
    stringInterpLevel*: int64
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
    entityNameIdx*: InternKey
    globals*: InternTable[ScriptGlobalBase]
    params*: InternTable[ScriptParamBase]
    locals*: InternTable[ScriptLocalBase]
    states*: InternTable[ScriptStateBase]
    events*: InternTable[ScriptEventBase]
    initStateIdx*: InternKey

  ScriptContinuation* = ref ScriptContinuationObj
  ScriptContinuationObj = object
    codeBlock*: seq[ScriptNode]
    codePc*: int64

  ScriptSharedExecState* = ref ScriptSharedExecStateObj
  ScriptSharedExecStateObj = object
    globals*: InternTable[ScriptVal]
    entityTypes*: InternTable[ScriptExecBase]
    boardControllers*: InternTable[ScriptExecBase]
    worldController*: ScriptExecBase
    playerController*: ScriptExecBase
    world*: World
    vfs*: FsBase
    seed*: uint64

  ScriptExecStateObj = object of RootObj
    share*: ScriptSharedExecState
    execBase*: ScriptExecBase
    activeStateIdx*: InternKey
    locals*: InternTable[ScriptVal]
    params*: InternTable[ScriptVal]
    continuations*: seq[ScriptContinuation]
    sleepTicksLeft*: int64
    alive*: bool
  ScriptExecState* = ref ScriptExecStateObj

  GameType* = enum
    gtBed, # Quits the game
    gtInitialWorldSelect, # No world loaded, but allows for world creation
    gtDemo,
    gtEditorSingle,
    gtMultiClient,
    #gtMultiDedicated,
    gtMultiServer,
    gtSingle,

  WorldObj = object of ScriptExecStateObj
    name*: string
    tickTitle*: bool
    boards*: InternTable[Board]
    players*: seq[Player]
  World* = ref WorldObj

  MenuItem* = tuple[
    eventName: string,
    text: string,
  ]
  PlayerObj = object of ScriptExecStateObj
    playerId*: uint8
    windowTitle*: string
    windowTextLines*: seq[string]
    windowMenuItems*: seq[MenuItem]
    windowCursorY*: int64
  Player* = ref PlayerObj

  BoardInfoObj = object
    boardNameIdx*: InternKey
    controllerNameIdx*: InternKey
    w*, h*: int64
    entityDefList*: seq[BoardEntityDef]
    entityDefMap*: Table[int64, BoardEntityDef]
  BoardInfo* = ref BoardInfoObj
  BoardEntityDefObj = object
    id*: int64
    x*, y*: int64
    typeNameIdx*: InternKey
    body*: seq[ScriptNode]
  BoardEntityDef* = ref BoardEntityDefObj

  BoardObj = object of ScriptExecStateObj
    world*: World
    boardNameIdx*: InternKey
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
    stkStrClosed,
    stkStrConst,
    stkStrExprClosed,
    stkStrExprOpen,
    stkStrOpen,
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
    of stkStrOpen, stkStrClosed: discard
    of stkStrExprOpen, stkStrExprClosed: discard
    of stkStrConst: strConst*: string
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
    ikEnter = "enter"

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
    sftPosof,
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
    snkSpawnInto,
    snkStringBlock,
    snkWhileBlock,
  ScriptNode* = ref ScriptNodeObj
  ScriptNodeObj = object
    case kind*: ScriptNodeKind
    of snkRootBlock:
      rootBody*: seq[ScriptNode]
    of snkOnStateBlock:
      onStateNameIdx*: InternKey
      onStateBody*: seq[ScriptNode]
    of snkOnEventBlock:
      onEventNameIdx*: InternKey
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
    of snkStringBlock:
      stringNodes*: seq[ScriptNode]
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
      broadcastEventNameIdx*: InternKey
    of snkSay:
      sayExpr*: ScriptNode
    of snkSend:
      sendEventNameIdx*: InternKey
      sendPos*: ScriptNode
    of snkSpawn, snkSpawnInto:
      spawnIntoDstExpr*: ScriptNode
      spawnEntityNameIdx*: InternKey
      spawnPos*: ScriptNode
      spawnBody*: seq[ScriptNode]
      spawnElse*: seq[ScriptNode]
    of snkGoto:
      gotoStateNameIdx*: InternKey
    of snkGlobalDef:
      globalDefType*: ScriptValKind
      globalDefNameIdx*: InternKey
    of snkGlobalVar:
      globalVarNameIdx*: InternKey
    of snkParamDef:
      paramDefType*: ScriptValKind
      paramDefNameIdx*: InternKey
      paramDefInitValue*: ScriptNode
    of snkParamVar:
      paramVarNameIdx*: InternKey
    of snkLocalDef:
      localDefType*: ScriptValKind
      localDefNameIdx*: InternKey
      localDefInitValue*: ScriptNode
    of snkLocalVar:
      localVarNameIdx*: InternKey

  ScriptValKind* = enum
    svkBool,
    svkDir,
    svkEntity,
    svkInt,
    svkPlayer,
    svkPos,
    svkStr,
  ScriptVal* = ref ScriptValObj
  ScriptValObj = object
    case kind*: ScriptValKind
    of svkBool: boolVal*: bool
    of svkDir: dirValX*, dirValY*: int64
    of svkEntity: entityRef*: Entity
    of svkInt: intVal*: int64
    of svkPlayer: playerRef*: Player
    of svkPos:
      posBoardNameIdx*: InternKey
      posValX*, posValY*: int64
    of svkStr: strVal*: string

# Forward declarations
proc `$`*(x: Entity): string
proc `$`*(x: Player): string

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
  of svkPlayer:
    if x.playerRef != nil:
      &"PlayerV({x.playerRef})"
    else:
      &"PlayerV(nil)"
  of svkPos: &"PosV({x.posBoardNameIdx.getInternName()}, {x.posValX}, {x.posValY})"
  of svkStr: &"StrV({x.strVal})"

proc `$`*(x: ScriptNode): string =
  case x.kind
  of snkAssign: return &"Assign({x.assignType}: {x.assignDstExpr} <:- {x.assignSrcExpr})"
  of snkBroadcast: return &"Broadcast({x.broadcastEventNameIdx.getInternName()})"
  of snkConst: return &"Const({x.constVal})"
  of snkDie: return &"Die"
  of snkForceMove: return &"ForceMove({x.moveDirExpr})"
  of snkFunc: return &"Func:{x.funcType}({x.funcArgs})"
  of snkGlobalDef: return &"GlobalDef(${x.globalDefNameIdx.getInternName()}: {x.globalDefType})"
  of snkGlobalVar: return &"GlobalVar(${x.globalVarNameIdx.getInternName()})"
  of snkGoto: return &"Goto({x.gotoStateNameIdx.getInternName()})"
  of snkIfBlock: return &"If({x.ifTest}, then {x.ifBody}, else {x.ifElse})"
  of snkLocalDef: return &"LocalDef(@{x.localDefNameIdx.getInternName()}: {x.localDefType} := {x.localDefInitValue})"
  of snkLocalVar: return &"LocalVar(@{x.localVarNameIdx.getInternName()})"
  of snkMove: return &"Move({x.moveDirExpr} else {x.moveElse})"
  of snkOnEventBlock: return &"OnEvent({x.onEventNameIdx.getInternName()}: {x.onEventBody})"
  of snkOnStateBlock: return &"OnState({x.onStateNameIdx.getInternName()}: {x.onStateBody})"
  of snkParamDef: return &"ParamDef(@{x.paramDefNameIdx.getInternName()}: {x.paramDefType} := {x.paramDefInitValue})"
  of snkParamVar: return &"ParamVar(@{x.paramVarNameIdx.getInternName()})"
  of snkRootBlock: return &"Root({x.rootBody})"
  of snkSay: return &"Say({x.sayExpr})"
  of snkSend: return &"Send({x.sendEventNameIdx.getInternName()} -> {x.sendPos})"
  of snkSleep: return &"Sleep({x.sleepTimeExpr})"
  of snkSpawn: return &"Spawn({x.spawnEntityNameIdx.getInternName()} -> {x.spawnPos}: {x.spawnBody} else {x.spawnElse})"
  of snkSpawnInto: return &"SpawnInto({x.spawnIntoDstExpr} := {x.spawnEntityNameIdx.getInternName()} -> {x.spawnPos}: {x.spawnBody} else {x.spawnElse})"
  of snkStringBlock: return &"String({x.stringNodes})"
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
  of stkStrClosed: return "\">T"
  of stkStrConst: return &"StringConstT({x.strConst})"
  of stkStrExprClosed: return ")\"T"
  of stkStrExprOpen: return "\"(T"
  of stkStrOpen: return "<\"T"
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
  &"SharedExecState(globals={x.globals}, vfs={x.vfs})"

proc `$`*(x: ScriptExecBase): string =
  &"ExecBase(initState={x.initStateIdx.getInternName()}, globals={x.globals}, params={x.params}, locals={x.locals}, states={x.states}, events={x.events})"

proc `$`*(x: ScriptContinuation): string =
  &"Continuation({x.codePc} in {x.codeBlock})"

proc `$`*(x: ScriptExecState): string =
  &"ExecState(activeState={x.activeStateIdx.getInternName()}, alive={x.alive})"

proc `$`*(x: Entity): string =
  &"Entity(pos=({x.x}, {x.y}), activeState={x.activeStateIdx.getInternName()}, alive={x.alive})"

proc `$`*(x: Board): string =
  &"Board(boardName={x.boardNameIdx.getInternName()}, activeState={x.activeStateIdx.getInternName()}, alive={x.alive})"

proc `$`*(x: Player): string =
  &"Player(activeState={x.activeStateIdx.getInternName()}, alive={x.alive})"

proc `$`*(x: World): string =
  &"World(activeState={x.activeStateIdx.getInternName()}, alive={x.alive})"
