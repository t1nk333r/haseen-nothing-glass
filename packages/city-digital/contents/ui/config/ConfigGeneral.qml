import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "../components/cities.js" as Cities

// "Clocks" config page for City Digital — a single-city picker (maxClocks 1).
// The row picks an IANA timezone and an optional label. Stored in the `clocks`
// String kcfg as a single "Zone|Label" item.
//
// Editing model: a plain JS array `_rows` of { tz, label } is the single
// source of truth. Every edit builds a NEW array and reassigns it (and writes
// the serialized string to cfg_clocks). We never mutate a live ListModel in
// place — doing so with `required property int index` delegates triggered
// re-indexing/focus-out races that left phantom blank rows and blocked Apply.

ColumnLayout {
    id: page
    spacing: Kirigami.Units.largeSpacing

    Layout.margins: Kirigami.Units.largeSpacing * 2
    Layout.topMargin: Kirigami.Units.largeSpacing * 2

    property int maxClocks: 1

    // `clocks` is a String kcfg: comma-joined "Zone|Label" items. A plain
    // string dirties reliably on every edit, so Apply enables correctly.
    property string cfg_clocks: ""

    // Full IANA zone list for the pickers (sorted). Falls back to the bundled
    // cities table keys if Intl.supportedValuesOf isn't available.
    readonly property var _zones: {
        try {
            if (typeof Intl !== "undefined" && Intl.supportedValuesOf)
                return Intl.supportedValuesOf("timeZone");
        } catch (e) {}
        return Object.keys(Cities.TABLE).sort();
    }

    // Editing buffer: array of { tz, label }. The Repeater binds to this.
    property var _rows: []

    property bool _loading: false

    function _toArray(v) {
        if (typeof v === "string")
            return v.length ? v.split(",") : [];
        return v ? v : [];
    }

    // Parse cfg_clocks -> _rows (skip blank tz entries; never a phantom row).
    function _load() {
        _loading = true;
        var rows = [];
        var list = _toArray(cfg_clocks);
        for (var i = 0; i < list.length && rows.length < maxClocks; i++) {
            var s = String(list[i]);
            var bar = s.indexOf("|");
            var tz = (bar >= 0 ? s.slice(0, bar) : s).trim();
            var label = bar >= 0 ? s.slice(bar + 1).trim() : "";
            if (!tz) continue;
            rows.push({ tz: tz, label: label });
        }
        if (rows.length === 0)
            rows.push({ tz: "", label: "" });
        _rows = rows;
        _loading = false;
    }

    // Serialize _rows -> cfg_clocks (skip blank rows). Reassigns a fresh string.
    function _save() {
        if (_loading) return;
        var out = [];
        for (var i = 0; i < _rows.length; i++) {
            var tz = (_rows[i].tz || "").trim();
            if (!tz) continue;
            out.push(tz + "|" + (_rows[i].label || ""));
        }
        cfg_clocks = out.join(",");
    }

    // Replace the whole editing array and persist. All edits funnel through
    // here so the model is always rebuilt immutably, never mutated in place.
    function _apply(rows) {
        _rows = rows;
        _save();
    }

    function _setRow(index, key, value) {
        if (index < 0 || index >= _rows.length) return;
        var rows = _rows.slice();
        var r = { tz: rows[index].tz, label: rows[index].label };
        r[key] = value;
        rows[index] = r;
        _apply(rows);
    }

    function _removeRow(index) {
        if (index < 0 || index >= _rows.length) return;
        var rows = _rows.slice();
        rows.splice(index, 1);
        if (rows.length === 0)
            rows.push({ tz: "", label: "" });
        _apply(rows);
    }

    function _addRow() {
        if (_rows.length >= maxClocks) return;
        var rows = _rows.slice();
        rows.push({ tz: "", label: "" });
        _apply(rows);
    }

    // Only (re)load when our array is empty — i.e. first open. Subsequent
    // cfg_clocks changes are our own _save() writes; don't clobber the buffer.
    onCfg_clocksChanged: if (!_rows || _rows.length === 0) _load()
    Component.onCompleted: _load()

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: true
        type: Kirigami.MessageType.Information
        text: i18n("Pick the city this clock shows.")
    }

    Repeater {
        model: page._rows

        delegate: RowLayout {
            id: row
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            required property int index
            required property var modelData
            readonly property string tz: modelData.tz || ""
            readonly property string label: modelData.label || ""

            ComboBox {
                id: zoneCombo
                Layout.fillWidth: true
                editable: true
                model: page._zones
                currentIndex: page._zones.indexOf(row.tz)
                Component.onCompleted: editText = row.tz
                // Selecting from the dropdown.
                onActivated: page._setRow(row.index, "tz", currentText.trim())
                // Pressing Enter in the editable field.
                onAccepted: page._setRow(row.index, "tz", editText.trim())
                // Losing focus after typing a custom value without Enter. Only
                // commit a non-empty value that differs — otherwise clicking the
                // remove/add button (which steals focus) would write a blank.
                onActiveFocusChanged: {
                    if (activeFocus) return;
                    var v = (editText || "").trim();
                    if (v.length > 0 && v !== row.tz) page._setRow(row.index, "tz", v);
                }
            }

            // Live code preview so the user sees what will be shown.
            Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 3
                horizontalAlignment: Text.AlignHCenter
                text: row.tz ? Cities.lookup(row.tz).code : ""
                opacity: 0.7
                elide: Text.ElideRight
            }

            TextField {
                id: labelField
                Layout.preferredWidth: Kirigami.Units.gridUnit * 7
                placeholderText: row.tz ? Cities.lookup(row.tz).name : i18n("Label")
                text: row.label
                onEditingFinished: page._setRow(row.index, "label", text)
            }

            Button {
                icon.name: "list-remove"
                enabled: page._rows.length > 1
                onClicked: page._removeRow(row.index)
            }
        }
    }

    Button {
        icon.name: "list-add"
        text: i18n("Add city")
        enabled: page._rows.length < page.maxClocks
        onClicked: page._addRow()
    }

    Item { Layout.fillHeight: true }
}
