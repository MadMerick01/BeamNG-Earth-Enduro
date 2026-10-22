"""Filesystem/JSON and exported game-hook tests. BeamNG engine APIs are stubs."""
import json
import tempfile
import unittest
from pathlib import Path

from lupa.luajit21 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / 'mod' / 'beamng_earth_enduro'


class InstalledHooksTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.user = Path(self.temp.name)
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        g = self.lua.globals()
        g.sourceRoot, g.testsRoot = str(MOD / 'lua' / 'ge' / 'extensions'), str(ROOT / 'tests')
        g.pyRead, g.pyWrite = self.read_json, self.write_json
        g.pyExists = lambda p: self.path(p).is_file()
        g.pyDirExists = lambda p: self.path(p).is_dir()
        g.pyMkdir = lambda p: self.path(p).mkdir(parents=True, exist_ok=True)
        g.bootScript = str(MOD / 'scripts' / 'beamngEarthEnduro' / 'modScript.lua')
        self.lua.execute('''
          package.path = sourceRoot .. '/?.lua;' .. testsRoot .. '/?.lua;' .. package.path
          local F = require('fixtures')
          fakeEarth = F.adapter()
          package.loaded['beamngEarthEnduro/earthAdapter'] = { new = function() return fakeEarth end }
          FS = {
            fileExists = function(_, p) return pyExists(p) end,
            directoryExists = function(_, p) return pyDirExists(p) end,
            directoryCreate = function(_, p) pyMkdir(p); return true end,
          }
          jsonReadFile = function(p) return pyRead(p) end
          jsonWriteFile = function(p, data) return pyWrite(p, data) end
          log = function() end
          notifications = 0
          guihooks = { trigger = function() notifications = notifications + 1 end }
          setExtensionUnloadMode = function(name, mode) registeredName, registeredMode = name, mode end
          dofile(bootScript)
          beamngEarthEnduro_core = require('beamngEarthEnduro/core')
        ''')
        self.core = g.beamngEarthEnduro_core
        self.partial_write = False

    def path(self, virtual):
        self.assertTrue(virtual.startswith('/settings/beamngEarthEnduro/'))
        result = (self.user / virtual.lstrip('/')).resolve()
        self.assertTrue(result.is_relative_to(self.user))
        return result

    def to_lua(self, value):
        if isinstance(value, dict):
            return self.lua.table_from({k: self.to_lua(v) for k, v in value.items()})
        return value

    def from_lua(self, value):
        if hasattr(value, 'items'):
            return {k: self.from_lua(v) for k, v in value.items()}
        return value

    def read_json(self, path):
        file = self.path(path)
        if not file.exists():
            return None
        return self.to_lua(json.loads(file.read_text()))

    def write_json(self, path, value):
        if self.partial_write:
            self.path(path).write_text('{"schemaVersion":')
            return False
        self.path(path).write_text(json.dumps(self.from_lua(value), allow_nan=False))
        return None  # Exercise the engine's potentially nil success return plus read-back verification.

    def configure(self, latitude=0, longitude=0):
        file = self.path('/settings/beamngEarthEnduro/config.json')
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(json.dumps({'base': {'latitude': latitude, 'longitude': longitude}}))

    def arrive(self):
        self.core.onPreRender(0.1)
        self.assertEqual(self.core.getState()['state'], 'READY')

    def test_loader_uses_default_base_without_configuration_or_writes(self):
        self.assertEqual(self.lua.globals().registeredName, 'beamngEarthEnduro_core')
        self.assertEqual(self.lua.globals().registeredMode, 'manual')
        self.core.onExtensionLoaded()
        state = self.core.getState()
        self.assertEqual(state['state'], 'START_LOCATION_REQUIRED')
        self.assertEqual(state['base']['latitude'], -33.60147222)
        self.assertEqual(state['base']['longitude'], 150.82288889)
        self.assertEqual(state['radiusMetres'], 50)
        self.assertFalse(self.core.save())
        self.lua.execute('fakeEarth.pose = {latitude=-33.60147222, longitude=150.82288889}')
        self.arrive()
        self.assertFalse(list(self.user.rglob('save-*.json')))
        self.assertFalse(self.path('/settings/beamngEarthEnduro/config.json').exists())

    def test_default_profile_save_restart_and_changed_resume_preserve_base(self):
        self.core.onExtensionLoaded()
        self.lua.execute('fakeEarth.pose = {latitude=-33.60147222, longitude=150.82288889}')
        self.arrive()
        self.lua.execute('fakeEarth.pose = {latitude=-33.7, longitude=150.9}')
        self.core.onPreRender(0.1)
        self.assertTrue(self.core.save())
        original = self.path('/settings/beamngEarthEnduro/save-a.json').read_bytes()
        self.core.onExtensionUnloaded()
        self.core.onExtensionLoaded()
        state = self.core.getState()
        self.assertEqual(state['state'], 'RESUME_REQUIRED')
        self.assertEqual(state['base']['latitude'], -33.60147222)
        self.assertEqual(state['target']['latitude'], -33.7)
        self.assertEqual(state['target']['longitude'], 150.9)
        self.assertEqual(original, self.path('/settings/beamngEarthEnduro/save-a.json').read_bytes())
        self.assertFalse(self.path('/settings/beamngEarthEnduro/config.json').exists())

    def test_existing_profile_without_configuration_preserves_original_base_and_files(self):
        self.configure(0, 0)
        self.core.onExtensionLoaded()
        self.arrive()
        self.assertTrue(self.core.save())
        original = self.path('/settings/beamngEarthEnduro/save-a.json').read_bytes()
        self.path('/settings/beamngEarthEnduro/config.json').unlink()
        self.core.onExtensionUnloaded()
        self.core.onExtensionLoaded()
        state = self.core.getState()
        self.assertEqual(state['state'], 'RESUME_REQUIRED')
        self.assertEqual(state['base']['latitude'], 0)
        self.assertEqual(state['base']['longitude'], 0)
        self.assertEqual(original, self.path('/settings/beamngEarthEnduro/save-a.json').read_bytes())

    def test_existing_override_is_used_without_modifying_its_bytes(self):
        self.configure(10, 20)
        original = self.path('/settings/beamngEarthEnduro/config.json').read_bytes()
        self.core.onExtensionLoaded()
        state = self.core.getState()
        self.assertEqual(state['base']['latitude'], 10)
        self.assertEqual(state['base']['longitude'], 20)
        self.assertEqual(original, self.path('/settings/beamngEarthEnduro/config.json').read_bytes())

    def test_first_launch_save_restart_and_fixed_base(self):
        self.configure()
        self.core.onExtensionLoaded()
        self.assertEqual(self.core.getState()['state'], 'START_LOCATION_REQUIRED')
        self.arrive()
        self.lua.execute('fakeEarth.pose = {latitude=1, longitude=2}')
        self.core.onPreRender(0.1)
        self.assertTrue(self.core.save())
        saved = json.loads(self.path('/settings/beamngEarthEnduro/save-a.json').read_text())
        self.assertEqual(saved['resume'], {'latitude': 1, 'longitude': 2})
        self.assertEqual(saved['base'], {'latitude': 0, 'longitude': 0})
        self.assertEqual(saved['vehicle']['model'], 'pickup')
        self.core.onExtensionUnloaded()
        self.core.onExtensionLoaded()
        self.assertEqual(self.core.getState()['state'], 'RESUME_REQUIRED')
        self.assertFalse(self.core.save())
        self.arrive()
        self.lua.execute('fakeEarth.pose = {latitude=3, longitude=4}')
        self.core.onPreRender(0.1)
        self.assertTrue(self.core.save())
        second = json.loads(self.path('/settings/beamngEarthEnduro/save-b.json').read_text())
        self.assertEqual(second['generation'], 2)
        self.assertEqual(second['resume']['latitude'], 3)
        self.assertEqual(second['base']['latitude'], 0)
        self.configure(20, 30)
        self.core.onFilesChanged(self.to_lua({1: {'filename': '/settings/beamngEarthEnduro/config.json'}}))
        self.assertEqual(self.core.getState()['state'], 'RESUME_REQUIRED')
        self.assertEqual(self.core.getState()['base']['latitude'], 0)

    def test_partial_disk_write_recovers_previous_generation(self):
        self.configure()
        self.core.onExtensionLoaded()
        self.arrive()
        self.assertTrue(self.core.save())
        original = self.path('/settings/beamngEarthEnduro/save-a.json').read_bytes()
        self.partial_write = True
        self.assertFalse(self.core.save())
        self.assertEqual(self.core.getState()['state'], 'ERROR')
        self.assertEqual(original, self.path('/settings/beamngEarthEnduro/save-a.json').read_bytes())
        self.core.onExtensionUnloaded()
        self.core.onExtensionLoaded()
        self.assertEqual(self.core.getState()['state'], 'RESUME_REQUIRED')
        self.assertIn('Recovered', self.core.getState()['saveFeedback'])

    def test_mission_end_locks_saving_without_implicit_writes(self):
        self.configure()
        self.core.onExtensionLoaded()
        self.arrive()
        self.core.uiMounted(True)
        self.core.onPreRender(0.1)
        self.assertGreater(self.lua.globals().notifications, 0)
        self.core.onClientEndMission()
        self.assertEqual(self.core.getState()['state'], 'EARTH_UNAVAILABLE')
        self.assertFalse(self.core.save())
        self.assertFalse(list(self.user.rglob('save-*.json')))


if __name__ == '__main__':
    unittest.main()
