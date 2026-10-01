import QtQuick
import QtQuick.Layouts
import "../../components"
import "widget"

// Quickshell copy of packages/calendar/contents/ui/main.qml.
//
// Mechanically identical to the Plasma original except for the port's
// standard substitutions (PORTING.md items 3-5, 8): the Plasma imports and
// the `PlasmoidItem`/`fullRepresentation` wrapper are gone,
// `Kirigami.Theme.backgroundColor` -> `theme.systemBackground`,
// `PlasmaBackdrop { id: backdrop }` is supplied by WidgetHost, and the
// i18n() wrappers are dropped.
//
// The one structural change: the THREE `PlasmaCalendar.Calendar` backends,
// the `EventPluginsManager` and the `_daysModelForDate()` juggling are
// deleted and replaced by one `EventSource`. That machinery existed only
// because a Plasma `Calendar` holds a single month while the widget looks up
// to 60 days ahead; a plain `eventsForDate()` has no such limit, so it is
// deleted rather than reproduced (plan 011 step 4).
//
// `EventSource` returns no events on this machine and its own header records
// why (plan 011 phase A: no khal/vdirsyncer/CalDAV/Akonadi, no .ics store, no
// Quickshell calendar service). It is no longer an empty seam, though: plan
// 020 put a real implementation behind it - a watched document plus `khal` if
// it is installed - so everything below renders the day one exists. Everything
// else - month grid, today badge, midnight rollover, both layouts, the three
// temporal groupings and their date formats, the eventType pill colours -
// behaves exactly as on Plasma. The wide panel's empty state is the one
// exception: it used to say the same words whether there was no calendar or a
// quiet week, and now words itself from the seam's `state`.
//
// Two Qt-6 fixes the other ports already carry: `Font.Regular` does not
// exist in Qt 6 (five occurrences here - each logged "Unable to assign
// [undefined] to int" per grid cell, on every frame, until they became
// `Font.Normal`), and the day binding is guarded against `monthDays` not
// being an array yet.
//
// `enabledCalendarPlugins` is dropped: it named a plugin system that does not
// exist here. `eventLookaheadDays` and `firstDayOfWeek` live in
// manifest.json's settings schema.

