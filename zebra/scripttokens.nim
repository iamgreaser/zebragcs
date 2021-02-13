import streams
import strformat
import strscans
import strutils

import types

proc expectToken*(sps: ScriptParseState, kind: ScriptTokenKind)
proc newScriptParseError*(sps: ScriptParseState, message: string): ref ScriptParseError
proc readGlobalName*(sps: ScriptParseState): string
proc readKeywordToken*(sps: ScriptParseState): string
proc readParamName*(sps: ScriptParseState): string
proc readToken*(sps: ScriptParseState): ScriptToken
proc pushBackToken*(sps: ScriptParseState, tok: ScriptToken)
proc readVarTypeKeyword*(sps: ScriptParseState): ScriptValKind

const maxPeekDist = 100


proc newScriptParseError(sps: ScriptParseState, message: string): ref ScriptParseError =
  newException(ScriptParseError, &"{sps.row}:{sps.col}: {message}")

proc skipBytes(sps: ScriptParseState, count: int) =
  var skipped = sps.strm.readstr(count)
  for c in skipped:
    if c == '\n':
      sps.col = 1
      sps.row += 1
    elif c == '\r':
      raise newException(ScriptParseError, &"unexpected CR character at {sps.row}:{sps.col}, stop using Windows newlines")
    elif c == '\t':
      raise newException(ScriptParseError, &"unexpected tab character at {sps.row}:{sps.col}")
    else:
      sps.col += 1

proc readTokenDirect(sps: ScriptParseState): ScriptToken =
  var s = peekStr(sps.strm, maxPeekDist)
  var mid, post: string
  var midInt: int

  # Skip comments
  if scanf(s, "$s#$*", post):
    skipBytes(sps, s.len - post.len)
    s = peekStr(sps.strm, maxPeekDist)
    if scanf(s, "$*\n$*", mid, post):
      echo &"Comment: [#{mid}]"
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
  elif scanf(s, "$s$i$*", midInt, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkInt, intVal: midInt)
  elif scanf(s, "$s$$$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkGlobalVar, globalName: mid)
  elif scanf(s, "$s@$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkParamVar, paramName: mid)
  elif scanf(s, "$s$w$*", mid, post):
    skipBytes(sps, s.len - post.len)
    return ScriptToken(kind: stkWord, strVal: mid)
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
      sps.readTokenDirect()
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

proc readKeywordToken(sps: ScriptParseState): string =
  var tok = sps.readToken()
  if tok.kind == stkWord:
    return tok.strVal.toLowerAscii()
  else:
    raise newScriptParseError(sps, &"Expected keyword token, got {tok} instead")

proc readVarTypeKeyword(sps: ScriptParseState): ScriptValKind =
  var varTypeName = sps.readKeywordToken()
  case varTypeName
  of "bool": svkBool
  of "dir": svkDir
  of "int": svkInt
  of "pos": svkPos
  else:
    raise newScriptParseError(sps, &"Expected type keyword, got \"{varTypeName}\" instead")

proc readGlobalName(sps: ScriptParseState): string =
  sps.readExpectedToken(stkGlobalVar).globalName

proc readParamName(sps: ScriptParseState): string =
  sps.readExpectedToken(stkParamVar).paramName
