.pragma library

// IANA timezone -> { code, name } lookup for the City world-clock widgets.
//
// `code` is a short 2-4 letter city code (airport-ish / colloquial) shown in
// the compact 1x1 and 2x2 annotations; `name` is the full city label shown in
// the 4x2 info block. Collection of common world-clock picks (~150 zones).
//
// Unmapped zones fall back (see lookup()) to a name derived from the IANA
// city segment (e.g. "Asia/Kolkata" -> "Kolkata") and a code derived from
// that name's leading letters.

var TABLE = {
    // --- North America ---
    "America/New_York":       { code: "NYC",  name: "New York" },
    "America/Detroit":        { code: "DET",  name: "Detroit" },
    "America/Toronto":        { code: "YYZ",  name: "Toronto" },
    "America/Montreal":       { code: "YUL",  name: "Montreal" },
    "America/Chicago":        { code: "CHI",  name: "Chicago" },
    "America/Winnipeg":       { code: "YWG",  name: "Winnipeg" },
    "America/Mexico_City":    { code: "MEX",  name: "Mexico City" },
    "America/Denver":         { code: "DEN",  name: "Denver" },
    "America/Phoenix":        { code: "PHX",  name: "Phoenix" },
    "America/Edmonton":       { code: "YEG",  name: "Edmonton" },
    "America/Los_Angeles":    { code: "LAX",  name: "Los Angeles" },
    "America/Vancouver":      { code: "YVR",  name: "Vancouver" },
    "America/Tijuana":        { code: "TIJ",  name: "Tijuana" },
    "America/Anchorage":      { code: "ANC",  name: "Anchorage" },
    "America/Halifax":        { code: "YHZ",  name: "Halifax" },
    "America/St_Johns":       { code: "YYT",  name: "St. John's" },
    "America/Havana":         { code: "HAV",  name: "Havana" },
    "Pacific/Honolulu":       { code: "HNL",  name: "Honolulu" },

    // --- Central / South America ---
    "America/Guatemala":      { code: "GUA",  name: "Guatemala City" },
    "America/Panama":         { code: "PTY",  name: "Panama City" },
    "America/Bogota":         { code: "BOG",  name: "Bogotá" },
    "America/Lima":           { code: "LIM",  name: "Lima" },
    "America/Caracas":        { code: "CCS",  name: "Caracas" },
    "America/La_Paz":         { code: "LPB",  name: "La Paz" },
    "America/Santiago":       { code: "SCL",  name: "Santiago" },
    "America/Argentina/Buenos_Aires": { code: "BUE", name: "Buenos Aires" },
    "America/Montevideo":     { code: "MVD",  name: "Montevideo" },
    "America/Sao_Paulo":      { code: "SAO",  name: "São Paulo" },
    "America/Asuncion":       { code: "ASU",  name: "Asunción" },

    // --- Europe ---
    "Atlantic/Reykjavik":     { code: "REK",  name: "Reykjavík" },
    "Europe/Lisbon":          { code: "LIS",  name: "Lisbon" },
    "Europe/Dublin":          { code: "DUB",  name: "Dublin" },
    "Europe/London":          { code: "LON",  name: "London" },
    "Europe/Madrid":          { code: "MAD",  name: "Madrid" },
    "Europe/Paris":           { code: "PAR",  name: "Paris" },
    "Europe/Brussels":        { code: "BRU",  name: "Brussels" },
    "Europe/Amsterdam":       { code: "AMS",  name: "Amsterdam" },
    "Europe/Berlin":          { code: "BER",  name: "Berlin" },
    "Europe/Zurich":          { code: "ZRH",  name: "Zürich" },
    "Europe/Rome":            { code: "ROM",  name: "Rome" },
    "Europe/Vienna":          { code: "VIE",  name: "Vienna" },
    "Europe/Prague":          { code: "PRG",  name: "Prague" },
    "Europe/Copenhagen":      { code: "CPH",  name: "Copenhagen" },
    "Europe/Oslo":            { code: "OSL",  name: "Oslo" },
    "Europe/Stockholm":       { code: "STO",  name: "Stockholm" },
    "Europe/Warsaw":          { code: "WAW",  name: "Warsaw" },
    "Europe/Budapest":        { code: "BUD",  name: "Budapest" },
    "Europe/Belgrade":        { code: "BEG",  name: "Belgrade" },
    "Europe/Athens":          { code: "ATH",  name: "Athens" },
    "Europe/Bucharest":       { code: "OTP",  name: "Bucharest" },
    "Europe/Helsinki":        { code: "HEL",  name: "Helsinki" },
    "Europe/Kyiv":            { code: "KBP",  name: "Kyiv" },
    "Europe/Kiev":            { code: "KBP",  name: "Kyiv" },
    "Europe/Istanbul":        { code: "IST",  name: "Istanbul" },
    "Europe/Moscow":          { code: "MOW",  name: "Moscow" },

    // --- Africa ---
    "Africa/Casablanca":      { code: "CMN",  name: "Casablanca" },
    "Africa/Lagos":           { code: "LOS",  name: "Lagos" },
    "Africa/Accra":           { code: "ACC",  name: "Accra" },
    "Africa/Algiers":         { code: "ALG",  name: "Algiers" },
    "Africa/Tunis":           { code: "TUN",  name: "Tunis" },
    "Africa/Cairo":           { code: "CAI",  name: "Cairo" },
    "Africa/Johannesburg":    { code: "JNB",  name: "Johannesburg" },
    "Africa/Cape_Town":       { code: "CPT",  name: "Cape Town" },
    "Africa/Nairobi":         { code: "NBO",  name: "Nairobi" },
    "Africa/Addis_Ababa":     { code: "ADD",  name: "Addis Ababa" },
    "Africa/Kampala":         { code: "KLA",  name: "Kampala" },
    "Africa/Kinshasa":        { code: "FIH",  name: "Kinshasa" },

    // --- Middle East / West Asia ---
    "Asia/Jerusalem":         { code: "JLM",  name: "Jerusalem" },
    "Asia/Beirut":            { code: "BEY",  name: "Beirut" },
    "Asia/Amman":             { code: "AMM",  name: "Amman" },
    "Asia/Riyadh":            { code: "RUH",  name: "Riyadh" },
    "Asia/Qatar":             { code: "DOH",  name: "Doha" },
    "Asia/Dubai":             { code: "DXB",  name: "Dubai" },
    "Asia/Tehran":            { code: "THR",  name: "Tehran" },
    "Asia/Baghdad":           { code: "BGW",  name: "Baghdad" },
    "Asia/Kuwait":            { code: "KWI",  name: "Kuwait City" },
    "Asia/Baku":              { code: "GYD",  name: "Baku" },
    "Asia/Yerevan":           { code: "EVN",  name: "Yerevan" },
    "Asia/Tbilisi":           { code: "TBS",  name: "Tbilisi" },

    // --- Central / South Asia ---
    "Asia/Karachi":           { code: "KHI",  name: "Karachi" },
    "Asia/Tashkent":          { code: "TAS",  name: "Tashkent" },
    "Asia/Kabul":             { code: "KBL",  name: "Kabul" },
    "Asia/Kolkata":           { code: "DEL",  name: "Mumbai" },
    "Asia/Calcutta":          { code: "DEL",  name: "Mumbai" },
    "Asia/Colombo":           { code: "CMB",  name: "Colombo" },
    "Asia/Kathmandu":         { code: "KTM",  name: "Kathmandu" },
    "Asia/Dhaka":             { code: "DAC",  name: "Dhaka" },
    "Asia/Almaty":            { code: "ALA",  name: "Almaty" },

    // --- East / Southeast Asia ---
    "Asia/Yangon":            { code: "RGN",  name: "Yangon" },
    "Asia/Bangkok":           { code: "BKK",  name: "Bangkok" },
    "Asia/Jakarta":           { code: "JKT",  name: "Jakarta" },
    "Asia/Ho_Chi_Minh":       { code: "SGN",  name: "Ho Chi Minh City" },
    "Asia/Saigon":            { code: "SGN",  name: "Ho Chi Minh City" },
    "Asia/Kuala_Lumpur":      { code: "KUL",  name: "Kuala Lumpur" },
    "Asia/Singapore":         { code: "SIN",  name: "Singapore" },
    "Asia/Manila":            { code: "MNL",  name: "Manila" },
    "Asia/Hong_Kong":         { code: "HKG",  name: "Hong Kong" },
    "Asia/Taipei":            { code: "TPE",  name: "Taipei" },
    "Asia/Shanghai":          { code: "SHA",  name: "Shanghai" },
    "Asia/Chongqing":         { code: "CKG",  name: "Chongqing" },
    "Asia/Urumqi":            { code: "URC",  name: "Ürümqi" },
    "Asia/Seoul":             { code: "SEL",  name: "Seoul" },
    "Asia/Pyongyang":         { code: "FNJ",  name: "Pyongyang" },
    "Asia/Tokyo":             { code: "TYO",  name: "Tokyo" },
    "Asia/Ulaanbaatar":       { code: "ULN",  name: "Ulaanbaatar" },
    "Asia/Vladivostok":       { code: "VVO",  name: "Vladivostok" },
    "Asia/Yekaterinburg":     { code: "SVX",  name: "Yekaterinburg" },
    "Asia/Novosibirsk":       { code: "OVB",  name: "Novosibirsk" },
    "Asia/Krasnoyarsk":       { code: "KJA",  name: "Krasnoyarsk" },

    // --- Oceania ---
    "Australia/Perth":        { code: "PER",  name: "Perth" },
    "Australia/Adelaide":     { code: "ADL",  name: "Adelaide" },
    "Australia/Darwin":       { code: "DRW",  name: "Darwin" },
    "Australia/Brisbane":     { code: "BNE",  name: "Brisbane" },
    "Australia/Sydney":       { code: "SYD",  name: "Sydney" },
    "Australia/Melbourne":    { code: "MEL",  name: "Melbourne" },
    "Australia/Hobart":       { code: "HBA",  name: "Hobart" },
    "Pacific/Auckland":       { code: "AKL",  name: "Auckland" },
    "Pacific/Fiji":           { code: "SUV",  name: "Suva" },
    "Pacific/Port_Moresby":   { code: "POM",  name: "Port Moresby" },
    "Pacific/Guam":           { code: "GUM",  name: "Guam" },
    "Pacific/Tongatapu":      { code: "TBU",  name: "Nukuʻalofa" },
    "Pacific/Pago_Pago":      { code: "PPG",  name: "Pago Pago" }
};

// Title-case the IANA city segment, turning underscores into spaces.
// "Asia/Kuala_Lumpur" -> "Kuala Lumpur", "Australia/Lord_Howe" -> "Lord Howe"
function _nameFromTz(tz) {
    if (!tz)
        return "";
    var seg = String(tz).split("/").pop().replace(/_/g, " ");
    return seg.replace(/\b\w/g, function (c) { return c.toUpperCase(); });
}

// Derive a short code from a city name: first letters of up to the first three
// words, uppercased. "New York" -> "NY", "Los Angeles" -> "LA", "Lima" -> "LIM".
function _codeFromName(name) {
    if (!name)
        return "";
    var words = name.split(" ").filter(function (w) { return w.length > 0; });
    if (words.length >= 2)
        return words.slice(0, 3).map(function (w) { return w[0]; }).join("").toUpperCase();
    return name.slice(0, 3).toUpperCase();
}

// Resolve a timezone id to { code, name }. Falls back to a derived name/code
// for any zone not in TABLE so the UI always has something to show.
function lookup(tz) {
    if (tz && TABLE.hasOwnProperty(tz))
        return TABLE[tz];
    var name = _nameFromTz(tz);
    return { code: _codeFromName(name), name: name };
}
