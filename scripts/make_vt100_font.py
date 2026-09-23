#!/usr/bin/env python3
"""
Build app/qml/fonts/dec-vt100/DEC-VT100.ttf from the VT100 character
generator ROM (DEC part 23-018E2), reproducing what the terminal put on
screen in 80-column mode rather than the raw ROM bits.
Requires fontTools.
"""
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import newTable
from fontTools.ttLib.tables.O_S_2f_2 import Panose
from fontTools.ttLib.tables.ttProgram import Program

FONT_DIR = Path(__file__).resolve().parents[1] / "app" / "qml" / "fonts" / "dec-vt100"
ROM_PATH = FONT_DIR / "23-018E2.bin"
OUT_PATH = FONT_DIR / "DEC-VT100.ttf"

FAMILY = "DEC VT100"

CELL = 10
# A power-of-two multiple keeps FreeType's 16.16 scale factor exact at the
# native 10px size; with 100 units per pixel advances come out as 9.984px.
PIXEL = 128
UPEM = CELL * PIXEL
# Row 0 is the blank scan line above capitals; rows 8-9 hold descenders.
ASCENT_ROWS = 8

# ROM slots 0x01-0x1F hold the DEC Special Graphics glyphs, which the
# terminal shows for 0x60-0x7E when that set is selected. Map them to their
# Unicode equivalents so programs emitting box drawing etc. get ROM glyphs.
SPECIAL_GRAPHICS = {
    0x01: [0x25C6],          # diamond
    0x02: [0x2592],          # checkerboard
    0x03: [0x2409],          # HT
    0x04: [0x240C],          # FF
    0x05: [0x240D],          # CR
    0x06: [0x240A],          # LF
    0x07: [0x00B0],          # degree
    0x08: [0x00B1],          # plus/minus
    0x09: [0x2424],          # NL
    0x0A: [0x240B],          # VT
    0x0B: [0x2518],          # lower right corner
    0x0C: [0x2510],          # upper right corner
    0x0D: [0x250C],          # upper left corner
    0x0E: [0x2514],          # lower left corner
    0x0F: [0x253C],          # crossing lines
    0x10: [0x23BA],          # scan line 1
    0x11: [0x23BB],          # scan line 3
    0x12: [0x2500],          # scan line 5 / horizontal line
    0x13: [0x23BC],          # scan line 7
    0x14: [0x23BD],          # scan line 9
    0x15: [0x251C],          # left tee
    0x16: [0x2524],          # right tee
    0x17: [0x2534],          # bottom tee
    0x18: [0x252C],          # top tee
    0x19: [0x2502],          # vertical line
    0x1A: [0x2264],          # less than or equal
    0x1B: [0x2265],          # greater than or equal
    0x1C: [0x03C0],          # pi
    0x1D: [0x2260],          # not equal
    0x1E: [0x00A3],          # pound sterling
    0x1F: [0x00B7],          # centered dot
}


def rom_rows(rom: bytes, index: int) -> list[int]:
    """Return the 10 displayed scan lines of a ROM glyph, top to bottom."""
    glyph = rom[index * 16:(index + 1) * 16]
    # The video counter starts each character row at ROM line 15, so that
    # line is the topmost scan line on screen, followed by lines 0-8.
    return [glyph[15]] + list(glyph[0:9])


def displayed_pixels(row: int) -> list[bool]:
    """Expand one 8-bit ROM line into the 10 dots shown in 80-column mode."""
    bits = [bool(row & (0x80 >> i)) for i in range(8)]
    # The last bit is only set in line-drawing glyphs; repeating it into the
    # two extra columns makes horizontal lines join across cells.
    bits += [bits[7], bits[7]]
    # Dot stretching: the video circuit holds each lit dot for one extra dot
    # time, so strokes are two dots wide on screen.
    return [bits[x] or (x > 0 and bits[x - 1]) for x in range(CELL)]


