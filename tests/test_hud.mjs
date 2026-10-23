import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import vm from 'node:vm'
import test from 'node:test'

const source = readFileSync(new URL('../mod/beamng_earth_enduro/ui/modules/apps/BeamNGEarthEnduroHUD/app.js', import.meta.url), 'utf8')
function app() {
  const commands = [], handlers = {}, timers = new Map()
  let definition, clock = 0
  const scope = { $on: (name, fn) => { handlers[name] = fn }, $evalAsync: fn => fn() }
  vm.runInNewContext(source, {
    angular: { module(name) {
      assert.equal(name, 'beamng.apps')
      return { directive(id, factory) { assert.equal(id, 'beamngEarthEnduroHud'); definition = factory.at(-1)() } }
    } },
    bngApi: { engineLua: command => commands.push(command) },
    setInterval: fn => { timers.set(1, fn); return 1 },
    clearInterval: id => timers.delete(id), Date: { now: () => clock }
  })
  definition.link(scope)
  return { scope, commands, handlers, timers, advance: ms => { clock += ms; for (const tick of timers.values()) tick() } }
}

test('app mounts and resynchronizes without overwriting layouts', () => {
  const a = app()
  assert.match(a.commands[0], /uiMounted\(true\)/)
  a.advance(3000)
  assert.match(a.commands[1], /uiMounted\(true\)/)
  assert.equal(a.scope.data.saveAllowed, false)
})
test('Save only sends the fixed command when Lua enabled it', () => {
  const a = app()
  a.scope.save()
  assert.equal(a.commands.length, 1)
  a.handlers.BeamNGEarthEnduroState({}, { state: 'READY', saveAllowed: true })
  a.scope.save()
  assert.equal(a.commands[1], 'if beamngEarthEnduro_core then beamngEarthEnduro_core.save() end')
  a.scope.reloadEnduro()
  assert.match(a.commands[2], /\.reload\(\)/)
})
test('test money button only sends the fixed command when Lua enabled it', () => {
  const a = app()
  a.scope.addTestMoney()
  assert.equal(a.commands.length, 1)
  a.handlers.BeamNGEarthEnduroState({}, { state: 'READY', testMoneyAllowed: true })
  a.scope.addTestMoney()
  assert.equal(a.commands[1], 'if beamngEarthEnduro_core then beamngEarthEnduro_core.addTestMoney() end')
})
test('repair buttons only send fixed commands when Lua enabled them', () => {
  const a = app()
  a.scope.requestRepairQuote(); a.scope.repairVehicle()
  assert.equal(a.commands.length, 1)
  a.handlers.BeamNGEarthEnduroState({}, { state: 'READY', repairQuoteAllowed: true, repairAllowed: true })
  a.scope.requestRepairQuote(); a.scope.repairVehicle()
  assert.equal(a.commands[1], 'if beamngEarthEnduro_core then beamngEarthEnduro_core.requestRepairQuote() end')
  assert.equal(a.commands[2], 'if beamngEarthEnduro_core then beamngEarthEnduro_core.repairVehicle() end')
})
test('parts buttons only send fixed commands when Lua enabled them', () => {
  const a = app()
  a.scope.buyParts(); a.scope.revertParts()
  assert.equal(a.commands.length, 1)
  a.handlers.BeamNGEarthEnduroState({}, { state: 'READY', buyPartsAllowed: true, revertPartsAllowed: true })
  a.scope.buyParts(); a.scope.revertParts()
  assert.equal(a.commands[1], 'if beamngEarthEnduro_core then beamngEarthEnduro_core.buyParts() end')
  assert.equal(a.commands[2], 'if beamngEarthEnduro_core then beamngEarthEnduro_core.revertParts() end')
})
test('restart button only sends the fixed command when Lua enabled it', () => {
  const a = app()
  a.scope.restartStage()
  assert.equal(a.commands.length, 1)
  a.handlers.BeamNGEarthEnduroState({}, { state: 'READY', restartAllowed: true })
  a.scope.restartStage()
  assert.equal(a.commands[1], 'if beamngEarthEnduro_core then beamngEarthEnduro_core.restartStage() end')
})
test('stale backend removes Save authorization', () => {
  const a = app()
  a.handlers.BeamNGEarthEnduroState({}, { state: 'READY', saveAllowed: true })
  a.advance(6001)
  assert.equal(a.scope.data.saveAllowed, false)
  assert.equal(a.scope.data.state, 'EARTH_UNAVAILABLE')
})
test('UI destruction releases timer and ignores late events', () => {
  const a = app()
  a.handlers.$destroy()
  assert.equal(a.timers.size, 0)
  assert.match(a.commands.at(-1), /uiMounted\(false\)/)
  a.handlers.BeamNGEarthEnduroState({}, { state: 'READY', saveAllowed: true })
  assert.equal(a.scope.data.saveAllowed, false)
})
test('coordinates copy as one latitude, longitude pair through the game clipboard', () => {
  const a = app()
  const position = { latitude: -33.86, longitude: 150.82 }
  assert.equal(a.scope.coordinates(position), '-33.86000000, 150.82000000')
  assert.equal(a.scope.coordinates({ latitude: 0, longitude: 0 }), '0.00000000, 0.00000000')
  a.scope.copyCoordinates(position)
  assert.equal(a.commands.at(-1), 'setClipboard("-33.86000000, 150.82000000")')
  const count = a.commands.length
  for (const invalid of [null, {}, { latitude: Infinity, longitude: 0 },
    { latitude: 0, longitude: 181 }, { latitude: 91, longitude: 0 },
    { latitude: '0); malicious()', longitude: 0 }]) {
    assert.equal(a.scope.coordinates(invalid), '')
    a.scope.copyCoordinates(invalid)
  }
  assert.equal(a.commands.length, count)
  const html = readFileSync(new URL('../mod/beamng_earth_enduro/ui/modules/apps/BeamNGEarthEnduroHUD/app.html', import.meta.url), 'utf8')
  assert.equal((html.match(/type="text" readonly/g) || []).length, 2)
  assert.ok(html.includes('ng-click="copyCoordinates(data.resume)"'))
  assert.ok(html.includes('ng-disabled="!coordinates(data.resume)"'))
  assert.ok(html.includes('ng-click="copyCoordinates(data.stage.finish)"'))
  assert.match(html, /Navigation tip:/)
  assert.doesNotMatch(html, /ng-bind-html|engineLua/)
})
test('the stage briefing can be dismissed without sending a command', () => {
  const a = app()
  const count = a.commands.length
  assert.equal(a.scope.briefingDismissed, false)
  a.scope.dismissBriefing()
  assert.equal(a.scope.briefingDismissed, true)
  assert.equal(a.commands.length, count)
})
