#!/usr/bin/env python3
"""Erzeugt das App-Icon ohne externe Bibliotheken: ein Terminalfenster mit JP-Prompt."""
import zlib, struct, math, sys

N = 1024
BG      = (0x05, 0x09, 0x0b)   # App-Hintergrund
WIN     = (0x0a, 0x12, 0x15)   # Terminalflaeche
BAR     = (0x12, 0x1d, 0x21)   # Titelleiste
GREEN   = (0x3d, 0xff, 0xa8)
DIM     = (0x1d, 0x7a, 0x55)
RED     = (0xff, 0x5f, 0x57)
YEL     = (0xfe, 0xbc, 0x2e)
GRN     = (0x28, 0xc8, 0x40)

R_OUT = N * 0.225          # Eckenradius des App-Icons
M_OUT = N * 0.055          # Rand
WIN_X0, WIN_X1 = N * 0.145, N * 0.855
WIN_Y0, WIN_Y1 = N * 0.215, N * 0.800
R_WIN = N * 0.055
BAR_H = N * 0.085


def rr_dist(x, y, x0, y0, x1, y1, r):
    """Abstand zu einem abgerundeten Rechteck, negativ innerhalb."""
    dx = max(x0 + r - x, 0, x - (x1 - r))
    dy = max(y0 + r - y, 0, y - (y1 - r))
    return math.hypot(dx, dy) - r


def seg_d(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    t = max(0.0, min(1.0, (wx * vx + wy * vy) / (vx * vx + vy * vy + 1e-9)))
    return math.hypot(px - (ax + t * vx), py - (ay + t * vy))


def S(*pts):
    return [(a * N, b * N, c * N, d * N) for a, b, c, d in pts]


# Prompt-Zeichen ">" und die Buchstaben J und P, als Striche
CHEV = S((.225, .400, .300, .470), (.300, .470, .225, .540))
J    = S((.415, .360, .415, .530), (.415, .530, .385, .578), (.385, .578, .337, .572))
P    = S((.505, .360, .505, .585), (.505, .360, .583, .360),
         (.583, .360, .583, .437), (.583, .437, .505, .437))
STROKE = N * 0.026
CUR_X0, CUR_X1 = N * .672, N * .724
CUR_Y0, CUR_Y1 = N * .432, N * .585

# Zwei Ausgabezeilen unter dem Prompt, angedeutet
LINES = [(.225, .655, .560, .655), (.225, .715, .430, .715)]
LINE_W = N * 0.017

DOTS = [(.205, .258, RED), (.258, .258, YEL), (.311, .258, GRN)]
DOT_R = N * 0.019


def clamp01(v):
    return 0.0 if v < 0 else (1.0 if v > 1 else v)


def mix(base, color, a):
    return tuple(int(base[i] + (color[i] - base[i]) * a) for i in range(3))


def render(path):
    buf = bytearray()
    for py in range(N):
        buf.append(0)
        row = bytearray()
        y = py + 0.5
        for px in range(N):
            x = px + 0.5

            # Aussenform
            a_out = clamp01(0.5 - rr_dist(x, y, M_OUT, M_OUT, N - M_OUT, N - M_OUT, R_OUT))
            if a_out <= 0:
                row += b'\x00\x00\x00\x00'
                continue

            r, g, b = BG

            # Terminalfenster
            d_win = rr_dist(x, y, WIN_X0, WIN_Y0, WIN_X1, WIN_Y1, R_WIN)
            a_win = clamp01(0.5 - d_win)
            if a_win > 0:
                inside_bar = y < WIN_Y0 + BAR_H
                r, g, b = mix((r, g, b), BAR if inside_bar else WIN, a_win)

            # feiner Rand um das Fenster
            edge = clamp01(1.0 - abs(d_win) / 2.0)
            if edge > 0:
                r, g, b = mix((r, g, b), DIM, edge * 0.85)

            # Ampelpunkte
            for cx, cy, col in DOTS:
                dd = math.hypot(x - cx * N, y - cy * N) - DOT_R
                a = clamp01(0.5 - dd)
                if a > 0:
                    r, g, b = mix((r, g, b), col, a)

            # Prompt-Chevron
            dc = min(seg_d(x, y, *s) for s in CHEV)
            a = clamp01(STROKE * 0.85 - dc + 0.5)
            if a > 0:
                r, g, b = mix((r, g, b), DIM, a)

            # JP
            dj = min(min(seg_d(x, y, *s) for s in J), min(seg_d(x, y, *s) for s in P))
            a = clamp01(STROKE - dj + 0.5)
            if a > 0:
                r, g, b = mix((r, g, b), GREEN, a)

            # Cursorblock
            dcur = rr_dist(x, y, CUR_X0, CUR_Y0, CUR_X1, CUR_Y1, N * 0.008)
            a = clamp01(0.5 - dcur)
            if a > 0:
                r, g, b = mix((r, g, b), GREEN, a)

            # angedeutete Ausgabezeilen
            for lx0, ly, lx1, _ in LINES:
                dl = seg_d(x, y, lx0 * N, ly * N, lx1 * N, ly * N)
                a = clamp01(LINE_W - dl + 0.5)
                if a > 0:
                    r, g, b = mix((r, g, b), DIM, a * 0.75)

            row += bytes((r, g, b, int(a_out * 255)))
        buf += row

    def chunk(t, d):
        c = t + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(bytes(buf), 6))
           + chunk(b'IEND', b''))
    open(path, 'wb').write(png)
    print("Icon:", N, "x", N)


if __name__ == "__main__":
    render(sys.argv[1])
