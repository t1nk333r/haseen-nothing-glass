import QtQuick

QtObject {
    id: wd

    property string location: "New York"
    property double configLatitude: 0
    property double configLongitude: 0
    property int temperatureUnit: 0

    property bool isLoading: true
    property string errorMessage: ""
    property string cityName: ""

    property string currentTemp: "--"
    property string highTemp: "--"
    property string lowTemp: "--"
    property int weatherCode: 0
    property string condition: i18n("Loading...")
    property string windSpeed: "--"
    property string windDirection: ""
    property string windUnit: "km/h"

    property var todaySunrise: null
    property var todaySunset: null
    property bool isNight: false

    property string gradientCategory: "clear"
    property string precipitationSummary: ""
    property var hourlySlots: []
    property var dailyForecast: []
    property real overallLow: 0
    property real overallHigh: 100

    property double _latitude: 0
    property double _longitude: 0

    readonly property string tempSymbol: temperatureUnit === 0 ? "°" : "°"

    property var _refreshTimer: Timer {
        interval: 1800000
        running: true
        repeat: true
        onTriggered: wd._fetchWeather()
    }

    property int _failCount: 0
    readonly property var _backoffSchedule: [5000, 10000, 20000, 40000, 80000, 160000, 300000]

    property var _retryTimer: Timer {
        interval: 5000
        repeat: false
        onTriggered: {
            if (wd._latitude === 0 && wd._longitude === 0)
                wd._geocodeAndFetch()
            else
                wd._fetchWeather()
        }
    }

    function _scheduleRetry() {
        _failCount = Math.min(_failCount + 1, _backoffSchedule.length - 1)
        _retryTimer.interval = _backoffSchedule[_failCount]
        _retryTimer.restart()
    }

    function _clearRetry() {
        _failCount = 0
        _retryTimer.stop()
    }

    function forceRefresh() {
        _retryTimer.stop()
        _failCount = 0
        if (_latitude === 0 && _longitude === 0)
            _geocodeAndFetch()
        else
            _fetchWeather()
    }

    function _refreshFromConfig() {
        _retryTimer.stop()
        _failCount = 0
        if (configLatitude !== 0 || configLongitude !== 0) {
            _latitude = configLatitude
            _longitude = configLongitude
            cityName = location
            _fetchWeather()
        } else {
            _geocodeAndFetch()
        }
    }

    onLocationChanged: _refreshFromConfig()
    onConfigLatitudeChanged: _refreshFromConfig()
    onConfigLongitudeChanged: _refreshFromConfig()
    onTemperatureUnitChanged: {
        if (_latitude !== 0 || _longitude !== 0) _fetchWeather()
    }

    Component.onCompleted: _refreshFromConfig()

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
        if (code === 0) return i18n("Clear")
        if (code === 1) return i18n("Mainly Clear")
        if (code === 2) return i18n("Partly Cloudy")
        if (code === 3) return i18n("Overcast")
        if (code === 45) return i18n("Fog")
        if (code === 48) return i18n("Rime Fog")
        if (code === 51) return i18n("Light Drizzle")
        if (code === 53) return i18n("Drizzle")
        if (code === 55) return i18n("Dense Drizzle")
        if (code === 56) return i18n("Freezing Drizzle")
        if (code === 57) return i18n("Heavy Freezing Drizzle")
        if (code === 61) return i18n("Slight Rain")
        if (code === 63) return i18n("Rain")
        if (code === 65) return i18n("Heavy Rain")
        if (code === 66) return i18n("Freezing Rain")
        if (code === 67) return i18n("Heavy Freezing Rain")
        if (code === 71) return i18n("Slight Snow")
        if (code === 73) return i18n("Snow")
        if (code === 75) return i18n("Heavy Snow")
        if (code === 77) return i18n("Snow Grains")
        if (code === 80) return i18n("Light Showers")
        if (code === 81) return i18n("Showers")
        if (code === 82) return i18n("Heavy Showers")
        if (code === 85) return i18n("Light Snow Showers")
        if (code === 86) return i18n("Heavy Snow Showers")
        if (code === 95) return i18n("Thunderstorm")
        if (code === 96) return i18n("Thunderstorm with Hail")
        if (code === 99) return i18n("Heavy Thunderstorm")
        return i18n("Unknown")
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

    function _geocodeAndFetch() {
        isLoading = true
        errorMessage = ""

        var xhr = new XMLHttpRequest()
        var url = "https://geocoding-api.open-meteo.com/v1/search?name=" +
                  encodeURIComponent(location) + "&count=1&language=en&format=json"

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText)
                    if (resp.results && resp.results.length > 0) {
                        _latitude = resp.results[0].latitude
                        _longitude = resp.results[0].longitude
                        cityName = resp.results[0].name || location
                        _fetchWeather()
                    } else {
                        errorMessage = "Location not found"
                        isLoading = false
                        condition = i18n("Location not found")
                        _clearRetry()
                    }
                } catch (e) {
                    errorMessage = "Error parsing location"
                    isLoading = false
                    _scheduleRetry()
                }
            } else {
                errorMessage = "Network error"
                isLoading = false
                _scheduleRetry()
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function _fetchWeather() {
        if (_latitude === 0 && _longitude === 0) {
            _geocodeAndFetch()
            return
        }

        // Compute the unit inline rather than reading the _apiTempUnit binding:
        // when called from onTemperatureUnitChanged, that binding has not been
        // re-evaluated yet and still holds the previous unit (one-step lag).
        var apiUnit = temperatureUnit === 0 ? "celsius" : "fahrenheit"

        var xhr = new XMLHttpRequest()
        var url = "https://api.open-meteo.com/v1/forecast?" +
                  "latitude=" + _latitude +
                  "&longitude=" + _longitude +
                  "&current=temperature_2m,weather_code,wind_speed_10m,wind_direction_10m" +
                  "&hourly=temperature_2m,weather_code" +
                  "&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset" +
                  "&temperature_unit=" + apiUnit +
                  "&wind_speed_unit=kmh" +
                  "&timezone=auto" +
                  "&forecast_days=7"

        xhr.onreadystatechange = function() {
            if (xhr.readyState !== XMLHttpRequest.DONE) return
            if (xhr.status === 200) {
                try {
                    var resp = JSON.parse(xhr.responseText)
                    _processResponse(resp)
                    isLoading = false
                    errorMessage = ""
                    _clearRetry()
                } catch (e) {
                    errorMessage = "Error parsing weather"
                    isLoading = false
                    _scheduleRetry()
                }
            } else {
                errorMessage = "Failed to fetch weather"
                isLoading = false
                _scheduleRetry()
            }
        }
        xhr.open("GET", url)
        xhr.send()
    }

    function _processResponse(resp) {
        var now = new Date()

        if (resp.daily) {
            todaySunrise = new Date(resp.daily.sunrise[0])
            todaySunset = new Date(resp.daily.sunset[0])
        }

        isNight = _isNightTime(now, todaySunrise, todaySunset)

        if (resp.current) {
            currentTemp = Math.round(resp.current.temperature_2m).toString()
            weatherCode = resp.current.weather_code || 0
            condition = conditionForCode(weatherCode)
            windSpeed = Math.round(resp.current.wind_speed_10m).toString()
            windDirection = _compassDirection(resp.current.wind_direction_10m || 0)
            gradientCategory = _gradientCategoryForCode(weatherCode, isNight)
        }

        if (resp.daily) {
            highTemp = Math.round(resp.daily.temperature_2m_max[0]).toString()
            lowTemp = Math.round(resp.daily.temperature_2m_min[0]).toString()
            _processDailyForecast(resp.daily)
            _computePrecipitationSummary(resp.daily)
        }

        if (resp.hourly) {
            _processHourlyForecast(resp.hourly, resp.daily)
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
            var hi = Math.round(daily.temperature_2m_max[i])
            var lo = Math.round(daily.temperature_2m_min[i])
            if (lo < minL) minL = lo
            if (hi > maxH) maxH = hi

            days.push({
                day: dayNames[d.getDay()],
                weatherCode: daily.weather_code[i],
                high: hi.toString(),
                low: lo.toString()
            })
        }

        var todayHi = Math.round(daily.temperature_2m_max[0])
        var todayLo = Math.round(daily.temperature_2m_min[0])
        if (todayLo < minL) minL = todayLo
        if (todayHi > maxH) maxH = todayHi

        overallLow = minL
        overallHigh = maxH
        dailyForecast = days
    }

    function _isPrecipCode(code) {
        return (code >= 51 && code <= 67) || (code >= 71 && code <= 77) ||
               (code >= 80 && code <= 86) || (code >= 95 && code <= 99)
    }

    function _computePrecipitationSummary(daily) {
        if (!daily || !daily.weather_code) {
            precipitationSummary = ""
            return
        }
        var codes = daily.weather_code
        var dryDays = 0
        for (var i = 0; i < codes.length; i++) {
            if (_isPrecipCode(codes[i])) break
            dryDays++
        }
        if (dryDays === 0)
            precipitationSummary = i18n("Precipitation expected today")
        else if (dryDays === 1)
            precipitationSummary = i18n("Precipitation expected tomorrow")
        else
            precipitationSummary = i18np("No precipitation for %1 day", "No precipitation for %1 days", dryDays)
    }

    function _processHourlyForecast(hourly, daily) {
        var now = new Date()
        var currentHour = now.getHours()
        var todayDateStr = now.getFullYear() + "-" +
            String(now.getMonth() + 1).padStart(2, '0') + "-" +
            String(now.getDate()).padStart(2, '0')

        var sunrise = daily ? new Date(daily.sunrise[0]) : null
        var sunset = daily ? new Date(daily.sunset[0]) : null

        var rawSlots = []
        for (var i = 0; i < hourly.time.length && rawSlots.length < 7; i++) {
            var t = new Date(hourly.time[i])
            if (t.getTime() <= now.getTime()) continue

            var slotNight = _isNightTime(t, sunrise, sunset)
            rawSlots.push({
                time: t,
                displayTime: _formatHour(t),
                temp: Math.round(hourly.temperature_2m[i]).toString(),
                iconName: iconNameForCode(hourly.weather_code[i], slotNight),
                isSunEvent: false,
                sunEventType: ""
            })
        }

        var sunEvents = []
        if (sunrise && sunrise.getTime() > now.getTime() &&
            rawSlots.length > 0 && sunrise.getTime() < rawSlots[rawSlots.length - 1].time.getTime()) {
            sunEvents.push({
                time: sunrise,
                displayTime: _formatHour(sunrise),
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
                displayTime: _formatHour(sunset),
                temp: "",
                iconName: "sunset",
                isSunEvent: true,
                sunEventType: "Sunset"
            })
        }

        var merged = rawSlots.concat(sunEvents)
        merged.sort(function(a, b) { return a.time.getTime() - b.time.getTime() })

        hourlySlots = merged.slice(0, 6)
    }
}
