import strformat
import strutils

import ../interntables
import ../types

proc parseCodeBlock*(sps: ScriptParseState, endKind: ScriptTokenKind): seq[ScriptNode]
proc parseExpr*(sps: ScriptParseState): ScriptNode
proc parseRoot*(sps: ScriptParseState, endKind: ScriptTokenKind): ScriptNode

import ./tokens


proc tagPos(sps: ScriptParseState, node: ScriptNode): ScriptNode =
  node.fname = sps.fname
  node.row = sps.row
  node.col = sps.col
  node
proc tagPos(tok: ScriptToken, node: ScriptNode): ScriptNode =
  node.fname = tok.fname
  node.row = tok.row
  node.col = tok.col
  node


proc parseExpr(sps: ScriptParseState): ScriptNode =
  var tok = sps.readToken()
  case tok.kind
    of stkInt: return tok.tagPos(ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkInt, intVal: tok.intVal)))
    of stkGlobalVar: return tok.tagPos(ScriptNode(kind: snkGlobalVar, globalVarNameIdx: internKey(tok.globalName)))
    of stkParamVar: return tok.tagPos(ScriptNode(kind: snkParamVar, paramVarNameIdx: internKey(tok.paramName)))
    of stkLocalVar: return tok.tagPos(ScriptNode(kind: snkLocalVar, localVarNameIdx: internKey(tok.localName)))

    of stkStrOpen:
      var accum: seq[ScriptNode] = @[]
      var outerTok = tok
      while true:
        var tok = sps.readToken()
        case tok.kind
        of stkStrClosed:
          #echo &"Nodes: {accum}"
          return outerTok.tagPos(ScriptNode(kind: snkStringBlock, stringNodes: accum))
        of stkStrConst:
          accum.add(tok.tagPos(ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkStr, strVal: tok.strConst))))
        of stkStrExprOpen:
          var subNode = sps.parseExpr()
          sps.expectToken(stkStrExprClosed)
          accum.add(subNode)
        else:
          raise tok.newScriptParseError(&"Expected string expression, got {tok} instead")

    of stkSquareOpen:
      var kw = sps.readKeywordToken()
      var funcType = internKey(kw)
      var funcArgs: seq[ScriptNode] = internCase (case funcType
        of "atboard": @[
          tok.tagPos(ScriptNode(kind: snkConst, constVal: ScriptVal(
            kind: svkStr, strVal: sps.readKeywordToken().toLowerAscii(),
          ))),
        ]
        of "haslayer": @[
          tok.tagPos(ScriptNode(kind: snkConst, constVal: ScriptVal(
            kind: svkStr, strVal: sps.readKeywordToken().toLowerAscii(),
          ))),
        ]
        of "layer": @[
          tok.tagPos(ScriptNode(kind: snkConst, constVal: ScriptVal(
            kind: svkStr, strVal: sps.readKeywordToken().toLowerAscii(),
          ))),
        ]
        of "list": @[
          tok.tagPos(ScriptNode(kind: snkConst, constVal: ScriptVal(
            kind: svkType, typeVal: sps.readVarType(),
          ))),
        ]
        else: @[])

      while true:
        var tok = sps.readToken()
        case tok.kind:
          of stkSquareClosed: break
          of stkEol: discard
          else:
            sps.pushBackToken(tok)
            var arg = sps.parseExpr()
            funcArgs.add(arg)

      return tok.tagPos(ScriptNode(kind: snkFunc, funcType: funcType, funcArgs: funcArgs))

    of stkWord:
      var funcType = internKey(tok.wordVal.toLowerAscii())
      var node = internCase (case funcType
        of "false": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: false))
        of "true": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: true))

        of "noentity": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkEntity, entityRef: nil))
        of "noplayer": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkPlayer, playerRef: nil))
        of "notype": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkType, typeVal: nil))

        of "i", "idle": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: 0))
        of "n", "north": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: -1))
        of "s", "south": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: +1))
        of "w", "west": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: -1, dirValY: 0))
        of "e", "east": ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: +1, dirValY: 0))

        # Implement some of these as argless functions for now
        of "randomdir": ScriptNode(kind: snkFunc, funcType: funcType, funcArgs: @[])
        of "self": ScriptNode(kind: snkFunc, funcType: funcType, funcArgs: @[])
        of "thispos": ScriptNode(kind: snkFunc, funcType: funcType, funcArgs: @[])

        else:
          raise tok.newScriptParseError(&"Expected expression, got {tok} instead"))
      return tok.tagPos(node)
    else:
      raise tok.newScriptParseError(&"Expected expression, got {tok} instead")


