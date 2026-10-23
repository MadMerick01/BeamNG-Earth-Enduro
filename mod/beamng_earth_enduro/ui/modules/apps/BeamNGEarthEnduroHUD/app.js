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
      // The briefing stays hidden for the rest of the session once the player dismisses it.
      scope.briefingDismissed = false
      scope.dismissBriefing = function () { scope.briefingDismissed = true }
      // Each part of the HUD sits on its own tab so the app stays short.
      scope.tabs = [
        { id: 'stage', label: 'Stage' }, { id: 'nav', label: 'Navigation' },
        { id: 'parts', label: 'Parts' }, { id: 'car', label: 'New Car' },
        { id: 'repair', label: 'Repair' }, { id: 'tips', label: 'Tips' }
      ]
      scope.tab = 'stage'
      scope.setTab = function (id) { scope.tab = id }
      // Marks a tab that has something waiting for the player.
      var alerts = {
        nav: function (d) { return !!d.resume },
        parts: function (d) { return !!d.partsChange },
        car: function (d) { return !!d.carChange },
        repair: function (d) { return !!d.wreck || d.repairOwed > 0 }
      }
      scope.tabAlert = function (id) { return !!alerts[id] && alerts[id](scope.data || {}) }
      // Opens a tab when its bill, wreck or coordinates first appear; the player can switch away after.
      var autoOpen = [
        ['repair', function (d) { return !!d.wreck }], ['car', alerts.car],
        ['parts', alerts.parts], ['nav', alerts.nav]
      ]
      var follow = function (previous, next) {
        for (var i = 0; i < autoOpen.length; i++) {
          if (autoOpen[i][1](next) && !autoOpen[i][1](previous)) { scope.tab = autoOpen[i][0]; return }
        }
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
      scope.buyCar = function () {
        if (scope.data.buyCarAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.buyCar() end')
      }
      scope.revertCar = function () {
        if (scope.data.revertCarAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.revertCar() end')
      }
      scope.revertParts = function () {
        if (scope.data.revertPartsAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.revertParts() end')
      }
      scope.restartStage = function () {
        if (scope.data.restartAllowed) call('if beamngEarthEnduro_core then beamngEarthEnduro_core.restartStage() end')
      }
      // Stage clock: h:mm:ss of the size of a number of seconds; the sign is shown by the caller.
      scope.clock = function (seconds) {
        if (typeof seconds !== 'number' || !isFinite(seconds)) return '-:--:--'
        var total = Math.floor(Math.abs(seconds))
        var pad = function (n) { return (n < 10 ? '0' : '') + n }
        return Math.floor(total / 3600) + ':' + pad(Math.floor(total / 60) % 60) + ':' + pad(total % 60)
      }
      scope.pace = function (seconds) {
        if (typeof seconds !== 'number' || !isFinite(seconds)) return ''
        return (seconds > 0 ? '+' : (seconds < 0 ? '\u2212' : '')) + Math.abs(seconds) + ' s'
      }
      scope.paceColor = function (seconds) { return seconds > 0 ? '#6fcf97' : (seconds < 0 ? '#eb5757' : '#f2f6f5') }
      // Green with time in hand, amber in the last tenth of the limit, red in overtime.
      scope.timerColor = function (timer) {
        if (!timer) return '#a7e5c9'
        if (timer.remainingSeconds < 0) return '#eb5757'
        if (timer.remainingSeconds < timer.targetSeconds * 0.1) return '#f2c94c'
        return '#a7e5c9'
      }
      scope.timerLabel = function (d) {
        var t = d.timer || {}
        if (d.stageFinished) return t.remainingSeconds < 0 ? 'FINISHED OVER THE LIMIT BY' : 'FINISHED WITH TIME TO SPARE'
        if (t.remainingSeconds < 0) return 'OVERTIME'
        return t.started ? 'TIME LEFT' : 'TIME LIMIT'
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
        scope.$evalAsync(function () {
          if (disposed) return
          follow(scope.data || {}, data)
          scope.data = data
        })
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
