import QtQuick
import "../../components"
import "../../components/nothing"

// Calendar, Nothing style.
//
// Same source of truth as the Liquid Glass calendar next door: one
// EventSource (which on this machine has no data yet - see
// components/EventSource.qml for the seam and the survey behind that), the
// same `firstDayOfWeek` and `eventLookaheadDays` settings, the same midnight
// rollover. The month grid is derived here because that derivation is
// presentation - a grid of 42 slots - not data.
//
// Nothing terms: mono weekday initials, a tight grid, today as a filled red
// square rather than a circle, weekends dimmed, and an empty schedule that
// reads as a statement (NOTHING SCHEDULED) instead of a failure - the one
// place this file reads the seam's `state`, to say which silence it is
// (`_emptyText`).
Item {
    id: full
    anchors.fill: parent

    // The three grid presets: 192x192 (small), 400x192 (wide), 400x400 (big).
    readonly property bool isWide: full.width >= full.height * 1.6
    readonly property bool isBig: !full.isWide && Math.min(full.width, full.height) >= 300
    readonly property bool isSmall: !full.isWide && !full.isBig

    // ── Date state ───────────────────────────────────────────────────────
    property date today: new Date()
    readonly property int viewYear: full.today.getFullYear()
    readonly property int viewMonth: full.today.getMonth()

    // 0 = Sunday, 1 = Monday. Same key as the Liquid Glass twin.
    readonly property int firstDow: plugin.settings.firstDayOfWeek

    readonly property var monthNames: ["January", "February", "March", "April",
        "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var weekdaysSun: ["S", "M", "T", "W", "T", "F", "S"]
    readonly property var weekdaysMon: ["M", "T", "W", "T", "F", "S", "S"]
    readonly property var weekdays: full.firstDow === 1 ? full.weekdaysMon : full.weekdaysSun

    function isWeekendCol(col) {
        return full.firstDow === 1 ? (col === 5 || col === 6)
                                   : (col === 0 || col === 6)
    }

    // Day-of-month per grid slot [0..41]; 0 means the slot is outside the
    // month. Recomputed whenever the month or the week start moves.
    readonly property var monthDays: {
        var firstOfMonth = new Date(full.viewYear, full.viewMonth, 1)
        var offset = firstOfMonth.getDay() - full.firstDow
        if (offset < 0) offset += 7
        var lastDay = new Date(full.viewYear, full.viewMonth + 1, 0).getDate()
        var out = new Array(42)
        for (var i = 0; i < 42; i++) {
            var day = i - offset + 1
            out[i] = (day < 1 || day > lastDay) ? 0 : day
        }
        return out
    }

    // Midnight rollover, as in the twin: one scheduled shot, re-armed each
    // time it fires, rather than a per-minute poll.
    Timer {
        id: midnightTimer
        repeat: false
        onTriggered: {
            full.today = new Date()
            full.scheduleNextMidnight()
            full._scheduleRebuild()
        }
    }
    function scheduleNextMidnight() {
        var now = new Date()
        var next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5)
        midnightTimer.interval = Math.max(1000, next.getTime() - now.getTime())
        midnightTimer.start()
    }

    // ── Events ───────────────────────────────────────────────────────────
    readonly property var _lookaheadPresets: [7, 14, 30, 60]
    readonly property int effectiveLookahead: {
        var idx = plugin.settings.eventLookaheadDays
        return (idx >= 0 && idx < full._lookaheadPresets.length)
            ? full._lookaheadPresets[idx] : 30
    }
    onEffectiveLookaheadChanged: full._scheduleRebuild()

    EventSource {
        id: eventSource
        onEventsChanged: full._scheduleRebuild()
    }

    // The empty schedule's words come from the seam's own state - the one
    // thing this widget branches on it for, never the layout. "Nothing
    // scheduled" is a calendar with nothing in it; the other two say whose
    // silence it is, and the caption stays words-only (the path to point a
    // writer at belongs to the glass panel's wide layout, not to a tile
    // centimetres wide).
    readonly property string _emptyText: {
        const s = eventSource.state
        if (s === "no-backend") return "No calendar connected"
        if (s === "stale") return "Calendar may be stale"
        return "Nothing scheduled"
    }

    ListModel { id: eventsModel }

    // Day-of-month -> true for days of the VIEW month that carry an event,
    // filled by the same pass that builds the list. The grid marks them with
    // a dot under the number.
    property var eventDays: ({})

    Timer {
        id: rebuildDebounce
        interval: 80
        repeat: false
        onTriggered: full._rebuildEvents()
    }
    function _scheduleRebuild() { rebuildDebounce.restart() }

    function _whenLabel(day, dayStart, todayStart, ev) {
        if (dayStart.getTime() === todayStart.getTime())
            return ev.isAllDay ? "ALL DAY" : Qt.formatDateTime(ev.startDateTime, "HH:mm")
        return Qt.formatDateTime(day, "dd MMM").toUpperCase()
    }

    function _rebuildEvents() {
        eventsModel.clear()

        var now = full.today
        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        var end = new Date(todayStart.getTime() + full.effectiveLookahead * 86400000)
        var marks = ({})
        var seen = ({})

        for (var d = new Date(todayStart); d < end; d = new Date(d.getTime() + 86400000)) {
            var raw = eventSource.eventsForDate(d)
            if (!raw || raw.length === 0) continue

            var events = []
            for (var ei = 0; ei < raw.length; ei++) events.push(raw[ei])
            events.sort(function (a, b) {
                if (a.isAllDay && !b.isAllDay) return -1
                if (!a.isAllDay && b.isAllDay) return 1
                return a.startDateTime.getTime() - b.startDateTime.getTime()
            })

            for (var i = 0; i < events.length; i++) {
                var ev = events[i]
                var key = ev.title + "|" + ev.startDateTime.getTime()
                if (seen[key]) continue
                seen[key] = true

                if (d.getMonth() === full.viewMonth && d.getFullYear() === full.viewYear)
                    marks[d.getDate()] = true

                eventsModel.append({
                    title: ev.title,
                    when: full._whenLabel(d, new Date(d.getFullYear(), d.getMonth(), d.getDate()),
                                          todayStart, ev),
                    isToday: d.getTime() === todayStart.getTime()
                })
            }
        }

        full.eventDays = marks
    }

    Component.onCompleted: {
        full.scheduleNextMidnight()
        full._scheduleRebuild()
    }

    NCard {
        id: card
        theme: nothing
        anchors.fill: parent
        clip: true

        // ── Small square: today's number, and nothing else ───────────────
        Item {
            id: smallLayout
            visible: full.isSmall
            anchors.fill: parent
            anchors.margins: nothing.pad

            NLabel {
                id: sWeekday
                theme: nothing
                text: Qt.formatDateTime(full.today, "dddd")
                loud: true
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                elide: Text.ElideRight
            }

            Item {
                id: sStage
                anchors.top: sWeekday.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: sFooter.top
                anchors.bottomMargin: nothing.gap

                readonly property string dayText: String(full.today.getDate())
                readonly property real dotSize: {
                    var cols = sStage.dayText.length * 6 - 1
                    var byW = (sStage.width - (cols - 1) * 2) / cols
                    var byH = (sStage.height - 6 * 2) / 7
                    return Math.max(2, Math.min(byW, byH) * 0.82)
                }

                NDotMatrix {
                    anchors.centerIn: parent
                    theme: nothing
                    text: sStage.dayText
                    dot: sStage.dotSize
                    gap: Math.max(1, sStage.dotSize * 0.34)
                    onColor: nothing.red
                }
            }

            Column {
                id: sFooter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                spacing: nothing.px(6)

                // The week as seven dots, today's square and red: the same
                // information the grid carries, at the size that has no grid.
                Row {
                    id: sWeek
                    width: parent.width
                    spacing: nothing.px(3)

                    readonly property int todayCol: {
                        var c = full.today.getDay() - full.firstDow
                        if (c < 0) c += 7
                        return c
                    }

                    Repeater {
                        model: 7

                        Rectangle {
                            required property int index
                            readonly property bool isToday: index === sWeek.todayCol

                            width: (sWeek.width - 6 * sWeek.spacing) / 7
                            height: nothing.px(5)
                            radius: isToday ? nothing.rDot : height / 2
                            color: isToday ? nothing.red
                                : (full.isWeekendCol(index) ? nothing.onFaint : nothing.onDim)
                        }
                    }
                }

                NMono {
                    theme: nothing
                    width: parent.width
                    text: Qt.formatDateTime(full.today, "MMMM yyyy").toUpperCase()
                    color: nothing.onDim
                    font.pixelSize: nothing.fMicro
                    font.letterSpacing: nothing.trackLabel
                    elide: Text.ElideRight
                }
            }
        }

        // ── Wide: the schedule on the left, the month square on the right ─
        Item {
            id: wideLayout
            visible: full.isWide
            anchors.fill: parent
            anchors.margins: nothing.pad

            Item {
                id: wList
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.right: wRule.left
                anchors.rightMargin: nothing.pad

                NLabel {
                    id: wListHeader
                    theme: nothing
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: "Schedule"
                    loud: true
                }

                ListView {
                    anchors.top: wListHeader.bottom
                    anchors.topMargin: nothing.gap
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    visible: eventsModel.count > 0
                    model: eventsModel
                    spacing: nothing.px(4)
                    clip: true
                    interactive: contentHeight > height

                    delegate: Item {
                        id: wEvent
                        required property string title
                        required property string when
                        required property bool isToday

                        width: ListView.view.width
                        height: nothing.px(26)

                        Rectangle {
                            id: wEventMark
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: nothing.px(3)
                            height: nothing.px(16)
                            radius: nothing.rDot
                            color: wEvent.isToday ? nothing.red : nothing.onFaint
                        }

                        NText {
                            theme: nothing
                            anchors.left: wEventMark.right
                            anchors.leftMargin: nothing.px(6)
                            anchors.right: parent.right
                            anchors.top: parent.top
                            text: wEvent.title
                            font.pixelSize: nothing.fLabel
                            elide: Text.ElideRight
                        }

                        NMono {
                            theme: nothing
                            anchors.left: wEventMark.right
                            anchors.leftMargin: nothing.px(6)
                            anchors.bottom: parent.bottom
                            text: wEvent.when
                            color: nothing.onDim
                            font.pixelSize: nothing.fMicro
                        }
                    }
                }

                // Not a failure - a fact. An empty schedule says so plainly,
                // and says which of the three silences it is.
                Column {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: eventsModel.count === 0
                    spacing: nothing.px(4)

                    NDotMatrix {
                        theme: nothing
                        anchors.horizontalCenter: parent.horizontalCenter
                        pattern: ["01110", "10001", "10011", "10101", "11001", "10001", "01110"]
                        dot: nothing.px(3)
                        gap: nothing.px(2)
                        onColor: nothing.onFaint
                        offColor: "transparent"
                    }
                    NLabel {
                        theme: nothing
                        width: parent.width
                        text: full._emptyText
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }

            NDivider {
                id: wRule
                theme: nothing
                vertical: true
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: wMonth.left
                anchors.rightMargin: nothing.pad
            }

            Item {
                id: wMonth
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: Math.min(parent.width * 0.5, parent.height)

                CalendarBlock {
                    anchors.fill: parent
                }
            }
        }

        // ── Big square: the month, then the schedule beneath it ──────────
        Item {
            id: bigLayout
            visible: full.isBig
            anchors.fill: parent
            anchors.margins: nothing.pad

            CalendarBlock {
                id: bMonth
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: Math.round(full.height * 0.62)
            }

            NDivider {
                id: bRule
                theme: nothing
                anchors.top: bMonth.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
            }

            NLabel {
                id: bListHeader
                theme: nothing
                anchors.top: bRule.bottom
                anchors.topMargin: nothing.gap
                anchors.left: parent.left
                anchors.right: parent.right
                text: "Schedule"
                loud: true
            }

            ListView {
                anchors.top: bListHeader.bottom
                anchors.topMargin: nothing.px(4)
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                visible: eventsModel.count > 0
                model: eventsModel
                spacing: nothing.px(4)
                clip: true
                interactive: contentHeight > height

                delegate: Item {
                    id: bEvent
                    required property string title
                    required property string when
                    required property bool isToday

                    width: ListView.view.width
                    height: nothing.px(20)

                    Rectangle {
                        id: bEventMark
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: nothing.px(6)
                        height: nothing.px(6)
                        radius: bEvent.isToday ? nothing.rDot : width / 2
                        color: bEvent.isToday ? nothing.red : nothing.onFaint
                    }

                    NMono {
                        id: bEventWhen
                        theme: nothing
                        anchors.left: bEventMark.right
                        anchors.leftMargin: nothing.px(6)
                        anchors.verticalCenter: parent.verticalCenter
                        width: nothing.px(58)
                        text: bEvent.when
                        color: nothing.onDim
                        font.pixelSize: nothing.fMicro
                        elide: Text.ElideRight
                    }

                    NText {
                        theme: nothing
                        anchors.left: bEventWhen.right
                        anchors.leftMargin: nothing.px(6)
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: bEvent.title
                        font.pixelSize: nothing.fLabel
                        elide: Text.ElideRight
                    }
                }
            }

            NLabel {
                theme: nothing
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: bListHeader.bottom
                anchors.bottom: parent.bottom
                visible: eventsModel.count === 0
                text: full._emptyText
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }
        }
    }

    // ── The month block, used by the wide and the big layouts ────────────
    // Month line, mono weekday initials, then a 7x6 grid. Today is a filled
    // red square - the one accent on the tile - and weekends are dimmed.
    component CalendarBlock: Item {
        id: block

        NLabel {
            id: blockMonth
            theme: nothing
            anchors.top: parent.top
            anchors.left: parent.left
            text: full.monthNames[full.viewMonth]
            loud: true
        }

        NMono {
            id: blockYear
            theme: nothing
            anchors.verticalCenter: blockMonth.verticalCenter
            anchors.right: parent.right
            text: String(full.viewYear)
            color: nothing.onDim
            font.pixelSize: nothing.fMicro
        }

        Row {
            id: blockDows
            anchors.top: blockMonth.bottom
            anchors.topMargin: nothing.px(6)
            anchors.left: parent.left
            anchors.right: parent.right
            height: nothing.px(14)

            Repeater {
                model: 7

                Item {
                    required property int index
                    width: blockDows.width / 7
                    height: blockDows.height

                    NMono {
                        anchors.centerIn: parent
                        theme: nothing
                        text: full.weekdays[parent.index]
                        color: full.isWeekendCol(parent.index) ? nothing.onQuiet : nothing.onDim
                        font.pixelSize: nothing.fMicro
                        font.letterSpacing: nothing.trackLabel
                    }
                }
            }
        }

        Item {
            id: blockGrid
            anchors.top: blockDows.bottom
            anchors.topMargin: nothing.px(2)
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            readonly property real cellW: blockGrid.width / 7
            readonly property real cellH: blockGrid.height / 6
            readonly property real cellSide: Math.min(blockGrid.cellW, blockGrid.cellH)

            Grid {
                anchors.fill: parent
                rows: 6
                columns: 7

                Repeater {
                    model: 42

                    Item {
                        id: cell
                        required property int index

                        width: blockGrid.cellW
                        height: blockGrid.cellH

                        readonly property int day: {
                            var list = full.monthDays
                            if (!list || cell.index < 0 || cell.index >= list.length) return 0
                            var v = list[cell.index]
                            return v ? v : 0
                        }
                        readonly property bool isToday:
                            cell.day !== 0 && cell.day === full.today.getDate()
                        readonly property bool isWeekend: full.isWeekendCol(cell.index % 7)
                        readonly property bool hasEvent:
                            cell.day !== 0 && !!full.eventDays[cell.day]

                        // Today: a filled square, tight radius, never a circle.
                        Rectangle {
                            id: todayMark
                            anchors.centerIn: parent
                            width: blockGrid.cellSide * 0.84
                            height: width
                            radius: nothing.rDot
                            visible: cell.isToday
                            color: nothing.red
                        }

                        NMono {
                            anchors.centerIn: parent
                            theme: nothing
                            visible: cell.day !== 0
                            text: String(cell.day)
                            color: cell.isToday ? nothing.redInk
                                : (cell.isWeekend ? nothing.onQuiet : nothing.on)
                            font.pixelSize: Math.max(nothing.px(8),
                                Math.round(blockGrid.cellSide * 0.44))
                        }

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: Math.max(1, blockGrid.cellSide * 0.06)
                            width: nothing.px(3)
                            height: width
                            radius: width / 2
                            visible: cell.hasEvent
                            color: cell.isToday ? nothing.redInk : nothing.on
                        }
                    }
                }
            }
        }
    }
}
