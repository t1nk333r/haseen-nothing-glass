.pragma library

// Dot-matrix glyph patterns: one string per row, one character per dot.
// "0", " " and "." leave the dot unlit; anything else lights it.
//
// 5x7 digits, which is the smallest grid where a 4 and a 9 are still
// unmistakable at a glance - 3x5 saves eight dots per digit and costs you
// the ability to read a clock across a room.
var DIGITS = {
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
    "3": ["11111", "00010", "00100", "00010", "00001", "10001", "01110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
    ":": ["000", "010", "010", "000", "010", "010", "000"],
    ".": ["00", "00", "00", "00", "00", "00", "11"],
    "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
    " ": ["00", "00", "00", "00", "00", "00", "00"]
};

// Lay a string out as one pattern, with a one-dot column between glyphs.
function text(str) {
    var glyphs = [];
    var s = String(str || "");
    for (var i = 0; i < s.length; i++) {
        var g = DIGITS[s[i]];
        if (g) glyphs.push(g);
    }
    if (!glyphs.length) return [];

    var rows = 7;
    var out = [];
    for (var r = 0; r < rows; r++) {
        var line = "";
        for (var j = 0; j < glyphs.length; j++) {
            if (j > 0) line += "0";
            line += glyphs[j][r];
        }
        out.push(line);
    }
    return out;
}
