#!/usr/bin/env python3
"""Publish a fully prepared dev bundle without removing its installed path."""
import ctypes
import os
import plistlib
import sys
from pathlib import Path


def replace(source, target, bundle_id):
    source, target = Path(source), Path(target)
    if source.is_symlink() or not source.is_dir():
        raise ValueError("Staged bundle must be a directory, not a symlink")
    with (source / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    if info.get("CFBundleIdentifier") != bundle_id:
        raise ValueError("Refusing to publish a bundle without the Dev identity")
    if target.is_symlink():
        raise ValueError("Refusing to replace a symlink")
    if not target.exists():
        os.rename(source, target)
        return
    if not target.is_dir() or source.resolve() == target.resolve():
        raise ValueError("Installed and staged bundles must be distinct directories")
    # Darwin sys/stdio.h: RENAME_SWAP = 0x00000002. Both paths remain present
    # throughout the exchange. On failure leave the installed copy intact.
    libc = ctypes.CDLL("/usr/lib/libSystem.B.dylib", use_errno=True)
    swap = libc.renamex_np
    swap.argtypes = [ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint]
    swap.restype = ctypes.c_int
    if swap(os.fsencode(source), os.fsencode(target), 0x00000002):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))
    # The old bundle is now at source; the installer's staging cleanup owns it.


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit("Usage: replace-dev-bundle.py STAGED_APP INSTALLED_APP BUNDLE_ID")
    replace(*sys.argv[1:])
