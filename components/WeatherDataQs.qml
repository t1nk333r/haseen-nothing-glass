import QtQuick
import Quickshell.Io

// The Quickshell weather engine.
//
// It began as a copy of the Plasma original (the Plasma-era tree, deleted
// 2026-09-10 - PORTING.md item 31) and has since diverged on
// purpose. On Omarchy the location, the unit system and the refresh cadence
// are the desktop's business, not one tile's, so this copy follows the shell
// instead of its own settings. PORTING.md's rule applies: that behaviour lives
// here, and not in the Plasma original, which ran on a session with no
// Omarchy state directory to follow.
//
// What it takes from Omarchy's own weather plugin
// (/usr/share/omarchy/shell/plugins/panels/weather/):
//
//   location  ~/.local/state/omarchy/settings/weather.json, watched live
//             (Panel.qml:97-114, mirrored in OmarchyLocation.qml), so
//             `omarchy-weather-location --set Riyadh` moves this tile with no
//             restart. No file means IP auto-detect through wttr.in, exactly
//             like the stock pill (Panel.qml:456-467) - never a hard-coded
//             city, which is what an unconfigured user used to get.
//   units     Model.shouldUseImperial(): an explicit `unit` wins, else the
//             country the geocoder reported, else the locale. Open-Meteo is
//             always asked in metric and the conversion happens here, so
//             flipping the unit re-renders the cached report instead of
//             costing a round trip.
//   refresh   `refreshMinutes`, default 15, clamped to >= 1, firing on start
//             (Panel.qml:143, 469-476).
//   failure   the last good reading stays on screen and three 2.5 s retries
//             per cycle replace the old unbounded 5-minute backoff
//             (Panel.qml:367-390). An offline moment must not blank a
//             perfectly good temperature.
//
// What it deliberately does NOT take is the presentation: Omarchy draws a
// nerd-font glyph and no condition text at all. The icon vocabulary and the 27
// phrases below are this widget's design and stay.
//
// Quickshell-specific fixes carried over from the original port (plan 008's
// execution log - each was observed live, not theorised):
//
//   1. Every property write inside a request callback is qualified with
//      `wd.`. An unqualified write from a nested JS closure does not resolve
//      to the QML object's scope: Qt logs `Invalid write to global property`
//      and DISCARDS it, so the state never reached the UI.
//   2. Only the newest request counts. The bar injects `settings` one step
//      after construction, so a default-config request and a real-config
//      request used to be in flight together and the display showed
//      whichever LANDED last; now a new request kills the previous one (see
//      Network below) and `_reqSeq` drops anything it had already written.
//   3. Config changes all funnel through `Qt.callLater(_refreshFromConfig)`,
//      collapsing that injection burst into one refresh.

