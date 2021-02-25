import nativesockets
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
    playerId*: uint16
    inputs*: seq[NetEvent]
  NetInputResultFrame* = ref NetInputResultFrameObj

  NetMessageType* = enum
    nmtQuit,
    nmtHelloReq,
    nmtHelloAck,
    nmtHelloGotAck,
    nmtStartGameReq,
    nmtStartGameAck,
    nmtInputFramePut,
    nmtInputFrameTick,
  NetMessageObj = object
    case kind*: NetMessageType
    of nmtQuit: discard
    of nmtHelloReq: discard
    of nmtHelloAck: discard
    of nmtHelloGotAck: discard
    of nmtStartGameReq:
      startGameReqSeed: uint64
    of nmtStartGameAck: discard
    of nmtInputFramePut:
      inputPutNeedFrameIdx*: uint16
      inputPutGotFrameIdx*: uint16
      inputPutSeq*: seq[NetEvent]
    of nmtInputFrameTick:
      inputTickFrameIdx*: uint16
      inputTickSeq*: seq[NetInputResultFrame]
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
    inputTickMessages: seq[NetMessage]
  NetClient* = ref NetClientObj

  NetServerState = enum
    svDead,
    svPreGameLobby,
  NetServerObj = object
    sock: Socket
    udpPort: Port
    state: NetServerState
    peers: seq[NetServerPeer]
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
  #sock.fd.setBlocking(false)
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
  #sock.fd.setBlocking(false)
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
  msg.playerId = strm.readUint16()
  msg.inputs.setLen(strm.readUint8())
  for idx in 0..(msg.inputs.len-1):
    strm.readNetObj(msg.inputs[idx])

proc writeNetObj*(strm: Stream, msg: NetInputResultFrame) =
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
    of nmtStartGameReq:
      msg.startGameReqSeed = strm.readUint64()
    of nmtStartGameAck: discard
    of nmtInputFramePut:
      msg.inputPutNeedFrameIdx = strm.readUint16()
      msg.inputPutGotFrameIdx = strm.readUint16()
      var putSeqLen: uint32 = strm.readUint8()
      msg.inputPutSeq.setLen(0)
      if putSeqLen >= 1:
        for idx in 0..(putSeqLen-1):
          var v = NetEvent()
          strm.readNetObj(v)
          msg.inputPutSeq.add(v)
    of nmtInputFrameTick:
      msg.inputTickFrameIdx = strm.readUint16()

      var tickSeqLen: uint32 = strm.readUint8()
      msg.inputTickSeq.setLen(0)
      if tickSeqLen >= 1:
        for i in 0..(tickSeqLen-1):
          var v = NetInputResultFrame()
          strm.readNetObj(v)
          msg.inputTickSeq.add(v)

proc writeNetObj*(strm: Stream, msg: NetMessage) =
  strm.write(uint8(msg.kind))
  case msg.kind
    of nmtQuit: discard
    of nmtHelloReq: discard
    of nmtHelloAck: discard
    of nmtHelloGotAck: discard
    of nmtStartGameReq:
      strm.write(uint64(msg.startGameReqSeed))
    of nmtStartGameAck: discard
    of nmtInputFramePut:
      strm.write(uint16(msg.inputPutNeedFrameIdx))
      strm.write(uint16(msg.inputPutGotFrameIdx))
      strm.write(uint8(msg.inputPutSeq.len))
      for ev in msg.inputPutSeq:
        strm.writeNetObj(ev)
    of nmtInputFrameTick:
      strm.write(uint16(msg.inputTickFrameIdx))
      strm.write(uint8(msg.inputTickSeq.len))
      for fr in msg.inputTickSeq:
        strm.writeNetObj(fr)

proc sendRaw*(netClient: NetClient, msg: string) =
  netClient.sock.sendTo(netClient.ipAddr, netClient.udpPort, msg)

proc broadcastRaw*(netServer: NetServer, msg: string) =
  for peer in netServer.peers:
    netServer.sock.sendTo(peer.ipAddr, peer.udpPort, msg)

proc update*(netClient: NetClient) =
  var data: string
  var address: string
  var port: Port
  var dataLen: int = netClient.sock.recvFrom(data, 1536, address, port)

proc update*(netServer: NetServer) =
  var data: string
  var address: string
  var port: Port
  var dataLen: int = netServer.sock.recvFrom(data, 1536, address, port)

iterator recvInputs*(netClient: NetClient): NetMessage =
  for msg in netClient.inputTickMessages:
    yield msg
  netClient.inputTickMessages.setLen(0)