proc parseEolOrElse(sps: ScriptParseState): seq[ScriptNode] =
  var tok = sps.readToken()
  case tok.kind
  of stkEol: return @[]
  of stkWord:
    case tok.wordVal.toLowerAscii()
    of "else":
      sps.expectToken(stkBraceOpen)
      return sps.parseCodeBlock(stkBraceClosed)
    else:
      raise tok.newScriptParseError(&"Expected EOL or \"else\" keyword, got {tok} instead")
  of stkBraceClosed:
    sps.pushBackToken(tok)
    return @[]
  else:
    raise tok.newScriptParseError(&"Expected EOL or \"else\" keyword, got {tok} instead")

proc parseOnBlock(sps: ScriptParseState): ScriptNode =
  var typeName = sps.readKeywordToken()
  case typeName

  of "event":
    var eventName = sps.readKeywordToken()
    var eventParams: seq[ScriptNode] = @[]
    while true:
      var tok = sps.readToken()
      case tok.kind
        of stkBraceOpen: break # Terminate and consume
        of stkLocalVar:
          eventParams.add(tok.tagPos(ScriptNode(kind: snkLocalVar, localVarNameIdx: internKey(tok.localName))))
        else:
          raise tok.newScriptParseError(&"Expected varname or '" & "{" & &"', got {tok} instead")
    return sps.tagPos(ScriptNode(
      kind: snkOnEventBlock,
      onEventNameIdx: internKey(eventName),
      onEventParams: eventParams,
      onEventBody: sps.parseCodeBlock(stkBraceClosed),
    ))

  of "state":
    var stateName = sps.readKeywordToken()
    sps.expectToken(stkBraceOpen)
    return sps.tagPos(ScriptNode(
      kind: snkOnStateBlock,
      onStateNameIdx: internKey(stateName),
      onStateBody: sps.parseCodeBlock(stkBraceClosed),
    ))

  else:
    raise sps.newScriptParseError(&"Unexpected keyword \"{typeName}\" after \"on\" keyword")

