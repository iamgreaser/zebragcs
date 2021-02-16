import tables

import ./types

proc broadcastEvent*(world: World, eventName: string)
proc newWorld*(share: ScriptSharedExecState): World

import ./board
import ./script/compile
import ./script/exec
import ./script/exprs

proc getWorldController(share: ScriptSharedExecState): ScriptExecBase =
  if share.worldController == nil:
    share.loadWorldControllerFromFile()

  share.worldController

proc newWorld(share: ScriptSharedExecState): World =
  assert share != nil
  assert share.world == nil
  var execBase = share.getWorldController()
  assert execBase != nil
  var world = World(
    boards: Table[string, Board](),
    execBase: execBase,
    activeState: execBase.initState,
    params: Table[string, ScriptVal](),
    locals: Table[string, ScriptVal](),
    alive: true,
    share: share,
    sleepTicksLeft: 0,
  )

  # Initialise!
  for k0, v0 in execBase.params.pairs():
    world.params[k0] = world.resolveExpr(v0.varDefault)
  for k0, v0 in execBase.locals.pairs():
    world.locals[k0] = world.resolveExpr(v0.varDefault)
  share.world = world
  world

proc broadcastEvent(world: World, eventName: string) =
  world.tickEvent(eventName)
  for board in world.boards.values():
    board.broadcastEvent(eventName)
