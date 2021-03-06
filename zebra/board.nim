import streams
import strformat
import strutils
import tables

import ./interntables
import ./types

proc addEntityToGrid*(board: Board, entity: Entity)
proc addEntityToList*(board: Board, entity: Entity)
proc broadcastEvent*(board: Board, node: ScriptNode, eventNameIdx: InternKey)
proc canAddEntityToGridPos*(board: Board, entity: Entity, x: int64, y: int64): bool
proc getBoard*(world: World, boardName: string): var Board
proc loadBoardFromFile*(world: World, boardName: string): Board
proc removeEntityFromGrid*(board: Board, entity: Entity)
proc removeEntityFromList*(board: Board, entity: Entity)
proc sendEventToPos*(board: Board, node: ScriptNode, eventNameIdx: InternKey, x: int64, y: int64, args: seq[ScriptVal] = @[])

import ./script/exec

method tick*(board: Board)

import ./entity
import ./grid
import ./script/compile
import ./script/exprs
import ./script/nodes
import ./script/tokens
import ./vfs/types as vfsTypes

proc getBoardController(share: ScriptSharedExecState, controllerName: string): ScriptExecBase =
  try:
    share.boardControllers[controllerName]
  except KeyError:
    share.loadBoardControllerFromFile(controllerName)
    share.boardControllers[controllerName]

proc getBoard(world: World, boardName: string): var Board =
  try:
    return world.boards[boardName]
  except KeyError:
    # FIXME: The lookup for this is broken and results in crashes --GM
    #raise newException(Exception, &"board \"{boardName}\" not found")
    discard world.loadBoardFromFile(boardName)
    return world.boards[boardName]

