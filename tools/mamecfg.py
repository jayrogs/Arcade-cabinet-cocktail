#!/usr/bin/env python3
"""Reads and changes MAME 2003-Plus's own per-game settings file, for the one switch
that matters on this table: upright or cocktail.

MAME keeps each game's controls and switches in cfg/<game>.cfg, in its own binary
layout (src/config.c): the header, a count, the game's list as its maker set it, the
same list as it is set now, then the key assignments and coin counters. A switch's
current setting lives in the "as it is set now" copy.

    python3 mamecfg.py show pacman
    python3 mamecfg.py cocktail pacman 3     the 3rd switch in the game's list
"""
import os, struct, sys

CFG = os.path.expanduser("~/.config/retroarch/saves/MAME 2003-Plus/mame2003-plus/cfg")
NAME, SETTING = 0x36, 0x37           # a switch, and one of its possible settings


def parse(data):
    assert data[:8] == b"MAMECFG\x09", "not a MAME settings file"
    pos = 8
    total, = struct.unpack(">I", data[pos:pos + 4]); pos += 4
    lists = []
    for _ in range(2):
        entries = []
        for _ in range(total):
            start = pos
            typ, mask, value, n = struct.unpack(">IHHH", data[pos:pos + 10]); pos += 10
            pos += 4 * n
            entries.append({"at": start, "type": typ & 0xff, "mask": mask, "value": value})
        lists.append(entries)
    return lists


def switches(entries):
    """Each switch with the settings that follow it."""
    out = []
    for i, e in enumerate(entries):
        if e["type"] == NAME:
            opts = []
            for f in entries[i + 1:]:
                if f["type"] != SETTING:
                    break
                opts.append(f["value"])
            out.append((i, e, opts))
    return out


def main():
    cmd, game = sys.argv[1], sys.argv[2]
    path = os.path.join(CFG, game + ".cfg")
    data = bytearray(open(path, "rb").read())
    maker, now = parse(bytes(data))
    sw = switches(now)
    if cmd == "show":
        for k, (i, e, opts) in enumerate(sw, 1):
            print("switch %d: mask %02x  now %02x  settings %s" % (k, e["mask"], e["value"],
                                                                  " ".join("%02x" % o for o in opts)))
        return
    if cmd == "cocktail":
        k = int(sys.argv[3])
        i, e, opts = sw[k - 1]
        # upright is the maker's setting; cocktail is the other one of exactly two
        assert len(opts) == 2, "switch %d does not have two settings" % k
        upright = maker[i]["value"]
        cocktail = [o for o in opts if o != upright]
        assert len(cocktail) == 1
        struct.pack_into(">H", data, e["at"] + 6, cocktail[0])
        open(path, "wb").write(bytes(data))
        again = switches(parse(bytes(data))[1])[k - 1][1]["value"]
        print("%s: switch %d was %02x, now %02x (cocktail)" % (game, k, e["value"], again))


def set_value(game, k, value):
    path = os.path.join(CFG, game + ".cfg")
    data = bytearray(open(path, "rb").read())
    i, e, opts = switches(parse(bytes(data))[1])[k - 1]
    assert value in opts, "that value is not one of the switch's settings"
    struct.pack_into(">H", data, e["at"] + 6, value)
    open(path, "wb").write(bytes(data))
    return e["value"]


if __name__ == "__main__":
    main()
