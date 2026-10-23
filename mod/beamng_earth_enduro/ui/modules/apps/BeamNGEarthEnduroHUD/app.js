/* global angular, bngApi */
angular.module('beamng.apps').directive('beamngEarthEnduroHud', [function () {
  return {
    templateUrl: '/ui/modules/apps/BeamNGEarthEnduroHUD/app.html',
    replace: true,
    link: function (scope) {
      'use strict'
      var disposed = false
      var lastMessage = Date.now()
      scope.data = { state: 'EARTH_UNAVAILABLE', stateLabel: 'WAITING FOR THE RALLY', saveAllowed: false }
      var call = function (command) {
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) bngApi.engineLua(command)
      }
      var mount = function (on) {
        call('if beamngEarthEnduro_core then beamngEarthEnduro_core.uiMounted(' + (on ? 'true' : 'false') + ') end')
      }
      scope.save = function () {
        if (scope.data.saveAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.save() end')
      }
      scope.addTestMoney = function () {
        if (scope.data.testMoneyAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.addTestMoney() end')
      }
      scope.requestRepairQuote = function () {
        if (scope.data.repairQuoteAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.requestRepairQuote() end')
      }
      scope.repairVehicle = function () {
        if (scope.data.repairAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.repairVehicle() end')
      }
      scope.buyParts = function () {
        if (scope.data.buyPartsAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.buyParts() end')
      }
      scope.revertParts = function () {
        if (scope.data.revertPartsAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.revertParts() end')
      }
      scope.restartStage = function () {
        if (scope.data.restartAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.restartStage() end')
      }
      scope.reloadEnduro = function () {
        call('if beamngEarthEnduro_core then beamngEarthEnduro_core.reload() end')
      }
      scope.coordinates = function (position) {
        if (!position || typeof position.latitude !== 'number' || typeof position.longitude !== 'number' ||
            !isFinite(position.latitude) || !isFinite(position.longitude) ||
            Math.abs(position.latitude) > 90 || Math.abs(position.longitude) > 180) return ''
        return position.latitude.toFixed(8) + ', ' + position.longitude.toFixed(8)
      }
      scope.copyCoordinates = function (position) {
        var text = scope.coordinates(position)
        if (!text) return
        if (typeof bngApi !== 'undefined' && bngApi.engineLua) {
          bngApi.engineLua('setClipboard("' + text + '")')
        }
      }
      scope.$on('BeamNGEarthEnduroState', function (event, data) {
        if (disposed || !data || typeof data.state !== 'string') return
        lastMessage = Date.now()
        scope.$evalAsync(function () { if (!disposed) scope.data = data })
      })
      mount(true)
      var heartbeat = setInterval(function () {
        if (disposed) return
        mount(true)
        if (Date.now() - lastMessage > 6000) {
          scope.$evalAsync(function () {
            if (disposed) return
            scope.data = {
              state: 'EARTH_UNAVAILABLE', stateLabel: 'WAITING FOR THE RALLY', saveAllowed: false,
              sessionStatus: 'The rally mod is not responding. Check that the mod is enabled, then reload it.'
            }
          })
        }
      }, 3000)
      scope.$on('$destroy', function () {
        disposed = true
        clearInterval(heartbeat)
        mount(false)
      })
    }
  }
}])
