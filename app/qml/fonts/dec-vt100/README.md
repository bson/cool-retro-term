# DEC VT100

`DEC-VT100.ttf` is generated from `23-018E2.bin`, a dump of the DEC VT100
character generator ROM (US ASCII set), by `scripts/make_vt100_font.py`.
Regenerate it with that script rather than editing the TTF.

The glyphs reproduce the terminal's 80-column output rather than the raw ROM
bits: each character is a 10x10 cell, the last ROM column is repeated into the
two extra columns, and every lit dot is stretched one dot to the right, as the
VT100 video circuit did. The DEC Special Graphics glyphs in the ROM are mapped
to their Unicode equivalents (box drawing, scan lines, symbols).

The ROM image is DEC's original data, obtained from the PCjs VT100 ROM
collection (https://www.pcjs.org/machines/dec/vt100/rom/) and cross-checked
against an independent dump. No license is stated for it.