proc parseCodeBlock(sps: ScriptParseState, endKind: ScriptTokenKind): seq[ScriptNode] =
  var nodes: seq[ScriptNode] = @[]
  var awaitingEol: bool = false
  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEol:
      awaitingEol = false
    of stkWord:
      if awaitingEol:
        raise tok.newScriptParseError(&"Expected EOL, got {tok} instead")

      case tok.wordVal.toLowerAscii()

      of "goto":
        var stateName = sps.readKeywordToken()
        awaitingEol = true
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkGoto,
          gotoStateNameIdx: internKey(stateName),
        )))

      of "broadcast":
        var eventName = sps.readKeywordToken()
        awaitingEol = true
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkBroadcast,
          broadcastEventNameIdx: internKey(eventName),
        )))

      of "dec", "fdiv", "inc", "mul", "set":
        var assignType = case tok.wordVal.toLowerAscii()
        of "dec": satDec
        of "fdiv": satFDiv
        of "inc": satInc
        of "mul": satMul
        of "set": satSet
        else:
          # SHOULD NOT REACH HERE!
          raise tok.newScriptParseError(&"EDOOFUS: ScriptAssignType unknown for {tok}!")

        var dstExpr = sps.parseExpr()
        var srcExpr = sps.parseExpr()
        awaitingEol = true
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkAssign,
          assignType: assignType,
          assignDstExpr: dstExpr,
          assignSrcExpr: srcExpr,
        )))

      of "die":
        awaitingEol = true
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkDie,
        )))

      of "forcemove":
        var dirExpr = sps.parseExpr()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkForceMove,
          forceMoveDirExpr: dirExpr,
        )))

      of "if":
        var ifTest = sps.parseExpr()
        sps.expectToken(stkBraceOpen)
        var ifBody = sps.parseCodeBlock(stkBraceClosed)
        var ifElse = sps.parseEolOrElse()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkIfBlock,
          ifTest: ifTest,
          ifBody: ifBody,
          ifElse: ifElse,
        )))

      of "lappend":
        var listDst = sps.parseExpr()
        var listVal = sps.parseExpr()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkListAppend,
          listAppendDst: listDst,
          listAppendVal: listVal,
        )))
        awaitingEol = true

      of "lprintleft":
        var layerNameIdx = internKey(sps.readKeywordToken())
        var x = sps.parseExpr()
        var y = sps.parseExpr()
        var fg = sps.parseExpr()
        var bg = sps.parseExpr()
        var s = sps.parseExpr()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkLayerPrintLeft,
          layerPrintNameIdx: layerNameIdx,
          layerPrintX: x,
          layerPrintY: y,
          layerPrintFg: fg,
          layerPrintBg: bg,
          layerPrintStr: s,
        )))

      of "lprintright":
        var layerNameIdx = internKey(sps.readKeywordToken())
        var x = sps.parseExpr()
        var y = sps.parseExpr()
        var fg = sps.parseExpr()
        var bg = sps.parseExpr()
        var s = sps.parseExpr()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkLayerPrintRight,
          layerPrintNameIdx: layerNameIdx,
          layerPrintX: x,
          layerPrintY: y,
          layerPrintFg: fg,
          layerPrintBg: bg,
          layerPrintStr: s,
        )))

      of "lrectfill":
        var layerNameIdx = internKey(sps.readKeywordToken())
        var x = sps.parseExpr()
        var y = sps.parseExpr()
        var w = sps.parseExpr()
        var h = sps.parseExpr()
        var cell = sps.parseExpr()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkLayerRectFill,
          layerRectNameIdx: layerNameIdx,
          layerRectX: x,
          layerRectY: y,
          layerRectWidth: w,
          layerRectHeight: h,
          layerRectCell: cell,
        )))

      of "move":
        var dirExpr = sps.parseExpr()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkMove,
          moveDirExpr: dirExpr,
          moveElse: sps.parseEolOrElse(),
        )))

      of "say":
        var sayExpr = sps.parseExpr()
        awaitingEol = true
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkSay,
          sayExpr: sayExpr,
        )))

      of "send":
        var posExpr = sps.parseExpr()
        var eventNameIdx = internKey(sps.readKeywordToken())
        var sendArgs: seq[ScriptNode] = @[]
        while true:
          var tok = sps.readToken()
          case tok.kind
          of stkEol: break # Terminate and consume
          else:
            if tok.kind == endKind:
              # Terminate and push back
              sps.pushBackToken(tok)
              break
            else:
              sps.pushBackToken(tok)
              sendArgs.add(sps.parseExpr())

        nodes.add(sps.tagPos(ScriptNode(
          kind: snkSend,
          sendPos: posExpr,
          sendEventNameIdx: eventNameIdx,
          sendArgs: sendArgs,
        )))

      of "sleep":
        var timeExpr = sps.parseExpr()
        awaitingEol = true
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkSleep,
          sleepTimeExpr: timeExpr,
        )))

      of "spawn", "spawninto":
        var dstExpr = case tok.wordVal.toLowerAscii()
          of "spawninto": sps.parseExpr()
          of "spawn": nil
          else:
            raise tok.newScriptParseError(&"EDOOFUS: Unhandled spawn type {tok}!")

        var posExpr = sps.parseExpr()
        var entityName = sps.readKeywordToken().toLowerAscii()
        var entityNameIdx = internKey(entityName)
        # Ensure that the entity exists
        if not sps.share.entityTypeNames.contains(entityNameIdx):
          raise sps.newScriptParseError(&"Entity type \"{entityName}\" not found")

        var braceToken = sps.readToken()
        var (bodyExpr, elseExpr) = case braceToken.kind
          of stkEol: (@[], @[])

          of stkWord:
            case braceToken.wordVal
            of "else":
              sps.expectToken(stkBraceOpen)
              (@[], sps.parseCodeBlock(stkBraceClosed))
            else:
              raise tok.newScriptParseError(&"Unexpected spawn block token {braceToken}")

          of stkBraceOpen:
            var bodyExpr: seq[ScriptNode] = @[]
            while true:
              var tok = sps.readToken()
              case tok.kind
              of stkBraceClosed: break # Exit here.
              of stkEol: discard
              of stkWord:
                case tok.wordVal.toLowerAscii()
                of "set":
                  var dstExpr = sps.parseExpr()
                  if dstExpr.kind != snkParamVar:
                    raise tok.newScriptParseError(&"Expected param in spawn block set, got {dstExpr} instead")
                  var srcExpr = sps.parseExpr()
                  bodyExpr.add(tok.tagPos(ScriptNode(
                    kind: snkAssign,
                    assignType: satSet,
                    assignDstExpr: dstExpr,
                    assignSrcExpr: srcExpr,
                  )))
                else:
                  raise tok.newScriptParseError(&"Unexpected spawn block keyword {tok}")
              else:
                raise tok.newScriptParseError(&"Unexpected token {tok}")

            (bodyExpr, sps.parseEolOrElse())

          else:
            raise tok.newScriptParseError(&"Unexpected spawn block token {braceToken}")

        case tok.wordVal.toLowerAscii()
          of "spawn":
            nodes.add(sps.tagPos(ScriptNode(
              kind: snkSpawn,
              spawnEntityNameIdx: entityNameIdx,
              spawnPos: posExpr,
              spawnBody: bodyExpr,
              spawnElse: elseExpr,
            )))
          of "spawninto":
            nodes.add(sps.tagPos(ScriptNode(
              kind: snkSpawnInto,
              spawnIntoDstExpr: dstExpr,
              spawnEntityNameIdx: entityNameIdx,
              spawnPos: posExpr,
              spawnBody: bodyExpr,
              spawnElse: elseExpr,
            )))
          else:
            raise tok.newScriptParseError(&"EDOOFUS: Unhandled spawn type {tok}!")

      of "while":
        var whileTest = sps.parseExpr()
        sps.expectToken(stkBraceOpen)
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkWhileBlock,
          whileTest: whileTest,
          whileBody: sps.parseCodeBlock(stkBraceClosed),
        )))
        awaitingEol = true

      else:
        raise tok.newScriptParseError(&"Unexpected word token \"{tok.wordVal}\"")
    else:
      if tok.kind == endKind:
        return nodes
      else:
        raise tok.newScriptParseError(&"Unexpected token {tok}")

