#!/usr/bin/env python3
"""Read-only check of Enduro's source fingerprints against an Earth checkout."""
import argparse
from pathlib import Path

from lupa.luajit21 import LuaRuntime


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('earth_checkout', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    source = args.earth_checkout / 'mod' / 'beamng_earth' / 'lua' / 'ge' / 'extensions' / 'beamngEarth'
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().moduleRoot = str(root / 'mod' / 'beamng_earth_enduro' / 'lua' / 'ge' / 'extensions')
    lua.execute("package.path = moduleRoot .. '/?.lua;' .. package.path")
    checker = lua.eval("require('beamngEarthEnduro/compatibility').check")

    def read(path):
        prefix = '/lua/ge/extensions/beamngEarth/'
        if not path.startswith(prefix) or '/' in path[len(prefix):]:
            raise ValueError('Unexpected source path')
        return (source / path[len(prefix):]).read_text(encoding='utf-8')

    ok, detail = checker(read)
    if not ok:
        raise SystemExit(f'Incompatible: {detail}')
    print(f'Pinned source check passed: {detail}')
    ok, _ = checker(lambda path: read(path).replace('\n', '\r\n'))
    if not ok:
        raise SystemExit('CRLF normalization check failed')
    print('Windows CRLF normalization passed.')


if __name__ == '__main__':
    main()
