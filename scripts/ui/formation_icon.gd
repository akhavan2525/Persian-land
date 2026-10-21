extends Button
## A round line icon for one battle formation, drawn in code so it stays sharp on every screen.

var kind := ""
var armed := false:
	set(v):
		armed = v
		queue_redraw()

const GOLD := Color("#f2c66d")
const TURQ := Color("#5fe0cf")
const BG := Color(0.07, 0.11, 0.24, 0.88)


func _init() -> void:
	flat = true
	focus_mode = Control.FOCUS_NONE
	custom_minimum_size = Vector2(58, 58)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	draw_circle(c, r, BG)
	var col := TURQ if armed else GOLD
	draw_arc(c, r, 0, TAU, 40, col, 3.0 if armed else 2.0, true)
	var k := r / 26.0      # icons are drawn on a 52-unit circle
	var w := 2.2
	match kind:
		"encircle":
			for i in 8:
				var a := TAU * i / 8.0
				draw_arc(c + Vector2(cos(a), sin(a)) * 15.0 * k, 3.0 * k, 0, TAU, 12, col, w, true)
			draw_line(c + Vector2(-4, -4) * k, c + Vector2(4, 4) * k, col, w, true)
			draw_line(c + Vector2(4, -4) * k, c + Vector2(-4, 4) * k, col, w, true)
		"ambush":
			# a tree with an archer's bow peeking out from behind it
			var t := c + Vector2(-5, 0) * k
			draw_polyline(PackedVector2Array([t + Vector2(-11, 4) * k, t + Vector2(0, -16) * k, t + Vector2(11, 4) * k, t + Vector2(-11, 4) * k]), col, w, true)
			draw_polyline(PackedVector2Array([t + Vector2(-8, 10) * k, t + Vector2(0, -6) * k, t + Vector2(8, 10) * k]), col, w, true)
			draw_line(t + Vector2(0, 10) * k, t + Vector2(0, 16) * k, col, w, true)
			var b := c + Vector2(9, 2) * k
			draw_arc(b, 10.0 * k, -PI * 0.45, PI * 0.45, 16, col, w, true)
			draw_line(b + Vector2(cos(-PI * 0.45), sin(-PI * 0.45)) * 10.0 * k, b + Vector2(cos(PI * 0.45), sin(PI * 0.45)) * 10.0 * k, col, 1.4, true)
			draw_line(b + Vector2(-2, 0) * k, b + Vector2(12, 0) * k, col, 1.6, true)
		"wall":
			for i in 4:
				var x := (i - 1.5) * 9.0
				var rect := Rect2(c + Vector2(x - 3.5, -4) * k, Vector2(7, 13) * k)
				draw_rect(rect, col, false, w)
				draw_line(c + Vector2(x, -4) * k, c + Vector2(x, 9) * k, col, 1.2, true)
			for i in 3:
				draw_circle(c + Vector2((i - 1) * 9.0, -12) * k, 2.0 * k, col)
		"wedge":
			var pts := [Vector2(0, -12), Vector2(-6, -3), Vector2(6, -3), Vector2(-12, 6), Vector2(12, 6), Vector2(-18, 15), Vector2(18, 15)]
			for p in pts:
				draw_circle(c + p * k, 2.6 * k, col)
			draw_polyline(PackedVector2Array([c + Vector2(-7, -15) * k, c + Vector2(0, -22) * k, c + Vector2(7, -15) * k]), col, w, true)
		"ring":
			draw_arc(c, 12.0 * k, 0, TAU, 32, col, w, true)
			for i in 8:
				var a := TAU * i / 8.0 + PI / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * 12.0 * k, c + d * 19.0 * k, col, w, true)
			draw_circle(c, 2.8 * k, col)
