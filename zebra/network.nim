import net
#import tables

type
  NetClientState = enum
    clInit,
  NetClientObj = object
    sock: Socket
    ipAddr: string
    udpPort: Port
    state: NetClientState
  NetClient* = ref NetClientObj

  NetServerState = enum
    svInit,
  NetServerObj = object
    sock: Socket
    udpPort: Port
    state: NetServerState
  NetServer* = ref NetServerObj

  NetServerPeerState = enum
    svpeerInit,
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
    state: clInit,
  )

proc newServer*(udpPort: Port = Port(22700)): NetServer =
  # TODO: Work out how to make this work sanely with dual IPv4+IPv6 --GM
  var sock = newSocket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
  sock.bindAddr(port = udpPort)
  NetServer(
    sock: sock,
    udpPort: udpPort,
    state: svInit,
  )