proc loadBoardInfo(strm: Stream, boardName: string, fname: string): BoardInfo =
  var boardInfo = BoardInfo(
    boardNameIdx: internKey(boardName),
    controllerNameIdx: internKey("default"),
    w: 0, h: 0,
    entityDefList: @[],
    entityDefMap: initTable[int64, BoardEntityDef](),
    layerInfoMap: initInternTable[LayerInfo](),
  )
  var hasSize = false
  var hasControllerName = false
  var sps = ScriptParseState(
    strm: strm,
    fname: fname,
    row: 1, col: 1,
    tokenPushStack: @[],
  )

  var nextLayerZorder: int64 = 0

  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEof: break # Exit condition
    of stkEol: discard
    of stkWord:
      case tok.wordVal.toLowerAscii()

      of "controller":
        if hasControllerName:
          raise tok.newScriptParseError(&"\"controller\" already defined earlier")
        boardInfo.controllerNameIdx = internKey(sps.readExpectedToken(stkWord).wordVal)
        sps.expectEolOrEof()
        hasControllerName = true

      of "entity":
        var entityId = sps.readInt()
        var entityX = sps.readInt()
        var entityY = sps.readInt()
        var entityTypeName = sps.readKeywordToken()
        var tok = sps.readToken()
        var entityBody: seq[ScriptNode] = case tok.kind
          of stkEol:
            sps.pushBackToken(tok)
            @[]
          of stkBraceOpen:
            sps.parseCodeBlock(stkBraceClosed)
          else:
            raise tok.newScriptParseError(&"Unexpected entity body token {tok}")
        sps.expectToken(stkEol)

        var entityDef = BoardEntityDef(
          id: entityId,
          typeNameIdx: internKey(entityTypeName),
          x: entityX,
          y: entityY,
          body: entityBody,
        )
        if boardInfo.entityDefMap.contains(entityDef.id):
          raise sps.newScriptParseError(&"Entity ID {entityDef.id} already allocated for this board")
        else:
          boardInfo.entityDefMap[entityDef.id] = entityDef
        boardInfo.entityDefList.add(entityDef)

      of "layer":
        var layerName = sps.readKeywordToken()
        if not hasSize:
          raise tok.newScriptParseError(&"layer {layerName} defined before board size")
        sps.expectToken(stkBraceOpen)

        var hasDefaultChar: bool = false
        var hasDefaultBgColor: bool = false
        var hasDefaultFgColor: bool = false
        var hasFixed: bool = false
        var hasOverlay: bool = false
        var hasLayerSize: bool = false
        var hasLayerOffset: bool = false
        var defaultChar: int64 = 0
        var defaultBgColor: int64 = 0
        var defaultFgColor: int64 = 0
        var solidityCheck: ScriptNode = nil
        var fixedMode: bool = false
        var overlayMode: bool = false
        var sizeWidth: int64 = boardInfo.w
        var sizeHeight: int64 = boardInfo.h
        var offsetX: int64 = 0
        var offsetY: int64 = 0

        var expectEol: bool = false
        while true:
          var tok = sps.readToken()

          # EOL-or-'}' check
          case tok.kind
          of stkEol:
            expectEol = false
            continue
          of stkBraceClosed:
            break
          else:
            if expectEol:
              raise tok.newScriptParseError(&"Expected EOL or '" & "}" & &"', got {tok} instead")

          case tok.kind
          of stkWord:
            var word = tok.wordVal.toLowerAscii()
            case word
            of "defaultchar":
              if hasDefaultChar:
                raise tok.newScriptParseError(&"\"defaultchar\" already defined earlier for layer {layerName}")
              defaultChar = sps.readInt()
              hasDefaultChar = true

            of "defaultfgcolor":
              if hasDefaultFgColor:
                raise tok.newScriptParseError(&"\"defaultfgcolor\" already defined earlier for layer {layerName}")
              defaultFgColor = sps.readInt()
              hasDefaultFgColor = true

            of "defaultbgcolor":
              if hasDefaultBgColor:
                raise tok.newScriptParseError(&"\"defaultbgcolor\" already defined earlier for layer {layerName}")
              defaultBgColor = sps.readInt()
              hasDefaultBgColor = true

            of "fixed":
              if hasFixed:
                raise tok.newScriptParseError(&"\"fixed\" already defined earlier for layer {layerName}")
              fixedMode = sps.readBool()
              hasFixed = true

            of "offset":
              if hasLayerOffset:
                raise tok.newScriptParseError(&"\"offset\" already defined earlier for layer {layerName}")
              offsetX = sps.readInt()
              offsetY = sps.readInt()
              hasLayerOffset = true

            of "overlay":
              if hasOverlay:
                raise tok.newScriptParseError(&"\"overlay\" already defined earlier for layer {layerName}")
              overlayMode = sps.readBool()
              hasOverlay = true

            of "size":
              if hasLayerSize:
                raise tok.newScriptParseError(&"\"size\" already defined earlier for layer {layerName}")
              sizeWidth = sps.readInt()
              sizeHeight = sps.readInt()
              hasLayerSize = true

            of "solid":
              if solidityCheck != nil:
                raise tok.newScriptParseError(&"\"solid\" already defined earlier for layer {layerName}")
              solidityCheck = sps.parseExpr()

            else:
              raise tok.newScriptParseError(&"Unexpected layer body token {tok}")
          else:
            raise tok.newScriptParseError(&"Unexpected layer body token {tok}")

        if solidityCheck == nil:
          raise sps.newScriptParseError(&"Layer \"{layerName}\" was not given a \"solid\" check in \"boards/{boardName}/board.info\"")

        var layerInfo = LayerInfo(
          layerNameIdx: internKey(layerName),
          solidityCheck: solidityCheck,
          zorder: nextLayerZorder,
          x: offsetX,
          y: offsetY,
          w: sizeWidth,
          h: sizeHeight,
          fixedMode: fixedMode,
          overlayMode: overlayMode,
          defaultCell: LayerCell(
            ch: uint16(defaultChar),
            fg: uint8(defaultFgColor),
            bg: uint8(defaultBgColor),
          ),
        )
        nextLayerZorder += 1
        if boardInfo.layerInfoMap.contains(layerInfo.layerNameIdx):
          raise sps.newScriptParseError(&"Layer \"{layerInfo.layerNameIdx.getInternName()}\" already allocated for this board")
        else:
          boardInfo.layerInfoMap[layerInfo.layerNameIdx] = layerInfo

      of "size":
        if hasSize:
          raise tok.newScriptParseError(&"\"size\" already defined earlier")
        boardInfo.w = sps.readExpectedToken(stkInt).intVal
        boardInfo.h = sps.readExpectedToken(stkInt).intVal
        sps.expectEolOrEof()
        hasSize = true

      else:
        raise tok.newScriptParseError(&"Expected expression, got {tok} instead")
    else:
      raise tok.newScriptParseError(&"Expected expression, got {tok} instead")

  if not hasSize:
    raise newException(BoardLoadError, &"board \"{boardName}\" was not given a size in \"boards/{boardName}/board.info\"")
  if not (boardInfo.w >= 1 and boardInfo.h >= 1):
    raise newException(BoardLoadError, &"board \"{boardName}\" has invalid size {boardInfo.w} x {boardInfo.h}")

  # Return!
  boardInfo

