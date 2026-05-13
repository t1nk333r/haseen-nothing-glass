from fontTools.ttLib import TTFont

font = TTFont("sf-icon-font.ttf")
names = font.getGlyphNames()

with open("sf-symbols-list.txt", "w") as f:
    for name in sorted(names):
        f.write(name + "\n")

print(f"Total glyphs: {len(names)}")