def draw_glyph(rows: list[int]):
    pen = TTGlyphPen(None)
    for r, row in enumerate(rows):
        pixels = displayed_pixels(row)
        top = (ASCENT_ROWS - r) * PIXEL
        bottom = top - PIXEL
        # One rectangle per horizontal run keeps the outline count small.
        x = 0
        while x < CELL:
            if not pixels[x]:
                x += 1
                continue
            start = x
            while x < CELL and pixels[x]:
                x += 1
            left, right = start * PIXEL, x * PIXEL
            pen.moveTo((left, bottom))
            pen.lineTo((left, top))
            pen.lineTo((right, top))
            pen.lineTo((right, bottom))
            pen.closePath()
    return pen.glyph()


def main() -> None:
    rom = ROM_PATH.read_bytes()
    if len(rom) != 2048:
        raise SystemExit(f"{ROM_PATH}: expected 2048 bytes, got {len(rom)}")

    glyph_order = [".notdef"]
    glyphs = {".notdef": TTGlyphPen(None).glyph()}
    cmap = {}

    def add(name: str, rom_index: int, codepoints: list[int]) -> None:
        glyph_order.append(name)
        glyphs[name] = draw_glyph(rom_rows(rom, rom_index))
        for cp in codepoints:
            cmap[cp] = name

    add("space", 0x20, [0x20, 0xA0])
    for code in range(0x21, 0x7F):
        add(f"uni{code:04X}", code, [code])
    for index, codepoints in SPECIAL_GRAPHICS.items():
        add(f"uni{codepoints[0]:04X}", index, codepoints)

    fb = FontBuilder(UPEM, isTTF=True)
    fb.setupGlyphOrder(glyph_order)
    fb.setupCharacterMap(cmap)
    fb.setupGlyf(glyphs)
    # The left side bearing must equal each glyph's xMin: the bytecode
    # interpreter positions outlines from it, so a zero bearing slides glyphs
    # with a blank left edge (l, i, I, 1, ...) left by that many pixels.
    fb.setupHorizontalMetrics({
        name: (UPEM, min((x for x, _ in glyphs[name].getCoordinates(None)[0]), default=0))
        for name in glyph_order
    })
    descent = (CELL - ASCENT_ROWS) * PIXEL
    fb.setupHorizontalHeader(ascent=ASCENT_ROWS * PIXEL, descent=-descent)
    fb.setupNameTable({
        "familyName": FAMILY,
        "styleName": "Regular",
        "uniqueFontIdentifier": f"{FAMILY} Regular",
        "fullName": FAMILY,
        "psName": FAMILY.replace(" ", "") + "-Regular",
        "version": "Version 1.0",
    })
    # Fontconfig and Qt use the PANOSE proportion to classify monospace fonts.
    panose = Panose()
    panose.bFamilyType = 2
    panose.bProportion = 9
    fb.setupOS2(
        sTypoAscender=ASCENT_ROWS * PIXEL,
        sTypoDescender=-descent,
        sTypoLineGap=0,
        usWinAscent=ASCENT_ROWS * PIXEL,
        usWinDescent=descent,
        panose=panose,
        xAvgCharWidth=UPEM,
    )
    fb.setupPost(isFixedPitch=1)
    # FreeType treats a TrueType font with no fpgm program as unhinted and
    # runs its autohinter, which snaps thin glyphs like the checkerboard and
    # diamond toward the letter blue zones and doubles 1-pixel lines. A no-op
    # fpgm selects the bytecode interpreter instead, which with no glyph
    # instructions leaves these grid-aligned outlines exactly as drawn.
    fpgm = newTable("fpgm")
    fpgm.program = Program()
    fpgm.program.fromAssembly(["PUSHB[ ]", "0", "POP[ ]"])
    fb.font["fpgm"] = fpgm
    # fontTools never recalculates the instruction limits in maxp.
    fb.font["maxp"].maxSizeOfInstructions = len(fpgm.program.getBytecode())
    fb.save(str(OUT_PATH))
    print(f"Wrote {OUT_PATH} ({len(glyph_order)} glyphs)")


if __name__ == "__main__":
    main()
