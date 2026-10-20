class_name CameraRig
extends Node3D
## Tilted RTS camera: one-finger drag pans, pinch / mouse wheel zooms.

var cam: Camera3D
var dist := 38.0
var min_dist := 18.0
var max_dist := 90.0
var pitch := deg_to_rad(54.0)
var bounds := 66.0
var _shake := 0.0


func _ready() -> void:
	rotation.y = -PI / 4.0
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.5
	cam.far = 600.0
	add_child(cam)
	cam.current = true
	_apply()


func _apply() -> void:
	position.x = clampf(position.x, -bounds, bounds)
	position.z = clampf(position.z, -bounds, bounds)
	cam.position = Vector3(0, sin(pitch) * dist, cos(pitch) * dist)
	cam.rotation = Vector3(-pitch, 0, 0)
	if _shake > 0.0:
		cam.position += Vector3(randf_range(-1, 1), randf_range(-1, 1), 0) * _shake * 0.3


func _process(delta: float) -> void:
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.0)
		_apply()


func shake(amount := 1.0) -> void:
	_shake = maxf(_shake, amount)


func focus(p: Vector3) -> void:
	var tw := create_tween()
	tw.tween_method(func(v: Vector3):
		position = Vector3(v.x, 0, v.z)
		_apply(), position, Vector3(p.x, 0, p.z), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func pan_pixels(delta: Vector2) -> void:
	var vp := get_viewport().get_visible_rect().size
	var per_px := 2.0 * dist * tan(deg_to_rad(cam.fov) * 0.5) / vp.y
	var right := global_transform.basis.x
	var fwd := -global_transform.basis.z
	right.y = 0
	fwd.y = 0
	position -= right.normalized() * delta.x * per_px
	position += fwd.normalized() * delta.y * per_px / sin(pitch)
	_apply()


func zoom_by(factor: float) -> void:
	dist = clampf(dist * factor, min_dist, max_dist)
	pitch = deg_to_rad(lerpf(40.0, 58.0, (dist - min_dist) / (max_dist - min_dist)))
	_apply()


## Screen position -> point on the terrain.
func ground_point(screen: Vector2, terrain: Terrain) -> Vector3:
	var o := cam.project_ray_origin(screen)
	var d := cam.project_ray_normal(screen)
	var h := 0.3
	var p := o
	for _i in 4:
		if absf(d.y) < 0.0001:
			break
		var t := (h - o.y) / d.y
		p = o + d * t
		h = terrain.height_at(p.x, p.z)
	return p
