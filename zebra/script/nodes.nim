import strformat
import strutils

import ../types

proc parseCodeBlock*(sps: ScriptParseState, endKind: ScriptTokenKind): seq[ScriptNode]
proc parseRoot*(sps: ScriptParseState, endKind: ScriptTokenKind): ScriptNode

import ./tokens


proc parseExpr(sps: ScriptParseState): ScriptNode =
  var tok = sps.readToken()
  case tok.kind
  of stkInt: return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkInt, intVal: tok.intVal))
  of stkString: return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkStr, strVal: tok.strVal))
  of stkGlobalVar: return ScriptNode(kind: snkGlobalVar, globalVarName: tok.globalName)
  of stkParamVar: return ScriptNode(kind: snkParamVar, paramVarName: tok.paramName)
  of stkLocalVar: return ScriptNode(kind: snkLocalVar, localVarName: tok.localName)
  of stkWord:
    case tok.wordVal.toLowerAscii()
    of "false": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: false))
    of "true": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkBool, boolVal: true))

    of "noentity": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkEntity, entityRef: nil))
    of "noplayer": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkPlayer, playerRef: nil))

    of "i", "idle": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: 0))
    of "n", "north": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: -1))
    of "s", "south": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: 0, dirValY: +1))
    of "w", "west": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: -1, dirValY: 0))
    of "e", "east": return ScriptNode(kind: snkConst, constVal: ScriptVal(kind: svkDir, dirValX: +1, dirValY: 0))

    of "self": return ScriptNode(kind: snkFunc, funcType: sftSelf, funcArgs: @[])
    of "posof": return ScriptNode(kind: snkFunc, funcType: sftPosof, funcArgs: @[sps.parseExpr()])

    of "cw": return ScriptNode(kind: snkFunc, funcType: sftCw, funcArgs: @[sps.parseExpr()])
    of "opp": return ScriptNode(kind: snkFunc, funcType: sftOpp, funcArgs: @[sps.parseExpr()])
    of "ccw": return ScriptNode(kind: snkFunc, funcType: sftCcw, funcArgs: @[sps.parseExpr()])

    of "eq": return ScriptNode(kind: snkFunc, funcType: sftEq, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "ne": return ScriptNode(kind: snkFunc, funcType: sftNe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "lt": return ScriptNode(kind: snkFunc, funcType: sftLt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "le": return ScriptNode(kind: snkFunc, funcType: sftLe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "gt": return ScriptNode(kind: snkFunc, funcType: sftGt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "ge": return ScriptNode(kind: snkFunc, funcType: sftGe, funcArgs: @[sps.parseExpr(), sps.parseExpr()])

    of "not": return ScriptNode(kind: snkFunc, funcType: sftNot, funcArgs: @[sps.parseExpr()])

    of "thispos": return ScriptNode(kind: snkFunc, funcType: sftThispos, funcArgs: @[])

    of "at": return ScriptNode(kind: snkFunc, funcType: sftAt, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "atboard": return ScriptNode(kind: snkFunc, funcType: sftAtBoard, funcArgs: @[
      ScriptNode(kind: snkConst, constVal: ScriptVal(
        kind: svkStr, strVal: sps.readKeywordToken().toLowerAscii(),
      )),
      sps.parseExpr(), sps.parseExpr(),
    ])

    of "dirx": return ScriptNode(kind: snkFunc, funcType: sftDirX, funcArgs: @[sps.parseExpr()])
    of "diry": return ScriptNode(kind: snkFunc, funcType: sftDirY, funcArgs: @[sps.parseExpr()])
    of "random": return ScriptNode(kind: snkFunc, funcType: sftRandom, funcArgs: @[sps.parseExpr(), sps.parseExpr()])
    of "randomdir": return ScriptNode(kind: snkFunc, funcType: sftRandomDir, funcArgs: @[])
    of "seek": return ScriptNode(kind: snkFunc, funcType: sftSeek, funcArgs: @[sps.parseExpr()])

    else:
      raise newScriptParseError(sps, &"Expected expression, got {tok} instead")
  else:
    raise newScriptParseError(sps, &"Expected expression, got {tok} instead")


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
      raise newScriptParseError(sps, &"Expected EOL or \"else\" keyword, got {tok} instead")
  of stkBraceClosed:
    sps.pushBackToken(tok)
    return @[]
  else:
    raise newScriptParseError(sps, &"Expected EOL or \"else\" keyword, got {tok} instead")

proc parseOnBlock(sps: ScriptParseState): ScriptNode =
  var typeName = sps.readKeywordToken()
  case typeName

  of "event":
    var eventName = sps.readKeywordToken()
    sps.expectToken(stkBraceOpen)
    return ScriptNode(
      kind: snkOnEventBlock,
      onEventName: eventName,
      onEventBody: sps.parseCodeBlock(stkBraceClosed),
    )

  of "state":
    var stateName = sps.readKeywordToken()
    sps.expectToken(stkBraceOpen)
    return ScriptNode(
      kind: snkOnStateBlock,
      onStateName: stateName,
      onStateBody: sps.parseCodeBlock(stkBraceClosed),
    )

  else:
    raise newScriptParseError(sps, &"Unexpected keyword \"{typeName}\" after \"on\" keyword")

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
        raise newScriptParseError(sps, &"Expected EOL, got {tok} instead")

      case tok.wordVal.toLowerAscii()

      of "goto":
        var stateName = sps.readKeywordToken()
        awaitingEol = true
        nodes.add(ScriptNode(
          kind: snkGoto,
          gotoStateName: stateName,
        ))

      of "broadcast":
        var eventName = sps.readKeywordToken()
        awaitingEol = true
        nodes.add(ScriptNode(
          kind: snkBroadcast,
          broadcastEventName: eventName,
        ))

      of "dec", "fdiv", "inc", "mul", "set":
        var assignType = case tok.wordVal.toLowerAscii()
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
        awaitingEol = true
        nodes.add(ScriptNode(
          kind: snkAssign,
          assignType: assignType,
          assignDstExpr: dstExpr,
          assignSrcExpr: srcExpr,
        ))

      of "die":
        awaitingEol = true
        nodes.add(ScriptNode(
          kind: snkDie,
        ))

      of "forcemove":
        var dirExpr = sps.parseExpr()
        nodes.add(ScriptNode(
          kind: snkForceMove,
          forceMoveDirExpr: dirExpr,
        ))


      of "if":
        var ifTest = sps.parseExpr()
        sps.expectToken(stkBraceOpen)
        var ifBody = sps.parseCodeBlock(stkBraceClosed)
        var ifElse = sps.parseEolOrElse()
        nodes.add(ScriptNode(
          kind: snkIfBlock,
          ifTest: ifTest,
          ifBody: ifBody,
          ifElse: ifElse,
        ))

      of "move":
        var dirExpr = sps.parseExpr()
        nodes.add(ScriptNode(
          kind: snkMove,
          moveDirExpr: dirExpr,
          moveElse: sps.parseEolOrElse(),
        ))

      of "say":
        var sayExpr = sps.parseExpr()
        awaitingEol = true
        nodes.add(ScriptNode(
          kind: snkSay,
          sayExpr: sayExpr,
        ))

      of "send":
        var posExpr = sps.parseExpr()
        var eventName = sps.readKeywordToken().toLowerAscii()
        awaitingEol = true
        nodes.add(ScriptNode(
          kind: snkSend,
          sendEventName: eventName,
          sendPos: posExpr,
        ))

      of "sleep":
        var timeExpr = sps.parseExpr()
        awaitingEol = true
        nodes.add(ScriptNode(
          kind: snkSleep,
          sleepTimeExpr: timeExpr,
        ))

      of "spawn", "spawninto":
        var dstExpr = case tok.wordVal.toLowerAscii()
          of "spawninto": sps.parseExpr()
          of "spawn": nil
          else:
            raise newScriptParseError(sps, &"EDOOFUS: Unhandled spawn type {tok}!")

        var posExpr = sps.parseExpr()
        var entityName = sps.readKeywordToken().toLowerAscii()
        var braceToken = sps.readToken()
        var (bodyExpr, elseExpr) = case braceToken.kind
          of stkEol: (@[], @[])

          of stkWord:
            case braceToken.wordVal
            of "else":
              sps.expectToken(stkBraceOpen)
              (@[], sps.parseCodeBlock(stkBraceClosed))
            else:
              raise newScriptParseError(sps, &"Unexpected spawn block token {braceToken}")

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

            (bodyExpr, sps.parseEolOrElse())

          else:
            raise newScriptParseError(sps, &"Unexpected spawn block token {braceToken}")

        case tok.wordVal.toLowerAscii()
          of "spawn":
            nodes.add(ScriptNode(
              kind: snkSpawn,
              spawnEntityName: entityName,
              spawnPos: posExpr,
              spawnBody: bodyExpr,
              spawnElse: elseExpr,
            ))
          of "spawninto":
            nodes.add(ScriptNode(
              kind: snkSpawnInto,
              spawnIntoDstExpr: dstExpr,
              spawnEntityName: entityName,
              spawnPos: posExpr,
              spawnBody: bodyExpr,
              spawnElse: elseExpr,
            ))
          else:
            raise newScriptParseError(sps, &"EDOOFUS: Unhandled spawn type {tok}!")

      of "while":
        var whileTest = sps.parseExpr()
        sps.expectToken(stkBraceOpen)
        nodes.add(ScriptNode(
          kind: snkWhileBlock,
          whileTest: whileTest,
          whileBody: sps.parseCodeBlock(stkBraceClosed),
        ))
        awaitingEol = true

      else:
        raise newScriptParseError(sps, &"Unexpected word token \"{tok.wordVal}\"")
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
      case tok.wordVal.toLowerAscii()

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

      of "local":
        var varType = sps.readVarTypeKeyword()
        var varName = sps.readLocalName()
        var valueNode = sps.parseExpr()

        nodes.add(ScriptNode(
          kind: snkLocalDef,
          localDefType: varType,
          localDefName: varName,
          localDefInitValue: valueNode,
        ))

      else:
        raise newScriptParseError(sps, &"Unexpected word token \"{tok.wordVal}\"")
    else:
      if tok.kind == endKind:
        return ScriptNode(
          kind: snkRootBlock,
          rootBody: nodes,
        )
      else:
        raise newScriptParseError(sps, &"Unexpected token {tok}")