proc parseRoot(sps: ScriptParseState, endKind: ScriptTokenKind): ScriptNode =
  var nodes: seq[ScriptNode] = @[]
  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEol: discard
    of stkWord:
      case tok.wordVal.toLowerAscii()

      of "on":
        nodes.add(sps.parseOnBlock())

      of "global":
        var varType = sps.readVarType()
        var varName = sps.readGlobalName()
        nodes.add(sps.tagPos(ScriptNode(
          kind: snkGlobalDef,
          globalDefType: varType,
          globalDefNameIdx: internKey(varName),
        )))

      of "param":
        var varType = sps.readVarType()
        var varName = sps.readParamName()
        var valueNode = sps.parseExpr()

        nodes.add(sps.tagPos(ScriptNode(
          kind: snkParamDef,
          paramDefType: varType,
          paramDefNameIdx: internKey(varName),
          paramDefInitValue: valueNode,
        )))

      of "local":
        var varType = sps.readVarType()
        var varName = sps.readLocalName()
        var valueNode = sps.parseExpr()

        nodes.add(sps.tagPos(ScriptNode(
          kind: snkLocalDef,
          localDefType: varType,
          localDefNameIdx: internKey(varName),
          localDefInitValue: valueNode,
        )))

      else:
        raise tok.newScriptParseError(&"Unexpected word token \"{tok.wordVal}\"")
    else:
      if tok.kind == endKind:
        return tok.tagPos(ScriptNode(
          kind: snkRootBlock,
          rootBody: nodes,
        ))
      else:
        raise tok.newScriptParseError(&"Unexpected token {tok}")