Item {
    id: root
    anchors.fill: parent

    MacOSColors {
        id: colors
        styleMode: plugin.settings.styleMode
        appearance: plugin.settings.appearance
        systemBackground: theme.systemBackground
        themePalette: theme.palette
    }

    // --- Date state ---
    property date today: new Date()
    property int viewYear: today.getFullYear()
    property int viewMonth: today.getMonth() // 0..11

    // First day of week: 0 = Sunday, 1 = Monday
    readonly property int firstDow: plugin.settings.firstDayOfWeek

    readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    readonly property var weekdayShortSun: ["S", "M", "T", "W", "T", "F", "S"]
    readonly property var weekdayShortMon: ["M", "T", "W", "T", "F", "S", "S"]
    readonly property var weekdayShort: firstDow === 1 ? weekdayShortMon : weekdayShortSun

    // Column [0..6] → is this a Sat/Sun column, given the current firstDow?
    function isWeekendCol(col) {
        return firstDow === 1 ? (col === 5 || col === 6) // Mon-first: cols 5,6 = Sat,Sun
        : (col === 0 || col === 6); // Sun-first: cols 0,6 = Sun,Sat
    }

    // Precomputed day-of-month per grid slot [0..41]; 0 means empty.
    property var monthDays: []
    function rebuildMonthDays() {
        const firstOfMonth = new Date(viewYear, viewMonth, 1);
        let offset = firstOfMonth.getDay() - firstDow;
        if (offset < 0)
            offset += 7;
        const lastDay = new Date(viewYear, viewMonth + 1, 0).getDate();
        const out = new Array(42);
        for (let i = 0; i < 42; i++) {
            const day = i - offset + 1;
            out[i] = (day < 1 || day > lastDay) ? 0 : day;
        }
        monthDays = out;
    }
    onViewYearChanged: {
        rebuildMonthDays();
        _scheduleRebuildEvents();
    }
    onViewMonthChanged: {
        rebuildMonthDays();
        _scheduleRebuildEvents();
    }
    onFirstDowChanged: rebuildMonthDays()
    Component.onCompleted: {
        rebuildMonthDays();
        scheduleNextMidnight();
        // Nothing to wait for any more: the original delayed this 500 ms so
        // three Plasma Calendar backends could finish loading their plugins
        // first, and the source is now queried directly.
        _scheduleRebuildEvents();
    }

    // Midnight rollover. The body is a named function, not inline in the
    // Timer, and takes the "now" it should roll over TO: that is the only
    // way to verify the rollover without moving the machine's clock
    // (moving the machine clock is forbidden), and it is what the headless harness calls.
    // Called with no argument - which is what the Timer does - it behaves
    // exactly as the Plasma original.
    function rollOver(now) {
        const n = now || new Date();
        root.today = n;
        if (n.getFullYear() !== root.viewYear)
            root.viewYear = n.getFullYear();
        if (n.getMonth() !== root.viewMonth)
            root.viewMonth = n.getMonth();
        root.scheduleNextMidnight();
        root._scheduleRebuildEvents();
    }

    Timer {
        id: midnightTimer
        repeat: false
        onTriggered: root.rollOver()
    }
    function scheduleNextMidnight() {
        const now = new Date();
        const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1, 0, 0, 5);
        midnightTimer.interval = Math.max(1000, next.getTime() - now.getTime());
        midnightTimer.start();
    }

    // --- Event lookahead preset ---
    readonly property var _lookaheadPresets: [7, 14, 30, 60]
    readonly property int effectiveLookahead: {
        var idx = plugin.settings.eventLookaheadDays;
        return (idx >= 0 && idx < _lookaheadPresets.length) ? _lookaheadPresets[idx] : 30;
    }
    onEffectiveLookaheadChanged: _scheduleRebuildEvents()

    // --- Event source -----------------------------------------------------
    // Replaces EventPluginsManager + the three PlasmaCalendar.Calendar
    // backends. See components/EventSource.qml.
    EventSource {
        id: eventSource
        onEventsChanged: root._scheduleRebuildEvents()
    }

    // Debounce rapid re-build signals
    Timer {
        id: rebuildDebounce
        interval: 80
        repeat: false
        onTriggered: root._doRebuildEventsModel()
    }
    function _scheduleRebuildEvents() {
        rebuildDebounce.restart();
    }

    // --- Flat events model (section headers + event cards) ---
    ListModel {
        id: eventsModel
    }

    // Fallback pill colors by event type when the collection has no color set.
    // These are matched against EventDataDecorator.eventType (strings from libcalendarplugin.so).
    readonly property var _eventTypeColors: ({
        "Event":    "#4B9EFF",   // blue  — calendar events
        "Todo":     "#FF9500",   // orange — tasks / todos
        "Journal":  "#34C759",   // green  — journal entries
        "Holiday":  "#FF6B6B"    // red    — public holidays
    })

    function _pillColorFor(ev) {
        var c = ev.eventColor ? ev.eventColor.toString() : "";
        if (c.length > 0 && c !== "#000000" && c !== "#00000000") return c;
        var tc = _eventTypeColors[ev.eventType];
        return tc ? tc : "#0a84ff";
    }

    function _formatTime(ev) {
        if (ev.isAllDay) return "All day";
        return Qt.formatDateTime(ev.startDateTime, "h:mm AP");
    }

    function _formatWeekDate(d) {
        return Qt.formatDateTime(d, "ddd d");
    }

    function _formatUpcomingDate(d) {
        return Qt.formatDateTime(d, "MMM d");
    }

    function _doRebuildEventsModel() {
        eventsModel.clear();

        var now = root.today;
        var todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());

        // End of current week (exclusive): the first day of next week
        // Sun-first: week ends Saturday (day 6), so next week starts Sunday
        // Mon-first: week ends Sunday (day 0), so next week starts Monday
        var weekEndDay = todayStart.getDay(); // 0=Sun..6=Sat
        var daysUntilNextWeek;
        if (firstDow === 1) {
            // Mon-first: last day = Sun (0), next week starts Mon
            daysUntilNextWeek = weekEndDay === 0 ? 1 : (8 - weekEndDay);
        } else {
            // Sun-first: last day = Sat (6), next week starts Sun
            daysUntilNextWeek = weekEndDay === 0 ? 7 : (7 - weekEndDay);
        }
        var weekEnd = new Date(todayStart.getTime() + daysUntilNextWeek * 86400000);

        var lookaheadEnd = new Date(todayStart.getTime() + effectiveLookahead * 86400000);

        var todayEvents = [];
        var weekEvents = [];
        var upcomingEvents = [];
        var seen = {};

        for (var d = new Date(todayStart); d < lookaheadEnd; d = new Date(d.getTime() + 86400000)) {
            var rawEvents = eventSource.eventsForDate(d);
            if (!rawEvents || rawEvents.length === 0) continue;

            // QVariantList → JS array so we can sort
            var events = [];
            for (var ei = 0; ei < rawEvents.length; ei++) events.push(rawEvents[ei]);

            events.sort(function(a, b) {
                if (a.isAllDay && !b.isAllDay) return -1;
                if (!a.isAllDay && b.isAllDay) return 1;
                return a.startDateTime.getTime() - b.startDateTime.getTime();
            });

            for (var i = 0; i < events.length; i++) {
                var ev = events[i];
                // Deduplicate multi-day events
                var key = ev.title + "|" + ev.startDateTime.getTime();
                if (seen[key]) continue;
                seen[key] = true;

                var entry = {
                    isHeader: false,
                    title: ev.title,
                    pillColor: _pillColorFor(ev),
                    isAllDay: ev.isAllDay,
                    timeLabel: ""
                };

                var dTime = d.getTime();
                var todayTime = todayStart.getTime();

                if (dTime === todayTime) {
                    entry.timeLabel = _formatTime(ev);
                    todayEvents.push(entry);
                } else if (d < weekEnd) {
                    entry.timeLabel = _formatWeekDate(d);
                    weekEvents.push(entry);
                } else {
                    entry.timeLabel = _formatUpcomingDate(d);
                    upcomingEvents.push(entry);
                }
            }
        }

        if (todayEvents.length > 0) {
            eventsModel.append({ isHeader: true, title: "Events today", pillColor: "", timeLabel: "", isAllDay: false });
            for (var ti = 0; ti < todayEvents.length; ti++) eventsModel.append(todayEvents[ti]);
        }
        if (weekEvents.length > 0) {
            eventsModel.append({ isHeader: true, title: "This week", pillColor: "", timeLabel: "", isAllDay: false });
            for (var wi = 0; wi < weekEvents.length; wi++) eventsModel.append(weekEvents[wi]);
        }
        if (upcomingEvents.length > 0) {
            eventsModel.append({ isHeader: true, title: "Upcoming", pillColor: "", timeLabel: "", isAllDay: false });
            for (var ui = 0; ui < upcomingEvents.length; ui++) eventsModel.append(upcomingEvents[ui]);
        }

    }
    // The Plasma original's fullRepresentation, inlined: the host sizes this
    // item and WidgetRegistry.qml carries the minimum (PORTING.md item 6),
    // so the Layout hints are gone.
    Item {
        id: full
        anchors.fill: parent

        readonly property bool isWide: full.width >= full.height * 2
        readonly property real wideGap: Math.round(full.height * 0.04)
        // Single unified type scale — everything uses this size.
        readonly property real labelSize: Math.max(10, Math.round(full.height * 0.058))

        LiquidGlass {
            id: glass
            anchors.fill: parent
            wallpaperItem: backdrop.item
            radius: plugin.settings.cornerRadius
            roundness: plugin.settings.roundness
            refractThickness: plugin.settings.refractThickness
            refractIOR: plugin.settings.refractIOR
            refractScale: plugin.settings.refractScale
            tint: colors.glassTint
            tintAlpha: plugin.settings.tintAlpha
            chromaStrength: plugin.settings.chromaStrength
            specStrength: plugin.settings.specStrength
            blurRadius: plugin.settings.blurRadiusPx
            realtimeRefraction: plugin.settings.realtimeRefraction
            fallbackOpacity: colors.glassFallbackOpacity
            solidMode: colors.isSolid
            solidColor: colors.solidBackground
        }

        // ── Left panel: Events (wide mode only) ───────────────────────────
        Item {
            id: leftPanel
            visible: full.isWide
            clip: true
            anchors {
                top: parent.top
                left: parent.left
                bottom: parent.bottom
                right: rightPanel.left
                rightMargin: full.wideGap
            }

            readonly property real _margin: Math.round(full.height * 0.09)
            readonly property real _cardSize: Math.max(10, Math.round(full.height * 0.052))
            readonly property real _cardSpacing: Math.round(full.height * 0.025)

            // Empty state. What is missing has three different meanings - no
            // backend at all, a calendar with nothing in it, a document nobody
            // has refreshed - and only the seam knows which, so the words come
            // from its `state` and its `stateDetail`. This is the ONE thing the
            // widget may branch on them for; the layout never does.
            Column {
                id: emptyState
                anchors.centerIn: parent
                width: parent.width * 0.86
                spacing: Math.round(full.height * 0.02)
                visible: eventsModel.count === 0

                readonly property string headline: eventSource.state === "no-backend"
                    ? "No calendar connected"
                    : (eventSource.state === "stale"
                        ? "Calendar may be out of date" : "Nothing scheduled")
                // The second line: where to point a writer, or how old the last
                // sync is. "unreadable" is the one thing the state cannot say
                // by itself - a malformed document is `no-backend` too, and
                // `readError` is what tells them apart.
                readonly property string detail: eventSource.state === "no-backend"
                    ? eventSource.stateDetail
                        + (eventSource.readError !== "" ? " · unreadable" : "")
                        + "\ninstall `khal`, or point any sync script at this file"
                    : (eventSource.state === "stale"
                        ? "last sync " + eventSource.stateDetail : "")

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: emptyState.headline
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: full.labelSize
                    font.weight: Font.Normal
                    opacity: colors.textQuiet
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: emptyState.detail !== ""
                    text: emptyState.detail
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: Math.round(full.labelSize * 0.8)
                    font.weight: Font.Normal
                    // Smaller, not fainter: PORTING item 33 measured
                    // `textQuiet` as the dimmest ink a Text may read here, so
                    // the hierarchy between the two lines is carried by size.
                    opacity: colors.textQuiet
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                }
            }

            // Section headers + event cards
            ListView {
                id: eventsList
                anchors {
                    top: parent.top
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    topMargin: leftPanel._margin
                    leftMargin: leftPanel._margin
                    rightMargin: leftPanel._margin
                    bottomMargin: leftPanel._margin
                }
                visible: eventsModel.count > 0
                model: eventsModel
                spacing: leftPanel._cardSpacing
                clip: true
                interactive: contentHeight > height

                delegate: Item {
                    width: eventsList.width
                    height: loader.height

                    Loader {
                        id: loader
                        width: parent.width
                        sourceComponent: model.isHeader ? sectionHeaderComponent : eventCardComponent
                        onLoaded: {
                            if (model.isHeader) {
                                item.headerTitle = model.title;
                                item.isFirstHeader = (index === 0);
                            } else {
                                item.cardTitle = model.title;
                                item.cardTime = model.timeLabel;
                                item.cardPill = model.pillColor;
                            }
                        }
                    }
                }
            }

            Component {
                id: sectionHeaderComponent
                Text {
                    textFormat: Text.PlainText
                    property string headerTitle: ""
                    property bool isFirstHeader: false

                    text: headerTitle
                    color: colors.foreground
                    font.family: colors.uiFont
                    font.pixelSize: full.labelSize
                    font.weight: Font.Normal
                    opacity: 0.55
                    font.letterSpacing: 0.5
                    topPadding: isFirstHeader ? 0 : leftPanel._cardSpacing
                    height: Math.round(font.pixelSize * 1.4) + topPadding
                }
            }

            Component {
                id: eventCardComponent
                EventCard {
                    property string cardTitle: ""
                    property string cardTime: ""
                    property string cardPill: ""

                    width: parent ? parent.width : 0
                    title: cardTitle
                    timeLabel: cardTime
                    pillColor: cardPill
                    textColor: colors.foreground
                    fontFamily: colors.uiFont
                    fontSize: leftPanel._cardSize
                    cardBg: colors.cardBackground
                    cardBgOpacity: colors.cardBackgroundOpacity
                }
            }
        }

        // ── Right panel: Calendar grid ────────────────────────────────────
        Item {
            id: rightPanel
            width: full.isWide ? full.height : full.width
            anchors {
                top: parent.top
                right: parent.right
                bottom: parent.bottom
            }
        }

        ColumnLayout {
            parent: rightPanel
            anchors.fill: parent
            anchors.margins: Math.round(full.height * 0.09)
            anchors.topMargin: Math.round(full.height * 0.14)
            spacing: Math.round(full.height * 0.02)

            // --- Month header ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: full.labelSize * 1.4

                TextMetrics {
                    id: sMetrics
                    font.family: colors.uiFont
                    font.pixelSize: full.labelSize
                    text: root.weekdayShort[0]
                }

                Text {
                    textFormat: Text.PlainText
                    x: parent.width / 7 / 2 - sMetrics.width / 2
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.monthNames[root.viewMonth].toUpperCase()
                    color: colors.todayAccent
                    font.family: colors.uiFont
                    font.pixelSize: full.labelSize
                    font.weight: Font.Normal
                    font.letterSpacing: 1
                }
            }

            // --- Weekday header (S M T W T F S) ---
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: full.labelSize * 1.4

                Row {
                    anchors.fill: parent
                    Repeater {
                        model: 7
                        delegate: Item {
                            width: parent.width / 7
                            height: parent.height
                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                text: root.weekdayShort[index]
                                color: colors.foreground
                                opacity: root.isWeekendCol(index) ? 0.45 : 0.75
                                font.family: colors.uiFont
                                font.pixelSize: full.labelSize
                                font.weight: Font.Normal
                            }
                        }
                    }
                }
            }

            // --- Day grid: 6 rows × 7 columns ---
            Item {
                id: gridWrap
                Layout.fillWidth: true
                Layout.fillHeight: true

                readonly property real cellW: width / 7
                readonly property real cellH: height / 6
                readonly property real badgeDiameter: Math.min(cellW, cellH) * 1.02

                Grid {
                    id: dayGrid
                    anchors.fill: parent
                    rows: 6
                    columns: 7

                    Repeater {
                        model: 42
                        delegate: Item {
                            width: gridWrap.cellW
                            height: gridWrap.cellH

                            // Defensive against `monthDays` not being an
                            // array yet: the plain `root.monthDays[index] || 0`
                            // the Plasma original uses logged "Unable to
                            // assign [undefined] to int" on every delegate
                            // during the first frame here.
                            readonly property int day: {
                                var list = root.monthDays
                                if (!list || index < 0 || index >= list.length) return 0
                                var v = list[index]
                                return v ? v : 0
                            }
                            readonly property bool empty: day === 0
                            readonly property bool isCurrent: !empty && day === root.today.getDate() && root.viewMonth === root.today.getMonth() && root.viewYear === root.today.getFullYear()
                            readonly property bool isWeekend: root.isWeekendCol(index % 7)

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                visible: !empty && !isCurrent
                                text: day
                                color: colors.foreground
                                opacity: isWeekend ? 0.45 : 1.0
                                font.family: colors.uiFont
                                font.pixelSize: full.labelSize
                                font.weight: Font.Normal
                            }

                            TodayBadge {
                                anchors.centerIn: parent
                                width: parent.width + gridWrap.badgeDiameter * 0.30
                                height: parent.height + gridWrap.badgeDiameter * 0.30
                                visible: isCurrent
                                contentRect: Qt.rect((width - parent.width) / 2, (height - parent.height) / 2, parent.width, parent.height)
                                dayNumber: day
                                diameter: gridWrap.badgeDiameter
                                circleXOffset: full.labelSize * 0.04
                                circleYOffset: -full.labelSize * 0.05
                                fontPixelSize: full.labelSize
                                fontFamily: colors.uiFont
                                badgeColor: colors.todayAccent
                                textColor: "#ffffff"
                                punchOutText: colors.punchOutText
                            }
                        }
                    }
                }
            }
        }
    }
}
