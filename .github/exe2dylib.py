#!/usr/bin/env python3
"""exe -> dylib converter (dylibify replacement). Needs: pip install lief."""
import sys

def main(src, dst, install_name):
    import lief
    b = lief.parse(src)
    if b is None:
        print(f"error: cannot parse {src}", file=sys.stderr)
        return 1
    b.header.file_type = lief.MachO.Header.FILE_TYPE.DYLIB
    b.add(lief.MachO.DylibCommand.id_dylib(install_name, 0, 1, 2))
    b.write(dst)
    print(f"converted {src} -> {dst} ({install_name})")
    return 0

if __name__ == "__main__":
    if len(sys.argv) != 4:
        print(f"usage: {sys.argv[0]} <src> <dst> <install-name>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3]))
