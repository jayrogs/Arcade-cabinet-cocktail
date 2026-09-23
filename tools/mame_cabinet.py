#!/usr/bin/env python3
"""Where a game's table switch sits in MAME 2003-Plus, read from MAME's own source.

MAME keeps each game's controls and switches as one list in the order its source
writes them. The table switch is the one named Cabinet. This finds the game, its list,
and counts the switches in order -- the same count mamecfg.py needs -- and says which
way up the game's picture is stored.

    python3 mame_cabinet.py dkong        prints: dkong 4 80 ROT270
"""
import glob, json, os, re, sys

SRC = glob.glob(os.path.expanduser("~/.cache/m2k3/*/src/drivers"))[0]
GAME = re.compile(r"^\s*GAME\w*\s*\(\s*\d+\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,\s*(\w+)\s*,"
                  r"\s*(\w+)\s*,\s*(ROT\d+|ORIENTATION_\w+)", re.M)


def clean(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


FILES = {}
GAMES = {}
for path in glob.glob(SRC + "/*.c"):
    text = clean(open(path, encoding="latin-1").read())
    FILES[path] = text
    for m in GAME.finditer(text):
        GAMES[m.group(1)] = (path, m.group(4), m.group(6))


def macros(text):
    """#define NAME ... with backslash-continued lines, so a shared block of switches
    written once and used by several games can be read in place."""
    out = {}
    joined = text.replace(chr(92) + chr(10), chr(10) + "@@")   # mark continued lines
    for m in re.finditer(r"^[ \t]*#define[ \t]+(\w+)[ \t]*(.*(?:\n@@.*)*)", joined, re.M):
        out[m.group(1)] = m.group(2).replace("@@", "")
    return out


def ports_block(name):
    for path, text in FILES.items():
        m = re.search(r"INPUT_PORTS_START\(\s*%s\s*\)(.*?)INPUT_PORTS_END" % re.escape(name), text, re.S)
        if m:
            defs = macros(text)
            lines = []
            for line in m.group(1).splitlines():
                word = line.strip()
                if word in defs:                 # a shared block: read what it holds
                    lines += defs[word].splitlines()
                else:
                    lines.append(line)
            return chr(10).join(lines)
    return None


def cabinet(game):
    if game not in GAMES:
        return {"error": "MAME does not know this game"}
    path, ports, rot = GAMES[game]
    block = ports_block(ports)
    if block is None:
        return {"error": "no switch list called %s" % ports}
    k = 0
    unsure = []
    lines = block.splitlines()
    for n, line in enumerate(lines):
        s = line.strip()
        if not s:
            continue
        is_switch = (s.startswith("PORT_DIPNAME") or
                     (s.startswith("PORT_SERVICE") and not s.startswith("PORT_SERVICE_NO_TOGGLE")) or
                     (s.startswith("PORT_BITX") and "IPT_DIPSWITCH_NAME" in s))
        if is_switch:
            k += 1
            if re.search(r"Cabinet", s, re.I):
                m = re.match(r"PORT_DIPNAME\s*\(\s*(0x[0-9a-fA-F]+|\d+)\s*,\s*(0x[0-9a-fA-F]+|\d+)", s)
                mask = int(m.group(1), 0) if m else None
                # which setting is the cocktail one, from the settings that follow
                cocktail = None
                for nxt in lines[n + 1:n + 8]:
                    t = nxt.strip()
                    if not t:
                        continue             # a commented-out setting leaves a blank line
                    if not t.startswith("PORT_DIPSETTING"):
                        break
                    v = re.match(r"PORT_DIPSETTING\s*\(\s*(0x[0-9a-fA-F]+|\d+)", t)
                    if v and re.search(r"Cocktail", t, re.I):
                        cocktail = int(v.group(1), 0)
                return {"switch": k, "mask": mask, "cocktail": cocktail, "rot": rot,
                        "ports": ports, "file": os.path.basename(path), "unsure": unsure}
        elif not s.startswith(("PORT_", "INPUT_PORTS")) and re.match(r"^[A-Z_0-9]+\s*(\(|$)", s):
            unsure.append(s[:40])          # a macro that may hide more switches
    return {"error": "no Cabinet switch", "rot": rot}


if __name__ == "__main__":
    out = {g: cabinet(g) for g in sys.argv[1:]}
    if len(sys.argv) == 2:
        print(json.dumps(out[sys.argv[1]]))
    else:
        print(json.dumps(out, indent=1))
