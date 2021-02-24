import net
import streams
#import tables

import ./types

type
  NetEventType* = enum
    nevInputPress,
    nevInputRelease,
    nevInputType,
  NetEventObj = object
    case kind*: NetEventType
    of nevInputPress, nevInputRelease, nevInputType:
      inputKey*: InputKeyType
  NetEvent* = ref NetEventObj

  NetInputResultFrameObj = object
    seed: uint64
    playerId: uint16
    inputs: seq[NetEvent]
  NetInputResultFrame* = ref NetInputResultFrameObj

  NetMessageType* = enum
    nmtQuit,
    nmtHelloReq,
    nmtHelloAck,
    nmtHelloGotAck,
    nmtInputFramePut,
    nmtInputFrameTicks,
  NetMessageObj = object
    case kind*: NetMessageType
    of nmtQuit: discard
    of nmtHelloReq: discard
    of nmtHelloAck: discard
    of nmtHelloGotAck: discard
    of nmtInputFramePut:
      inputPutGotFrameIdx*: uint8
      inputPutNeedFrameIdx*: uint8
      inputPutFrameIdx*: uint8
      inputPutSeq*: seq[NetEvent]
    of nmtInputFrameTicks:
      inputTickFrameBegIdx*: uint8
      inputTickSeq*: seq[seq[NetInputResultFrame]]
  NetMessage* = ref NetMessageObj

  NetClientState = enum
    clDead,
    clConnectStart,
    clConnectWait,
    clPreGameLobby,
    clInGame,
  NetClientObj = object
    sock: Socket
    ipAddr: string
    udpPort: Port
    state: NetClientState
  NetClient* = ref NetClientObj

  NetServerState = enum
    svDead,
    svPreGameLobby,
  NetServerObj = object
    sock: Socket
    udpPort: Port
    state: NetServerState
  NetServer* = ref NetServerObj

  NetServerPeerState = enum
    svpeerDead,
    svpeerConnectAckStart,
    svpeerConnectAckWait,
    svpeerPreGameLobby,
    svpeerInGame,
  NetServerPeerObj = object
    server: NetServer
    ipAddr: string
    udpPort: Port
    state: NetServerPeerState
  NetServerPeer* = ref NetServerPeerObj

proc newClient*(ipAddr: string, udpPort: Port = Port(22700)): NetClient =
  var sock = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  NetClient(
    sock: sock,
    ipAddr: ipAddr,
    udpPort: udpPort,
    state: clConnectStart,
  )

proc newServer*(udpPort: Port = Port(22700)): NetServer =
  # TODO: Work out how to make this work sanely with dual IPv4+IPv6 --GM
  var sock = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  sock.bindAddr(port = udpPort)
  NetServer(
    sock: sock,
    udpPort: udpPort,
    state: svPreGameLobby,
  )

proc readNetObj*(strm: Stream, msg: var NetEvent) =
  msg = NetEvent(kind: NetEventType(strm.readUint8()))
  case msg.kind
  of nevInputPress, nevInputRelease, nevInputType:
    msg.inputKey = InputKeyType(strm.readUint8())

proc writeNetObj*(strm: Stream, msg: NetEvent) =
  strm.write(uint8(msg.kind))
  case msg.kind
  of nevInputPress, nevInputRelease, nevInputType:
    strm.write(uint8(msg.inputKey))

proc readNetObj*(strm: Stream, msg: var NetInputResultFrame) =
  msg.seed = strm.readUint64()
  msg.playerId = strm.readUint16()
  msg.inputs.setLen(strm.readUint8())
  for idx in 0..(msg.inputs.len-1):
    strm.readNetObj(msg.inputs[idx])

proc writeNetObj*(strm: Stream, msg: NetInputResultFrame) =
  strm.write(uint64(msg.seed))
  strm.write(uint16(msg.playerId))
  strm.write(uint8(msg.inputs.len))
  for ev in msg.inputs:
    strm.writeNetObj(ev)

proc readNetObj*(strm: Stream, msg: var NetMessage) =
  msg = NetMessage(kind: NetMessageType(strm.readUint8()))
  case msg.kind
    of nmtQuit: discard
    of nmtHelloReq: discard
    of nmtHelloAck: discard
    of nmtHelloGotAck: discard
    of nmtInputFramePut:
      msg.inputPutGotFrameIdx = strm.readUint8()
      msg.inputPutNeedFrameIdx = strm.readUint8()
      msg.inputPutFrameIdx = strm.readUint8()
      var putSeqLen: uint32 = strm.readUint8()
      msg.inputPutSeq.setLen(putSeqLen)
      for idx in 0..(putSeqLen-1):
        strm.readNetObj(msg.inputPutSeq[idx])
    of nmtInputFrameTicks:
      msg.inputTickFrameBegIdx = strm.readUint8()
      var tickSeqLen: uint32 = strm.readUint8()
      msg.inputTickSeq.setLen(tickSeqLen)
      for i in 0..(tickSeqLen-1):
        var tickSeqSeqLen: uint32 = strm.readUint8()
        msg.inputTickSeq[i].setLen(tickSeqLen)
        for j in 0..(tickSeqSeqLen-1):
          strm.readNetObj(msg.inputTickSeq[i][j])

proc writeNetObj*(strm: Stream, msg: NetMessage) =
  strm.write(uint8(msg.kind))
  case msg.kind
    of nmtQuit: discard
    of nmtHelloReq: discard
    of nmtHelloAck: discard
    of nmtHelloGotAck: discard
    of nmtInputFramePut:
      strm.write(uint8(msg.inputPutGotFrameIdx))
      strm.write(uint8(msg.inputPutNeedFrameIdx))
      strm.write(uint8(msg.inputPutFrameIdx))
      strm.write(uint8(msg.inputPutSeq.len))
      for ev in msg.inputPutSeq:
        strm.writeNetObj(ev)
    of nmtInputFrameTicks:
      strm.write(uint8(msg.inputTickFrameBegIdx))
      strm.write(uint8(msg.inputTickSeq.len))
      for fr in msg.inputTickSeq:
        strm.write(uint8(fr.len))
        for ev in fr:
          strm.writeNetObj(ev)
