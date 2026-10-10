#!/usr/bin/env python3
"""Write a small, deterministic Finder icon layout using only Python's stdlib.

Single-leaf DS_Store format; no Finder automation or installed packaging tools.
Format reference: https://github.com/dmgbuild/ds_store (MIT), see THIRD_PARTY.md.
"""
import pathlib
import plistlib
import struct
import sys


def pack(*values):
    return struct.pack('>' + 'I' * len(values), *values)


def entry(name, code, kind, value):
    filename = name.encode('utf-16be')
    prefix = pack(len(filename) // 2) + filename + code.encode('ascii') + kind.encode('ascii')
    if kind == 'blob':
        return prefix + pack(len(value)) + value
    if kind == 'long':
        return prefix + pack(value)
    if kind == 'type':
        return prefix + value.encode('ascii')
    raise ValueError(kind)


def layout(destination):
    window = {'ShowStatusBar': False, 'ShowTabView': False, 'ShowToolbar': False,
              'ShowPathbar': False, 'ShowSidebar': False,
              'WindowBounds': '{{220, 180}, {640, 400}}', 'SidebarWidth': 0}
    icons = {'viewOptionsVersion': 1, 'backgroundType': 1,
             'backgroundColorRed': 0.92, 'backgroundColorGreen': 0.96,
             'backgroundColorBlue': 1.0, 'gridOffsetX': 0.0, 'gridOffsetY': 0.0,
             'gridSpacing': 100.0, 'arrangeBy': 'none', 'iconSize': 96.0,
             'textSize': 14.0, 'labelOnBottom': True, 'showItemInfo': False,
             'showIconPreview': False, 'scrollPositionX': 0.0, 'scrollPositionY': 0.0}
    records = [('.', 'bwsp', 'blob', plistlib.dumps(window, fmt=plistlib.FMT_BINARY)),
               ('.', 'icvp', 'blob', plistlib.dumps(icons, fmt=plistlib.FMT_BINARY)),
               ('.', 'vSrn', 'long', 1), ('.', 'vstl', 'type', 'icnv'),
               ('SleepGuard.app', 'Iloc', 'blob', pack(180, 185, 0xffffffff, 0xffff0000)),
               ('Applications', 'Iloc', 'blob', pack(460, 185, 0xffffffff, 0xffff0000))]
    records.sort(key=lambda item: (item[0].lower(), item[1]))
    leaf = pack(0, len(records)) + b''.join(entry(*record) for record in records)
    assert len(leaf) <= 4096
    # Buddy allocator: header, 32-byte superblock, 2048-byte allocator,
    # and 4096-byte B-tree leaf. Block addresses exclude the initial 4 bytes.
    allocator = pack(3, 0, 2048 | 11, 32 | 5, 4096 | 12) + pack(*([0] * 253))
    allocator += pack(1) + b'\x04DSDB' + pack(1)
    for width in range(32):
        free = [1 << width] if 6 <= width <= 10 or 13 <= width <= 30 else []
        allocator += pack(len(free), *free)
    output = bytearray(8196)
    output[:36] = struct.pack('>I4sIII16s', 1, b'Bud1', 2048, 2048, 2048,
                             bytes.fromhex('0000100c000000870000200b00000000'))
    output[36:56] = pack(2, 0, len(records), 1, 4096)
    output[2052:2052 + len(allocator)] = allocator
    output[4100:4100 + len(leaf)] = leaf
    pathlib.Path(destination).write_bytes(output)

if __name__ == '__main__':
    layout(sys.argv[1])
