// Shared JSON and text coercions for the widget data sources.
//
// Three sources read a document somebody else wrote - omarr's feed, DeepSpend's
// ledger, the collector's usage record - and each had grown its own copy of the
// same few lines: parse it or null, take the number or the fallback, take the
// string or nothing. A copy is not a guarantee: nothing kept the three agreeing,
// and `OmarrData._num` and `DeepSeekData._number` were the same function under
// two names.
//
// Registered the way `nothing/dots.js` is, which is the way a JavaScript file
// is registered here at all: a relative QML import beside the component that
// uses it (`import "JsonRead.js" as JsonRead`). `components/qmldir` lists TYPES;
// a .js file is not one, and dots.js appears in no qmldir either - QML resolves
// a relative .js import against the importing file's own directory, so this
// file travels with the components that import it and needs no registration of
// its own. The clone root is the plugin: there is no copy step to run.

// The parsed document, or null.
//
// The text is taken AS GIVEN - this does not trim. Trimming is not one rule
// here: OmarrData and DeepSeekData trim what they read (a trailing newline is
// how the file ended, not part of the document), while ClaudeUsageData parses
// its record exactly as the collector wrote it. Folding a trim in would quietly
// change that last one: `String.prototype.trim` removes a byte-order mark, so a
// record that starts with one reads today as an unparsable file and would start
// reading as a valid one.
function parseOrNull(text) {
  var t = String(text === undefined || text === null ? "" : text)
  if (t === "") return null
  try {
    return JSON.parse(t)
  } catch (e) {
    return null
  }
}

// A finite number, or `fallback`.
//
// `Number(null)` and `Number("")` are both 0, which is why a caller that has to
// tell "absent" from "zero" checks for the absent value itself before coming
// here (DeepSeekData's `lastTotal`).
function num(v, fallback) {
  var n = Number(v)
  return isFinite(n) ? n : fallback
}

// A whole, positive number, or `fallback`.
//
// That is the shape of every whole-number field these documents carry: a badge
// count, a queue depth. A document that reports zero or a negative one is
// reporting the ABSENCE of the thing rather than a value: omarr's `queuedTotal`
// sums its rows, so one broken row must not subtract from the fleet's total.
//
// TRUNCATED, not rounded: a count of 3.7 is three of the thing, and omarr's own
// counts were read with parseInt before this file existed, so that is the
// behaviour they keep. The callers this replaces disagreed on exactly one input
// class - a fractional whole-number field - and the one that rounded went with
// the compositor reader in plan 055, so nothing here rounds today.
function int(v, fallback) {
  var n = parseInt(v, 10)
  return (isFinite(n) && n > 0) ? n : fallback
}

// A non-empty string, or `fallback`.
//
// The rule both call families already had: OmarrData's `_str` never let a
// non-string through, and ClaudeUsageData's `_text` treated an empty string as
// an absent field - a window with `"label": ""` is a window with no label, not
// one whose label is the empty string.
function str(v, fallback) {
  return (typeof v === "string" && v !== "") ? v : fallback
}
