#!/usr/bin/env python3
"""Puts a game made on this PC onto the cabinet, with everything the shelf needs:
the file, its title, its player count, its place on the two-player list, its cover
and the switch that tells it it is in a table.

Used for the sped-up Pac-Man games, which are his own files with two bytes changed.
"""
import os, sys
import cab

R = "/home/jayrogs/roms/arcade/"

# (file on this PC, short name, title on the shelf, cover to borrow)
GAMES = [
    ("mspacmnf.zip", "mspacmnf", "MS. PAC-MAN - SPED UP", "mspacman"),
    ("pacmanf.zip",  "pacmanf",  "PAC-MAN - SPED UP",     "pacman"),
]


def add_line(sftp, path, line):
    """Adds the line once; a second run changes nothing."""
    with sftp.open(path) as f:
        text = f.read().decode()
    key = line.split("\t")[0]
    for have in text.splitlines():
        if have == line or have.split("\t")[0] == key:
            return False
    if text and not text.endswith("\n"):
        text += "\n"
    with sftp.open(path, "w") as f:
        f.write((text + line + "\n").encode())
    return True


def main(folder):
    c = cab.connect()
    s = c.open_sftp()
    for fname, short, title, cover in GAMES:
        s.put(os.path.join(folder, fname), R + "fbneo/" + fname)
        add_line(s, R + "names.txt", short + "\t" + title)
        add_line(s, R + "players.txt", short + "\t2P alt")
        add_line(s, R + "cocktail.txt", short)
        add_line(s, R + "cocktail2p.txt", short)
        print("sent", short)
    s.close()
    covers = " ; ".join("cp -n %s.png %s.png" % (g[3], g[1]) for g in GAMES)
    print(cab.run(c, "cd ~/roms/arcade/fbneo/media && " + covers +
                  " ; python3 ~/set_cocktail.py", 60))
    c.close()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
