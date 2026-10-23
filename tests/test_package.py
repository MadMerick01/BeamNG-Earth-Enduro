"""Validate the distributed layout/assets, not just the development checkout."""
import hashlib
import json
import struct
import tempfile
import unittest
import zlib
from pathlib import Path
from zipfile import ZipFile

from lupa.luajit21 import LuaRuntime

from tools.package import build


class PackageTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.output = build(Path(self.temp.name) / 'enduro.zip')

    def test_archive_layout_is_standalone_and_excludes_user_data(self):
        with ZipFile(self.output) as archive:
            names = set(archive.namelist())
            self.assertIn('scripts/beamngEarthEnduro/modScript.lua', names)
            self.assertIn('lua/ge/extensions/beamngEarthEnduro/core.lua', names)
            self.assertIn('ui/modules/apps/BeamNGEarthEnduroHUD/app.json', names)
            self.assertIn('README.md', names)
            self.assertIn('docs/TASK-004-mileage.md', names)
            self.assertIn('docs/TASK-003-simplified-checks.md', names)
            self.assertIn('docs/TASK-002-testing.md', names)
            self.assertIn('docs/TASK-002-architecture.md', names)
            self.assertFalse(any(n.startswith(('settings/', 'tests/', 'beamng_earth_enduro/', 'docs/beamng-api/')) for n in names))
            self.assertFalse(any('save-a.json' in n or 'save-b.json' in n or n.endswith('.pyc') for n in names))
            self.assertIsNone(archive.testzip())

    def test_manifest_configuration_and_app_assets_are_consistent(self):
        prefix = 'ui/modules/apps/BeamNGEarthEnduroHUD/'
        with ZipFile(self.output) as archive:
            manifest = json.loads(archive.read(prefix + 'app.json'))
            config = json.loads(archive.read('config.example.json'))
            self.assertEqual(manifest['appName'], 'BeamNGEarthEnduroHUD')
            self.assertEqual(manifest['name'], 'World Ironman Enduro Rally')
            self.assertEqual(manifest['directive'], 'beamngEarthEnduroHud')
            self.assertIn('beamng-earth-enduro-hud', manifest['domElement'])
            self.assertEqual(config['base']['latitude'], 34.224032)
            self.assertEqual(config['base']['longitude'], 75.029787)
            self.assertIn(b'/ui/modules/apps/BeamNGEarthEnduroHUD/app.html', archive.read(prefix + 'app.js'))
            self.assertIn(b'WORLD IRONMAN ENDURO RALLY', archive.read(prefix + 'app.html'))
            self.assertIn(b'beamngEarthEnduro_core', archive.read('scripts/beamngEarthEnduro/modScript.lua'))

    def test_starter_car_config_is_packaged(self):
        prefix = 'vehicles/burnside/'
        with ZipFile(self.output) as archive:
            config = json.loads(archive.read(prefix + 'worldironmanenduro_starter.pc'))
            info = json.loads(archive.read(prefix + 'info_worldironmanenduro_starter.json'))
            thumbnail = archive.read(prefix + 'worldironmanenduro_starter.jpg')
            core = archive.read('lua/ge/extensions/beamngEarthEnduro/core.lua')
        self.assertEqual(config['model'], 'burnside')
        self.assertEqual(config['mainPartName'], 'burnside')
        self.assertIsInstance(config['parts'], dict)
        self.assertEqual(info['Configuration'], 'WorldIronManEnduro_Starter')
        self.assertEqual(thumbnail[:3], b'\xff\xd8\xff')
        self.assertIn(b"'" + (prefix + 'worldironmanenduro_starter.pc').encode() + b"'", core)

    def test_png_is_complete_with_valid_checksums(self):
        with ZipFile(self.output) as archive:
            data = archive.read('ui/modules/apps/BeamNGEarthEnduroHUD/app.png')
        self.assertEqual(data[:8], b'\x89PNG\r\n\x1a\n')
        offset, ended = 8, False
        while offset < len(data):
            size, = struct.unpack('>I', data[offset:offset + 4])
            kind = data[offset + 4:offset + 8]
            body = data[offset + 8:offset + 8 + size]
            checksum, = struct.unpack('>I', data[offset + 8 + size:offset + 12 + size])
            self.assertEqual(checksum, zlib.crc32(kind + body))
            if kind == b'IHDR':
                self.assertEqual(struct.unpack('>II', body[:8]), (128, 128))
            if kind == b'IEND':
                ended = True
            offset += 12 + size
        self.assertTrue(ended)
        self.assertEqual(offset, len(data))

    def test_packaged_lua_starts_with_default_base_without_user_configuration(self):
        prefix = 'lua/ge/extensions/'
        with ZipFile(self.output) as archive:
            sources = {name[len(prefix):-4]: archive.read(name).decode('utf-8')
                       for name in archive.namelist() if name.startswith(prefix) and name.endswith('.lua')}
        lua = LuaRuntime()
        lua.globals().zipModules = lua.table_from(sources)
        lua.execute('''
          package.path = '' -- Do not allow fallback to the development checkout.
          table.insert(package.loaders, 2, function(name)
            local code = zipModules[name]
            if not code then return '\\nmodule absent from ZIP: ' .. name end
            return assert(loadstring(code, '@ZIP/' .. name .. '.lua'))
          end)
          packagedDefaults = require('beamngEarthEnduro/config').load({
            exists = function() return false end,
            read = function() error('missing configuration must not be read') end,
          })
        ''')
        defaults = lua.globals().packagedDefaults
        self.assertEqual(defaults['base']['latitude'], 34.224032)
        self.assertEqual(defaults['base']['longitude'], 75.029787)
        self.assertEqual(defaults['resumeRadiusMetres'], 50)

    def test_package_is_reproducible(self):
        second = build(Path(self.temp.name) / 'second.zip')
        self.assertEqual(hashlib.sha256(self.output.read_bytes()).digest(),
                         hashlib.sha256(second.read_bytes()).digest())


if __name__ == '__main__':
    unittest.main()
