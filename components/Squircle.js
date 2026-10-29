.pragma library

// The outline liquidglass.frag draws for a card, as a closed polyline the scene
// graph can fill (a Shape's PathPolyline) or a Canvas can trace.
//
// The shader's corner is a superellipse: q = abs(p) - b + r, and
// (qx^n + qy^n)^(1/n) = r, so parametrically qx = r*cos(t)^(2/n) and
// qy = r*sin(t)^(2/n). The clamps are the shader's own (liquidglass.frag:70-71):
// the exponent is at least 2, a circle, and the radius at most half the shorter
// side. A plain `Rectangle { radius }` is not this curve, and clamped to half a
// 192 px tile it is a disc. 32 steps a corner, starting and ending at (r, 0).
function outline(w, h, radius, roundness) {
    var r = Math.max(0, Math.min(radius, w / 2, h / 2))
    var n = Math.max(roundness, 2.0)
    var steps = 32
    var pts = []

    function cornerX(t) { return r * Math.pow(Math.abs(Math.cos(t)), 2.0 / n) }
    function cornerY(t) { return r * Math.pow(Math.abs(Math.sin(t)), 2.0 / n) }

    pts.push(Qt.point(r, 0))
    pts.push(Qt.point(w - r, 0))
    for (var i = 1; i <= steps; i++) {
        var t = (1 - i / steps) * Math.PI / 2
        pts.push(Qt.point(w - r + cornerX(t), r - cornerY(t)))
    }
    pts.push(Qt.point(w, h - r))
    for (var j = 1; j <= steps; j++) {
        var t2 = (1 - j / steps) * Math.PI / 2
        pts.push(Qt.point(w - r + cornerY(t2), h - r + cornerX(t2)))
    }
    pts.push(Qt.point(r, h))
    for (var k = 1; k <= steps; k++) {
        var t3 = (1 - k / steps) * Math.PI / 2
        pts.push(Qt.point(r - cornerX(t3), h - r + cornerY(t3)))
    }
    pts.push(Qt.point(0, r))
    for (var m = 1; m <= steps; m++) {
        var t4 = (1 - m / steps) * Math.PI / 2
        pts.push(Qt.point(r - cornerY(t4), r - cornerX(t4)))
    }
    pts.push(Qt.point(r, 0))
    return pts
}
