import strformat
import strutils

import types

proc parseCodeBlock*(sps: ScriptParseState, endKind: ScriptTokenKind): seq[ScriptNode]
proc parseRoot*(sps: ScriptParseState, endKind: ScriptTokenKind): ScriptNode

import scripttokens


proc parseExpr(sps: ScriptParseState): ScriptNode =
  var tok = sps.readToken()
  case tok.kind
  of stkInt: return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkInt, intVal: tok.intVal))
  of stkGlobalVar: return ScriptNode(kind: snkGlobalVar, globalVarName: tok.globalName)
  of stkParamVar: return ScriptNode(kind: snkParamVar, paramVarName: tok.paramName)
  of stkWord:
    case tok.strVal.toLowerAscii()
    of "false": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: false))
    of "true": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: true))

    of "i", "idle": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: 0))
    of "n", "north": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: -1))
    of "s", "south": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: +1))
    of "w", "west": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: -1, dirValY: 0))
    of "e", "east": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: +1, dirValY: 0))

    of "cw": return ScriptNode(kind: snkFunc, funcType: sftCw, funcArgs: @[sps.parseExpr()])
    of "opp": return ScriptNode(kind: snkFunc, funcType: sftOpp, funcArgs: @[sps.parseExpr()])
    of "ccw": return ScriptNode(kind: snkFunc, funcType: sftCcw, funcArgs: @[sps.parseExpr()])

    of "eq": return ScriptNode(kind: snkFunc, funcType: sftEq, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "ne": return ScriptNode(kind: snkFunc, funcType: sftNe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "lt": return ScriptNode(kind: snkFunc, funcType: sftLt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "le": return ScriptNode(kind: snkFunc, funcType: sftLe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "gt": return ScriptNode(kind: snkFunc, funcType: sftGt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "ge": return ScriptNode(kind: snkFunc, funcType: sftGe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])

    of "thispos": return ScriptNode(kind: snkFunc, funcType: sftThispos, funcArgs: @[])

    of "at": return ScriptNode(kind: snkFunc, funcType: sftAt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])

    else:
      raise newScriptParseError(sps, &"Expected expression, got {tok} instead")
  else:
    raise newScriptParseError(sps, &"Expected expression, got {tok} instead")


proc parseEolOrElse(sps: ScriptParseState): seq[ScriptNode] =
  var tok = sps.readToken()
  if tok.kind == stkEol:
    return @[]
  elif tok.kind == stkWord:
    case tok.strVal.toLowerAscii()
    of "else":
      sps.expectToken(stkBraceOpen)
      sps.expectToken(stkEol)
      return sps.parseCodeBlock(stkBraceClosed)
    else:
      raise newScriptParseError(sps, &"Expected EOL or \"else\" keyword, got {tok} instead")
  else:
    raise newScriptParseError(sps, &"Expected EOL or \"else\" keyword, got {tok} instead")

proc parseOnBlock(sps: ScriptParseState): ScriptNode =
  var typeName = sps.readKeywordToken()
  case typeName

  of "event":
    var eventName = sps.readKeywordToken()
    sps.expectToken(stkBraceOpen)
    sps.expectToken(stkEol)
    return ScriptNode(
      kind: snkOnEventBlock,
      onEventName: eventName,
      onEventBody: sps.parseCodeBlock(stkBraceClosed),
    )

  of "state":
    var stateName = sps.readKeywordToken()
    sps.expectToken(stkBraceOpen)
    sps.expectToken(stkEol)
    return ScriptNode(
      kind: snkOnStateBlock,
      onStateName: stateName,
      onStateBody: sps.parseCodeBlock(stkBraceClosed),
    )

  else:
    raise newScriptParseError(sps, &"Unexpected keyword \"{typeName}\" after \"on\" keyword")

proc parseCodeBlock(sps: ScriptParseState, endKind: ScriptTokenKind): seq[ScriptNode] =
  var nodes: seq[ScriptNode] = @[]
  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEol: discard
    of stkWord:
      case tok.strVal.toLowerAscii()

      of "goto":
        var stateName = sps.readKeywordToken()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkGoto,
          gotoStateName: stateName,
        ))

      of "broadcast":
        var eventName = sps.readKeywordToken()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkBroadcast,
          broadcastEventName: eventName,
        ))

      of "dec", "fdiv", "inc", "mul", "set":
        var assignType = case tok.strVal.toLowerAscii()
        of "dec": satDec
        of "fdiv": satFDiv
        of "inc": satInc
        of "mul": satMul
        of "set": satSet
        else:
          # SHOULD NOT REACH HERE!
          raise newScriptParseError(sps, &"EDOOFUS: ScriptAssignType unknown for {tok}!")

        var dstExpr = sps.parseExpr()
        var srcExpr = sps.parseExpr()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkAssign,
          assignType: assignType,
          assignDstExpr: dstExpr,
          assignSrcExpr: srcExpr,
        ))

      of "die":
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkDie,
        ))

      of "if":
        var ifTest = sps.parseExpr()
        sps.expectToken(stkBraceOpen)
        nodes.add(ScriptNode(
          kind: snkIfBlock,
          ifTest: ifTest,
          ifBody: sps.parseCodeBlock(stkBraceClosed),
          ifElse: sps.parseEolOrElse(),
        ))

      of "move":
        var dirExpr = sps.parseExpr()
        nodes.add(ScriptNode(
          kind: snkMove,
          moveDirExpr: dirExpr,
          moveElse: sps.parseEolOrElse(),
        ))

      of "send":
        var posExpr = sps.parseExpr()
        var eventName = sps.readKeywordToken().toLowerAscii()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkSend,
          sendEventName: eventName,
          sendPos: posExpr,
        ))

      of "sleep":
        var timeExpr = sps.parseExpr()
        sps.expectToken(stkEol)
        nodes.add(ScriptNode(
          kind: snkSleep,
          sleepTimeExpr: timeExpr,
        ))

      of "spawn":
        var posExpr = sps.parseExpr()
        var entityName = sps.readKeywordToken().toLowerAscii()
        sps.expectToken(stkBraceOpen)
        sps.expectToken(stkEol)

        var bodyExpr: seq[ScriptNode] = @[]
        while true:
          var tok = sps.readToken()
          case tok.kind
          of stkBraceClosed: break # Exit here.
          of stkEol: discard
          of stkWord:
            case tok.strVal.toLowerAscii()
            of "set":
              var dstExpr = sps.parseExpr()
              if dstExpr.kind != snkParamVar:
                raise newScriptParseError(sps, &"Expected param in spawn block set, got {dstExpr} instead")
              var srcExpr = sps.parseExpr()
              bodyExpr.add(ScriptNode(
                kind: snkAssign,
                assignType: satSet,
                assignDstExpr: dstExpr,
                assignSrcExpr: srcExpr,
              ))
            else:
              raise newScriptParseError(sps, &"Unexpected spawn block keyword {tok}")
          else:
            raise newScriptParseError(sps, &"Unexpected token {tok}")

        nodes.add(ScriptNode(
          kind: snkSpawn,
          spawnEntityName: entityName,
          spawnPos: posExpr,
          spawnBody: bodyExpr,
          spawnElse: sps.parseEolOrElse(),
        ))

      else:
        raise newScriptParseError(sps, &"Unexpected word token \"{tok.strval}\"")
    else:
      if tok.kind == endKind:
        return nodes
      else:
        raise newScriptParseError(sps, &"Unexpected token {tok}")

proc parseRoot(sps: ScriptParseState, endKind: ScriptTokenKind): ScriptNode =
  var nodes: seq[ScriptNode] = @[]
  while true:
    var tok = sps.readToken()
    case tok.kind
    of stkEol: discard
    of stkWord:
      case tok.strVal.toLowerAscii()

      of "on":
        nodes.add(sps.parseOnBlock())

      of "global":
        var varType = sps.readVarTypeKeyword()
        var varName = sps.readGlobalName()
        nodes.add(ScriptNode(
          kind: snkGlobalDef,
          globalDefType: varType,
          globalDefName: varName,
        ))

      of "param":
        var varType = sps.readVarTypeKeyword()
        var varName = sps.readParamName()
        var valueNode = sps.parseExpr()

        nodes.add(ScriptNode(
          kind: snkParamDef,
          paramDefType: varType,
          paramDefName: varName,
          paramDefInitValue: valueNode,
        ))

      else:
        raise newScriptParseError(sps, &"Unexpected word token \"{tok.strval}\"")
    else:
      if tok.kind == endKind:
        return ScriptNode(
          kind: snkRootBlock,
          rootBody: nodes,
        )
      else:
        raise newScriptParseError(sps, &"Unexpected token {tok}")