QtObject {
    id: wd

    // ── Settings ────────────────────────────────────────────────────────
    // Per-widget override of the city. Empty - the default - means "wherever
    // Omarchy says I am", which is what makes a fresh tile show the user's own
    // weather; fill it in to point a second tile at another city.
    property string location: ""
    // "" = auto, "metric", "imperial". Same three values as Omarchy's `unit`.
    property string unit: ""
    // Minutes between refreshes. Clamped below, so 0 cannot spin the network.
    property int refreshMinutes: 15

    // ── The gate every other engine already has ──────────────────────────
    // `active` is what a view binds to its own `visible`: false only while the
    // screen is switched off (DPMS), which is the one "not being drawn" state
    // the shell can see - a widget sits on every workspace by design. Unknown
    // reads as true, so the failure mode is a fetch into a hidden tile, never
    // a blank one. Nothing polls while it is false; see the two timers below.
    property bool active: true

    // ── Output ──────────────────────────────────────────────────────────
    property bool isLoading: true
    // Why the last attempt failed, for the empty state only. It never replaces
    // a reading: a widget with data on screen shows the data.
    property string errorMessage: ""
    property string cityName: ""

    property string currentTemp: "--"
    property string highTemp: "--"
    property string lowTemp: "--"
    property int weatherCode: 0
    property string condition: "Loading..."
    property string windSpeed: "--"
    property string windDirection: ""

    property var todaySunrise: null
    property var todaySunset: null
    property bool isNight: false

    property string gradientCategory: "clear"
    property string precipitationSummary: ""
    property var hourlySlots: []
    property var dailyForecast: []
    property real overallLow: 0
    property real overallHigh: 100

    // ── Where "here" is ─────────────────────────────────────────────────
    // The shared file Omarchy's own weather reads and `omarchy-weather-location`
    // writes. Watched, so a change lands without a restart.
    property OmarchyLocation _shared: OmarchyLocation {}

    // The city wttr.in guessed from our IP, once, when nothing else answered.
    property string _detectedName: ""

    readonly property string _overrideName: String(wd.location).replace(/^\s+|\s+$/g, "")
    readonly property bool _followShared: wd._overrideName === ""

    // The precedence chain, in one place: this widget's own city, else the
    // name in the shared file, else the city wttr.in detected from our IP.
    readonly property string resolvedLocation:
        wd._overrideName !== "" ? wd._overrideName
        : (wd._shared.name !== "" ? wd._shared.name : wd._detectedName)

    // Coordinates only ever come from the shared file - `omarchy-weather-location
    // --set <name> <lat,lon>` stores them so nobody has to geocode. A name-only
    // file, or a per-widget override, is geocoded instead.
    readonly property double resolvedLatitude:
        (wd._followShared && wd._shared.hasCoordinates) ? wd._shared.latitude : 0
    readonly property double resolvedLongitude:
        (wd._followShared && wd._shared.hasCoordinates) ? wd._shared.longitude : 0
    readonly property bool _hasStoredCoordinates:
        wd.resolvedLatitude !== 0 || wd.resolvedLongitude !== 0

    // Geocoder output for `resolvedLocation`, kept apart from the stored
    // coordinates so the two can disagree without one clobbering the other.
    property double _geoLatitude: 0
    property double _geoLongitude: 0
    property string _geocodedFor: ""
    // ISO-3166 alpha-2 from the geocoder; "" until something geocodes.
    property string _countryCode: ""

    function _latitude() { return wd._hasStoredCoordinates ? wd.resolvedLatitude : wd._geoLatitude }
    function _longitude() { return wd._hasStoredCoordinates ? wd.resolvedLongitude : wd._geoLongitude }

    // ── Units ───────────────────────────────────────────────────────────
    // Model.shouldUseImperial(setting, locale, country), with the country
    // expressed as the ISO-3166 code Open-Meteo's geocoder returns rather than
    // the free-text name wttr.in gives Omarchy. Same three countries.
    function _countryUsesImperial(code) {
        var c = String(code || "").replace(/^\s+|\s+$/g, "").toUpperCase()
        if (c === "") return null
        return c === "US" || c === "LR" || c === "MM"
    }

    function _localeUsesImperial(localeName) {
        var n = String(localeName || "").replace(".", "_")
        return /^en[_-]US($|[_.-])/.test(n) || /^en[_-]LR($|[_.-])/.test(n) || /^my($|[_.-])/.test(n)
    }

    readonly property bool useImperial: {
        var u = String(wd.unit || "").replace(/^\s+|\s+$/g, "").toLowerCase()
        if (u === "imperial") return true
        if (u === "metric") return false
        var byCountry = wd._countryUsesImperial(wd._countryCode)
        if (byCountry !== null) return byCountry
        return wd._localeUsesImperial(Qt.locale().name)
    }

    readonly property string tempSymbol: "°" + (wd.useImperial ? "F" : "C")
    readonly property string windUnit: wd.useImperial ? "mph" : "km/h"

    function _displayTemp(celsius) {
        var n = parseFloat(celsius)
        if (isNaN(n)) return NaN
        return Math.round(wd.useImperial ? n * 9 / 5 + 32 : n)
    }

    function _displayWind(kmh) {
        var n = parseFloat(kmh)
        if (isNaN(n)) return NaN
        return Math.round(wd.useImperial ? n * 0.621371 : n)
    }

    // ── Scheduling ──────────────────────────────────────────────────────
    property var _refreshTimer: Timer {
        interval: Math.max(1, wd.refreshMinutes || 15) * 60000
        // The gate: no timer, so no fetch, while the screen is off. Restarting
        // re-fires triggeredOnStart, so a screen coming back after a long
        // switched-off spell fetches immediately instead of waiting out the
        // rest of a 15-minute interval with a stale reading on it.
        running: wd.active
        repeat: true
        // Same as Omarchy's refreshTimer: the first tick IS the first fetch.
        // It goes through the coalescing path because at this point the bar
        // has not injected `settings` yet.
        triggeredOnStart: true
        onTriggered: Qt.callLater(wd._refreshFromConfig)
    }

    // Monotonic request id: a response whose id no longer matches is stale
    // and is dropped.
    property int _reqSeq: 0

    // Flat retry, capped per refresh cycle, matching Panel.qml:367-390. The
    // old exponential schedule climbed to five minutes and then kept going,
    // which on a laptop that had merely closed its lid meant a stale reading
    // and a permanently spinning request loop.
    readonly property int _maxRetries: 3
    property int _failCount: 0

    property var _retryTimer: Timer {
        interval: 2500
        repeat: false
        onTriggered: if (wd.active) wd._resolveAndFetch()
    }

    // A retry already pending when the screen goes off is dropped rather than
    // fired into a tile nobody can see; the refresh timer's restart fetches
    // afresh when the screen comes back.
    onActiveChanged: if (!wd.active) wd._retryTimer.stop()

    function _scheduleRetry() {
        if (wd._failCount >= wd._maxRetries) return
        wd._failCount = wd._failCount + 1
        wd._retryTimer.restart()
    }

    function _clearRetry() {
        wd._failCount = 0
        wd._retryTimer.stop()
    }

    function forceRefresh() {
        wd._shared._file.reload()
        wd._refreshFromConfig()
    }

    // Each refresh cycle gets a fresh retry budget, so an exhausted round does
    // not starve the rest of the session.
    function _refreshFromConfig() {
        wd._clearRetry()
        wd._resolveAndFetch()
    }

    function _resolveAndFetch() {
        var name = wd.resolvedLocation

        if (name === "" && !wd._hasStoredCoordinates) {
            // Nothing configured anywhere: ask wttr.in which city this IP is
            // in, the same question `omarchy-weather-location` asks.
            if (!detectProc.running) detectProc.running = true
            return
        }

        if (name !== "") wd.cityName = name

        // Geocode whenever the name is new - it is the only source of both the
        // canonical display name and the country the unit rule needs. With
        // stored coordinates it is enrichment, not a prerequisite, so a failed
        // geocode still fetches weather below.
        if (name !== "" && wd._geocodedFor !== name) {
            wd._geocode(name)
            return
        }

        wd._fetchWeather()
    }

    // Coalesced, not immediate: the bar assigns `settings` one property at a
    // time after construction, so a cold start walks location -> unit ->
    // refreshMinutes and direct calls fired one fetch per step. Qt.callLater
    // de-duplicates by function reference, collapsing the burst into one pass.
    onLocationChanged: Qt.callLater(wd._refreshFromConfig)
    onResolvedLocationChanged: Qt.callLater(wd._refreshFromConfig)
    onResolvedLatitudeChanged: Qt.callLater(wd._refreshFromConfig)
    onResolvedLongitudeChanged: Qt.callLater(wd._refreshFromConfig)

    // A unit change is pure presentation - the report is cached in metric.
    onUseImperialChanged: if (wd._report) wd._render()

    // ── IP auto-detect ──────────────────────────────────────────────────
    // A Process, not an XMLHttpRequest: this is the shell's own idiom for
    // shelling out (Panel.qml:456-467, and TailscaleData.qml here), and
    // `curl` gives the same 4-second deadline Omarchy uses. The answer is one
    // short line, so 4 KB is a generous cap.
    property Process _detectProc: Process {
        id: detectProc
        command: ["curl", "-fsS", "--proto", "=https", "--max-time", "4",
                  "--max-filesize", "4096", "https://wttr.in/?format=%l"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                // "Riyadh, Saudi Arabia" - the city is the first field.
                var raw = String(this.text || "").replace(/^\s+|\s+$/g, "")
                if (raw === "") return
                wd._detectedName = raw.split(",")[0].replace(/^\s+|\s+$/g, "")
            }
        }
        onExited: function (exitCode) {
            if (exitCode !== 0 && wd._detectedName === "") {
                wd.errorMessage = "Network error"
                wd.isLoading = false
                wd._scheduleRetry()
            }
        }
    }

    // ── Icons, conditions, gradients: this widget's own vocabulary ──────
    function iconNameForCode(code, night) {
        if (code === 0) return night ? "clearnight" : "sunny"
        if (code === 1 || code === 2) return night ? "partlycloudynight" : "partlysunny"
        if (code === 3) return "cloudy"
        if (code === 45 || code === 48) return "fog"
        if (code === 51 || code === 53 || code === 55) return night ? "nightdrizzle" : "drizzle"
        if (code === 56 || code === 57) return "sleet"
        if (code === 61 || code === 63) return "rain"
        if (code === 65) return "heavyrain"
        if (code === 66 || code === 67) return "sleet"
        if (code === 71 || code === 73 || code === 75) return "snow"
        if (code === 77) return "scatteredsnow"
        if (code === 80 || code === 81) return "rain"
        if (code === 82) return "heavyrain"
        if (code === 85 || code === 86) return "scatteredsnow"
        if (code === 95 || code === 96 || code === 99) return "thunderbolt"
        return night ? "clearnight" : "sunny"
    }

    function conditionForCode(code) {
        if (code === 0) return "Clear"
        if (code === 1) return "Mainly Clear"
        if (code === 2) return "Partly Cloudy"
        if (code === 3) return "Overcast"
        if (code === 45) return "Fog"
        if (code === 48) return "Rime Fog"
        if (code === 51) return "Light Drizzle"
        if (code === 53) return "Drizzle"
        if (code === 55) return "Dense Drizzle"
        if (code === 56) return "Freezing Drizzle"
        if (code === 57) return "Heavy Freezing Drizzle"
        if (code === 61) return "Slight Rain"
        if (code === 63) return "Rain"
        if (code === 65) return "Heavy Rain"
        if (code === 66) return "Freezing Rain"
        if (code === 67) return "Heavy Freezing Rain"
        if (code === 71) return "Slight Snow"
        if (code === 73) return "Snow"
        if (code === 75) return "Heavy Snow"
        if (code === 77) return "Snow Grains"
        if (code === 80) return "Light Showers"
        if (code === 81) return "Showers"
        if (code === 82) return "Heavy Showers"
        if (code === 85) return "Light Snow Showers"
        if (code === 86) return "Heavy Snow Showers"
        if (code === 95) return "Thunderstorm"
        if (code === 96) return "Thunderstorm with Hail"
        if (code === 99) return "Heavy Thunderstorm"
        return "Unknown"
    }

    function _gradientCategoryForCode(code, night) {
        if (code === 0 || code === 1) return night ? "nightclear" : "clear"
        if (code === 2) return night ? "nightcloudy" : "clear"
        if (code === 3) return "cloudy"
        if (code === 45 || code === 48) return "fog"
        if (code >= 51 && code <= 67) return "rain"
        if (code >= 80 && code <= 82) return "rain"
        if (code >= 71 && code <= 77) return "snow"
        if (code === 85 || code === 86) return "snow"
        if (code >= 95) return "storm"
        return night ? "nightclear" : "clear"
    }

    function _compassDirection(degrees) {
        var dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        var idx = Math.round(degrees / 45) % 8
        return dirs[idx]
    }

    function _formatHour(date) {
        var h = date.getHours()
        var m = date.getMinutes()
        var ampm = h >= 12 ? "PM" : "AM"
        var dh = h % 12
        if (dh === 0) dh = 12
        if (m > 0) return dh + ":" + (m < 10 ? "0" + m : m) + " " + ampm
        return dh + " " + ampm
    }

    function _isNightTime(now, sunrise, sunset) {
        if (sunrise && sunset) return now < sunrise || now >= sunset
        var h = now.getHours()
        return h < 7 || h >= 19
    }

    // ── Network ─────────────────────────────────────────────────────────
    // Every request is a `curl` child, never an in-shell XMLHttpRequest. QML's
    // XMLHttpRequest has no deadline and no size limit: it buffers whatever the
    // server sends, for as long as it takes, inside the desktop shell. curl
    // enforces both before a byte reaches us - `--max-time` ends a stalled
    // transfer and `--max-filesize` aborts one that grows past the cap, with
    // or without a Content-Length (curl >= 8.4) - so the most a response can
    // cost the shell is `_httpMaxBytes`.
    //
    // At most one request is ever in flight: starting one kills the previous,
    // so a stalled transfer cannot pile up behind later refreshes. Its output,
    // if any arrives, is dropped by the `seq` check, and the object is
    // destroyed rather than left to finish.
    //
    // The endpoints and limits are properties so tests/weather-http.sh can
    // point them at a local server; nothing in the plugin sets them.
    property string _geocodeEndpoint: "https://geocoding-api.open-meteo.com/v1/search"
    property string _forecastEndpoint: "https://api.open-meteo.com/v1/forecast"
    property string _httpProtocols: "=https"
    property int _httpTimeoutSec: 10
    // A seven-day forecast is ~15 KB and a geocode under 2 KB.
    property int _httpMaxBytes: 1048576

    property Process _http: null

    property Component _httpComponent: Component {
        Process {
            id: req
            property int seq: 0
            property var handler: null
            property string body: ""
            property bool _streamDone: false
            property bool _exited: false
            property int _exitCode: -1
            stdout: StdioCollector {
                waitForEnd: true
                onStreamFinished: {
                    req.body = String(this.text || "")
                    req._streamDone = true
                    req._settle()
                }
            }
            onExited: function (exitCode) {
                req._exitCode = exitCode
                req._exited = true
                req._settle()
            }
            // Both halves, in whichever order they arrive: the exit code says
            // whether curl finished, the stream holds what it got.
            function _settle() {
                if (!req._streamDone || !req._exited) return
                wd._httpSettled(req)
            }
        }
    }

    // GET `url`; `handler(status, body)` runs only if this is still the newest
    // request. `status` is the HTTP status, or 0 when curl gave up (network
    // error, deadline, size cap).
    function _httpGet(url, handler) {
        wd._cancelHttp()
        wd._reqSeq = wd._reqSeq + 1
        var p = wd._httpComponent.createObject(wd, {
            seq: wd._reqSeq,
            handler: handler,
            command: ["curl", "-sS",
                      "--proto", wd._httpProtocols,
                      "--max-time", String(wd._httpTimeoutSec),
                      "--max-filesize", String(wd._httpMaxBytes),
                      "-w", "\n%{http_code}",
                      url]
        })
        wd._http = p
        p.running = true
    }

    function _cancelHttp() {
        var p = wd._http
        wd._http = null
        if (!p) return
        if (p.running) p.running = false
        p.destroy()
    }

    function _httpSettled(p) {
        // Superseded or cancelled: nothing it says is current.
        if (!wd || p !== wd._http || p.seq !== wd._reqSeq) return
        wd._http = null
        var text = p.body
        var cut = text.lastIndexOf("\n")
        // `-w` writes the status after the body; a curl that gave up still
        // writes it, as 000, and its exit code says it gave up.
        var status = p._exitCode === 0 && cut >= 0 ? (parseInt(text.slice(cut + 1), 10) || 0) : 0
        var body = cut >= 0 ? text.slice(0, cut) : ""
        var handler = p.handler
        p.destroy()
        handler(status, body)
    }

    function _geocode(name) {
        wd.isLoading = true
        var url = wd._geocodeEndpoint + "?name=" +
                  encodeURIComponent(name) + "&count=1&language=en&format=json"

        wd._httpGet(url, function (status, body) {
            var hit = null
            if (status === 200) {
                try {
                    var resp = JSON.parse(body)
                    if (resp.results && resp.results.length > 0) hit = resp.results[0]
                } catch (e) {
                    hit = null
                }
            }

            if (hit) {
                wd._geoLatitude = hit.latitude
                wd._geoLongitude = hit.longitude
                wd._countryCode = String(hit.country_code || "")
                wd._geocodedFor = name
                wd.cityName = hit.name || name
                wd.errorMessage = ""
                wd._fetchWeather()
                return
            }

            // Stored coordinates make the geocode optional: fetch anyway and
            // let the unit rule fall back to the locale.
            if (wd._hasStoredCoordinates) {
                wd._fetchWeather()
                return
            }

            wd.isLoading = false
            if (status === 200) {
                // The city does not exist. Retrying cannot change that, so the
                // budget is spent on transient faults instead.
                wd.errorMessage = "Location not found"
                wd._clearRetry()
            } else {
                wd.errorMessage = "Network error"
                wd._scheduleRetry()
            }
        })
    }

    function _fetchWeather() {
        var lat = wd._latitude()
        var lon = wd._longitude()
        if (lat === 0 && lon === 0) {
            wd._resolveAndFetch()
            return
        }

        // Always metric, like Omarchy: °F and mph are computed here, so the
        // unit setting is a render-time decision and never a refetch.
        var url = wd._forecastEndpoint + "?" +
                  "latitude=" + lat +
                  "&longitude=" + lon +
                  "&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m" +
                  "&hourly=temperature_2m,weather_code" +
                  "&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset" +
                  "&wind_speed_unit=kmh" +
                  "&timezone=auto" +
                  "&forecast_days=7"

        wd._httpGet(url, function (status, body) {
            if (status === 200) {
                try {
                    wd._report = JSON.parse(body)
                    wd._render()
                    wd.isLoading = false
                    wd.errorMessage = ""
                    wd._clearRetry()
                    return
                } catch (e) {
                    wd.errorMessage = "Error parsing weather"
                }
            } else {
                wd.errorMessage = "Failed to fetch weather"
            }
            // Whatever is already rendered stays rendered: an unreachable API
            // is no reason to throw away this morning's temperature.
            wd.isLoading = false
            wd._scheduleRetry()
        })
    }

    // A tile torn down mid-request takes its request with it.
    Component.onDestruction: wd._cancelHttp()

    // ── Rendering ───────────────────────────────────────────────────────
    // The last good response, in metric, so a unit flip re-renders offline.
    property var _report: null

    function _render() {
        var resp = wd._report
        if (!resp) return
        var now = new Date()

        if (resp.daily) {
            wd.todaySunrise = new Date(resp.daily.sunrise[0])
            wd.todaySunset = new Date(resp.daily.sunset[0])
        }

        wd.isNight = wd._isNightTime(now, wd.todaySunrise, wd.todaySunset)

        if (resp.current) {
            wd.currentTemp = String(wd._displayTemp(resp.current.temperature_2m))
            wd.weatherCode = resp.current.weather_code || 0
            wd.condition = wd.conditionForCode(wd.weatherCode)
            wd.windSpeed = String(wd._displayWind(resp.current.wind_speed_10m))
            wd.windDirection = wd._compassDirection(resp.current.wind_direction_10m || 0)
            wd.gradientCategory = wd._gradientCategoryForCode(wd.weatherCode, wd.isNight)
        }

        if (resp.daily) {
            wd.highTemp = String(wd._displayTemp(resp.daily.temperature_2m_max[0]))
            wd.lowTemp = String(wd._displayTemp(resp.daily.temperature_2m_min[0]))
            wd._processDailyForecast(resp.daily)
            wd._computePrecipitationSummary(resp.daily)
        }

        if (resp.hourly) {
            wd._processHourlyForecast(resp.hourly, resp.daily)
        }
    }

    function _processDailyForecast(daily) {
        var days = []
        var dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var minL = Infinity
        var maxH = -Infinity

        for (var i = 1; i <= 5; i++) {
            if (i >= daily.temperature_2m_max.length) break
            var d = new Date()
            d.setDate(d.getDate() + i)
            var hi = wd._displayTemp(daily.temperature_2m_max[i])
            var lo = wd._displayTemp(daily.temperature_2m_min[i])
            if (lo < minL) minL = lo
            if (hi > maxH) maxH = hi

            days.push({
                day: dayNames[d.getDay()],
                weatherCode: daily.weather_code[i],
                high: hi.toString(),
                low: lo.toString()
            })
        }

        var todayHi = wd._displayTemp(daily.temperature_2m_max[0])
        var todayLo = wd._displayTemp(daily.temperature_2m_min[0])
        if (todayLo < minL) minL = todayLo
        if (todayHi > maxH) maxH = todayHi

        wd.overallLow = minL
        wd.overallHigh = maxH
        wd.dailyForecast = days
    }

    function _isPrecipCode(code) {
        return (code >= 51 && code <= 67) || (code >= 71 && code <= 77) ||
               (code >= 80 && code <= 86) || (code >= 95 && code <= 99)
    }

    function _computePrecipitationSummary(daily) {
        if (!daily || !daily.weather_code) {
            wd.precipitationSummary = ""
            return
        }
        var codes = daily.weather_code
        var dryDays = 0
        for (var i = 0; i < codes.length; i++) {
            if (wd._isPrecipCode(codes[i])) break
            dryDays++
        }
        if (dryDays === 0)
            wd.precipitationSummary = "Precipitation expected today"
        else if (dryDays === 1)
            wd.precipitationSummary = "Precipitation expected tomorrow"
        else
            wd.precipitationSummary = "No precipitation for " + dryDays + " days"
    }

    function _processHourlyForecast(hourly, daily) {
        var now = new Date()

        var sunrise = daily ? new Date(daily.sunrise[0]) : null
        var sunset = daily ? new Date(daily.sunset[0]) : null

        var rawSlots = []
        for (var i = 0; i < hourly.time.length && rawSlots.length < 7; i++) {
            var t = new Date(hourly.time[i])
            if (t.getTime() <= now.getTime()) continue

            var slotNight = wd._isNightTime(t, sunrise, sunset)
            rawSlots.push({
                time: t,
                displayTime: wd._formatHour(t),
                temp: String(wd._displayTemp(hourly.temperature_2m[i])),
                iconName: wd.iconNameForCode(hourly.weather_code[i], slotNight),
                isSunEvent: false,
                sunEventType: ""
            })
        }

        var sunEvents = []
        if (sunrise && sunrise.getTime() > now.getTime() &&
            rawSlots.length > 0 && sunrise.getTime() < rawSlots[rawSlots.length - 1].time.getTime()) {
            sunEvents.push({
                time: sunrise,
                displayTime: wd._formatHour(sunrise),
                temp: "",
                iconName: "sunrise",
                isSunEvent: true,
                sunEventType: "Sunrise"
            })
        }
        if (sunset && sunset.getTime() > now.getTime() &&
            rawSlots.length > 0 && sunset.getTime() < rawSlots[rawSlots.length - 1].time.getTime()) {
            sunEvents.push({
                time: sunset,
                displayTime: wd._formatHour(sunset),
                temp: "",
                iconName: "sunset",
                isSunEvent: true,
                sunEventType: "Sunset"
            })
        }

        var merged = rawSlots.concat(sunEvents)
        merged.sort(function(a, b) { return a.time.getTime() - b.time.getTime() })

        wd.hourlySlots = merged.slice(0, 6)
    }
}
