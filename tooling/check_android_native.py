#!/usr/bin/env python3
"""Inspect 64-bit ELF LOAD alignment in an APK/AAB before release.

Also reports upstream RELRO boundaries separately; run the camera on a 16 KB
emulator with backcompat disabled. This static check cannot prove runtime safety.
APK ZIP alignment/signatures must additionally pass Android's zipalign/apksigner.
"""
import argparse
import struct
import zipfile


def inspect(path):
    failures, warnings, checked = [], [], 0
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.endswith('.so') or not any('/' + abi + '/' in name for abi in ('arm64-v8a', 'x86_64')):
                continue
            checked += 1
            data = archive.read(name)
            if data[:6] != b'\x7fELF\x02\x01':
                failures.append(name + ': expected little-endian ELF64')
                continue
            offset = struct.unpack_from('<Q', data, 32)[0]
            size, count = struct.unpack_from('<HH', data, 54)
            loads = []
            for index in range(count):
                kind, _, _, virtual, _, _, memory, alignment = struct.unpack_from('<IIQQQQQQ', data, offset + index * size)
                if kind == 1:
                    loads.append(alignment)
                if kind == 0x6474e552 and (virtual + memory) % 16384:
                    warnings.append(name + ': upstream RELRO end is not 16 KB aligned; retain runtime coverage')
            if not loads or min(loads) < 16384:
                failures.append(name + ': LOAD alignment below 16 KB')
    if not checked:
        failures.append('No 64-bit native libraries found')
    for warning in warnings:
        print('REVIEW:', warning)
    for failure in failures:
        print('FAIL:', failure)
    print(f'{checked} native libraries inspected; {len(failures)} LOAD alignment failures; {len(warnings)} RELRO advisories')
    return not failures


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact')
    args = parser.parse_args()
    raise SystemExit(0 if inspect(args.artifact) else 1)
