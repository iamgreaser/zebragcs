import streams
import strformat
import strscans
import strutils

import ../types

proc expectEolOrEof*(sps: ScriptParseState)
proc expectToken*(sps: ScriptParseState, kind: ScriptTokenKind)
proc newScriptParseError*(sps: ScriptParseState, message: string): ref ScriptParseError
proc newScriptParseError*(tok: ScriptToken, message: string): ref ScriptParseError
proc newScriptParseError*(node: ScriptNode, message: string): ref ScriptParseError
proc pushBackToken*(sps: ScriptParseState, tok: ScriptToken)
proc readBool*(sps: ScriptParseState): bool
proc readExpectedToken*(sps: ScriptParseState, kind: ScriptTokenKind): ScriptToken
proc readGlobalName*(sps: ScriptParseState): string
proc readInt*(sps: ScriptParseState): int64
proc readKeywordToken*(sps: ScriptParseState): string
proc readLocalName*(sps: ScriptParseState): string
proc readParamName*(sps: ScriptParseState): string
proc readToken*(sps: ScriptParseState): ScriptToken
proc readVarTypeKeyword*(sps: ScriptParseState): ScriptValKind

const maxPeekDist = 200


proc newScriptParseError(sps: ScriptParseState, message: string): ref ScriptParseError =
  newException(ScriptParseError, &"{sps.fname}:{sps.row}:{sps.col}: {message}")
proc newScriptParseError(tok: ScriptToken, message: string): ref ScriptParseError =
  newException(ScriptParseError, &"{tok.fname}:{tok.row}:{tok.col}: {message}")
proc newScriptParseError(node: ScriptNode, message: string): ref ScriptParseError =
  newException(ScriptParseError, &"{node.fname}:{node.row}:{node.col}: {message}")

proc skipBytes(sps: ScriptParseState, count: int) =
  var skipped = sps.strm.readstr(count)
  for c in skipped:
    if c == '\n':
      sps.col = 1
      sps.row += 1
    elif c == '\r':
      raise sps.newScriptParseError(&"unexpected CR character, stop using Windows newlines")
    elif c == '\t':
      raise sps.newScriptParseError(&"unexpected tab character")
    else:
      sps.col += 1