proc loadBoard(world: World, boardName: string, strm: Stream, fname: string): Board =
  var share = world.share
  assert share != nil

  if world.boards.contains(boardName):
    raise newException(BoardLoadError, &"board \"{boardName}\" already assigned")

  var boardInfo = loadBoardInfo(strm, boardName, fname)
  assert boardInfo != nil

  var execBase = share.getBoardController(boardInfo.controllerNameIdx.getInternName())
  assert execBase != nil
  var board = Board(
    boardNameIdx: internKey(boardName),
    world: world,
    grid: newGrid[seq[Entity]](
      w = boardInfo.w,
      h = boardInfo.h,
      default = (proc(): seq[Entity] = newSeq[Entity]())),
    entities: @[],
    layers: initInternTable[Layer](),
    execBase: execBase,
    activeStateIdx: execBase.initStateIdx,
    params: initInternTable[ScriptVal](),
    locals: initInternTable[ScriptVal](),
    alive: true,
    share: share,
    sleepTicksLeft: 0,
  )
  world.boards[boardName] = board

  # Initialise!
  for k0, v0 in execBase.params.indexedPairs():
    board.params[k0] = board.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.indexedPairs():
    board.locals[k0] = board.resolveExpr(v0.varDefault)

  # Add all layers
  # TODO: Load stuff from files --GM
  for k0, layerInfo in boardInfo.layerInfoMap.indexedPairs():
    board.layers[k0] = Layer(
      layerInfo: layerInfo,
      board: board,
      x: layerInfo.x,
      y: layerInfo.y,
      grid: newGrid[LayerCell](
        w = boardInfo.w,
        h = boardInfo.h,
        default = (proc(): LayerCell = layerInfo.defaultCell)),
    )

  # Add all entities
  var entityMap: Table[int64, Entity] = initTable[int64, Entity]()
  for entityDef in boardInfo.entityDefList:
    entityMap[entityDef.id] = board.newEntity(
      x = entityDef.x,
      y = entityDef.y,
      entityType = entityDef.typeNameIdx,
    )

  # Initialise all entities
  for entityDef in boardInfo.entityDefList:
    entityMap[entityDef.id].customiseFromBody(board, entityDef.body)

  board

proc loadBoardFromFile(world: World, boardName: string): Board =
  var share = world.share
  assert share != nil
  var fname = @["boards", boardName, "board.info"]
  var strm = share.vfs.openReadStream(fname)
  if strm == nil:
    raise newException(IOError, &"\"{fname}\" could not be opened")
  try:
    world.loadBoard(boardName, strm, fname.join("/"))
  finally:
    strm.close()

proc canAddEntityToGridPos(board: Board, entity: Entity, x: int64, y: int64): bool =
  if not (x >= 0 and x < board.grid.w and y >= 0 and y < board.grid.h):
    false
  else:
    if entity.hasPhysGhost():
      return true

    var entseq = board.grid[x, y]
    if entseq.len != 0:
      var i: int64 = entseq.len-1
      while i >= 0:
        var other = entseq[i]
        if other.hasPhysBlock():
          return false
        i -= 1

    for layerNameIdx, layer in board.layers.indexedPairs():
      var layerInfo = layer.layerInfo

      # FIXME: Solid fixed layers won't work properly right now --GM
      if layerInfo.fixedMode:
        continue

      var (lx, ly) = (x, y)
      lx -= layer.x
      ly -= layer.y
      var cell = if lx >= 0 and lx < layer.grid.w and ly >= 0 and ly < layer.grid.h:
          layer.grid[lx, ly]
        else:
          layerInfo.defaultCell

      if cell != LayerCell(ch: 0, fg: 0, bg: 0):
        if entity.resolveExpr(layerInfo.solidityCheck).asBool(layerInfo.solidityCheck):
          return false
    true

proc addEntityToGrid(board: Board, entity: Entity) =
  # May be useful for safety, but clashes with forcemove. --GM
  #assert board.canAddEntityToGridPos(entity, entity.x, entity.y)

  board.grid[entity.x, entity.y].add(entity)

proc addEntityToList(board: Board, entity: Entity) =
  if not board.entities.contains(entity):
    board.entities.add(entity)

proc removeEntityFromGrid(board: Board, entity: Entity) =
  var entseq = board.grid[entity.x, entity.y]
  var i: int64 = 0
  while i < entseq.len:
    if entseq[i] == entity:
      entseq.delete(i)
    else:
      i += 1

  board.grid[entity.x, entity.y] = entseq

proc removeEntityFromList(board: Board, entity: Entity) =
  discard # Handled in Board.tick --GM


proc broadcastEvent(board: Board, node: ScriptNode, eventNameIdx: InternKey) =
  board.tickEvent(node, eventNameIdx)
  var i: int64 = 0
  while i < board.entities.len:
    var entity = board.entities[i]
    if entity.alive:
      entity.tickEvent(node, eventNameIdx)
    i += 1

proc sendEventToPos(board: Board, node: ScriptNode, eventNameIdx: InternKey, x: int64, y: int64, args: seq[ScriptVal] = @[]) =
  if (x >= 0 and x < board.grid.w and y >= 0 and y < board.grid.h):
    var entseq = board.grid[x, y]
    if entseq.len >= 1:
      var entity = entseq[entseq.len-1]
      entity.tickEvent(node, eventNameIdx, args)

method tick(board: Board) =
  procCall tick(ScriptExecState(board))

  var i: int64 = 0
  while i < board.entities.len:
    var entity = board.entities[i]
    if (entity.board == board) and entity.alive:
      entity.tick()
      i += 1
    else:
      board.removeEntityFromGrid(entity)
      board.entities.delete(i)