proc readTokenDirect(sps: ScriptParseState): ScriptToken =
  var s = peekStr(sps.strm, maxPeekDist)
  var mid, post: string
  var midInt: int # FIXME: We need a 64-bit version of this --GM

  if sps.isParsingString:
    var i = 0
    var accum = ""
    while i < s.len:
      case s[i]
      of '"':
        if accum != "":
          skipBytes(sps, i)
          return ScriptToken(kind: stkStrConst, strConst: accum)
        else:
          skipBytes(sps, i+1)
          sps.isParsingString = false
          return ScriptToken(kind: stkStrClosed)

      of '\\':
        i += 1
        if i >= s.len: raise newScriptParseError(sps, &"Line in string too long")

        case s[i]
        of '\\', '"':
          accum.add(s[i])
          i += 1
        of '(':
          if accum != "":
            skipBytes(sps, i-1)
            return ScriptToken(kind: stkStrConst, strConst: accum)
          else:
            skipBytes(sps, i+1)
            sps.stringInterpLevel += 1
            sps.isParsingString = false
            return ScriptToken(kind: stkStrExprOpen)
        else: raise newScriptParseError(sps, &"Unexpected char escape '\\{s[i]}'")

      else:
        accum.add(s[i])
        i += 1

    raise newScriptParseError(sps, &"Line in string too long")

  # Skip comments
  if scanf(s, "$s#$*", post):
    skipBytes(sps, s.len - post.len)
    s = peekStr(sps.strm, maxPeekDist)
    if scanf(s, "$*\n$*", mid, post):
      #echo &"Comment: [#{mid}]"
      skipBytes(sps, s.len - post.len)
      return ScriptToken(kind: stkEol)
    else:
      skipBytes(sps, s.len)
      s = peekStr(sps.strm, maxPeekDist)
      if s == "":
        return ScriptToken(kind: stkEof)
      else:
        raise newScriptParseError(sps, &"Line after comment too long")

  if scanf(s, "$*\n$s$*", mid, post) and scanf(mid, "$s$."):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkEol)
  elif scanf(s, "$s\"$*", post):
    skipBytes(sps, s.len - post.len)
    sps.isParsingString = true
    return ScriptToken(kind: stkStrOpen)
  elif scanf(s, "$s)$*", post):
    skipBytes(sps, s.len - post.len)
    if sps.stringInterpLevel >= 1:
      sps.stringInterpLevel -= 1
      sps.isParsingString = true
    else:
      raise newScriptParseError(sps, &"Unexpected ')'")
    return ScriptToken(kind: stkStrExprClosed)
  elif scanf(s, "$s$i$*", midInt, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkInt, intVal: midInt)
  elif scanf(s, "$s$$$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkGlobalVar, globalName: mid)
  elif scanf(s, "$s@$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkParamVar, paramName: mid)
  elif scanf(s, "$s%$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkLocalVar, localName: mid)
  elif scanf(s, "$s$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkWord, wordVal: mid)
  elif scanf(s, "$s[$*", post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkSquareOpen)
  elif scanf(s, "$s]$*", post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkSquareClosed)
  elif scanf(s, "$s{$*", post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkBraceOpen)
  elif scanf(s, "$s}$*", post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkBraceClosed)
  elif s == "":
    return ScriptToken(kind: stkEof)
  else:
    #raise newScriptParseError(sps, &"Invalid token from \"{s}\"")
    raise newScriptParseError(sps, &"Invalid token")

proc readToken(sps: ScriptParseState): ScriptToken =
  var tok = if sps.tokenPushStack.len >= 1:
      sps.tokenPushStack.pop()
    else:
      var fname = sps.fname
      var row = sps.row
      var col = sps.col
      var tok = sps.readTokenDirect()
      tok.fname = fname
      tok.row = row
      tok.col = col
      tok
  #echo &"Token: {tok}"
  return tok

proc pushBackToken(sps: ScriptParseState, tok: ScriptToken) =
  sps.tokenPushStack.add(tok)

proc readExpectedToken(sps: ScriptParseState, kind: ScriptTokenKind): ScriptToken =
  var tok = sps.readToken()
  if tok.kind != kind:
    raise newScriptParseError(sps, &"Expected {kind} token, got {tok} instead")
  else:
    return tok

proc expectToken(sps: ScriptParseState, kind: ScriptTokenKind) =
  var tok = sps.readToken()
  if tok.kind != kind:
    raise newScriptParseError(sps, &"Expected {kind} token, got {tok} instead")

proc expectEolOrEof(sps: ScriptParseState) =
  var tok = sps.readToken()
  if tok.kind != stkEol and tok.kind != stkEof:
    raise newScriptParseError(sps, &"Expected EOL or EOF, got {tok} instead")

proc readKeywordToken(sps: ScriptParseState): string =
  var tok = sps.readToken()
  if tok.kind == stkWord:
    return tok.wordVal.toLowerAscii()
  else:
    raise newScriptParseError(sps, &"Expected keyword token, got {tok} instead")

proc readVarTypeKeyword(sps: ScriptParseState): ScriptValKind =
  var varTypeName = sps.readKeywordToken()
  case varTypeName
  of "bool": svkBool
  of "cell": svkCell
  of "dir": svkDir
  of "entity": svkEntity
  of "int": svkInt
  of "player": svkPlayer
  of "pos": svkPos
  of "str": svkStr
  else:
    raise newScriptParseError(sps, &"Expected type keyword, got \"{varTypeName}\" instead")

proc readBool(sps: ScriptParseState): bool =
  var kw = sps.readKeywordToken()
  case kw
    of "true": true
    of "false": false
    else:
      raise newScriptParseError(sps, &"Expected boolean keyword, got \"{kw}\" instead")

proc readInt(sps: ScriptParseState): int64 =
  sps.readExpectedToken(stkInt).intVal

proc readGlobalName(sps: ScriptParseState): string =
  sps.readExpectedToken(stkGlobalVar).globalName

proc readParamName(sps: ScriptParseState): string =
  sps.readExpectedToken(stkParamVar).paramName

proc readLocalName(sps: ScriptParseState): string =
  sps.readExpectedToken(stkLocalVar).localName
