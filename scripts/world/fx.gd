class_name FX
## Ready-made particle effects built from soft round particles: fire, smoke, dust and sparks.


static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([])
	g.colors = PackedColorArray([])
	for i in cols.size():
		g.add_point(float(i) / (cols.size() - 1), cols[i])
	return g


static func _base(amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = amount
	p.lifetime = life
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.UP
	return p


## Rising flames over a box-shaped area (half extents), bright at the base, fading to red.
static func flames(extents: Vector3, amount := 60, size := 1.2) -> CPUParticles3D:
	var p := _base(amount, 0.9)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.spread = 10.0
	p.gravity = Vector3(0, 2.5, 0)
	p.initial_velocity_min = 0.6
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var c := Curve.new()
	c.add_point(Vector2(0, 0.7))
	c.add_point(Vector2(0.3, 1.0))
	c.add_point(Vector2(1, 0.2))
	p.scale_amount_curve = c
	p.color_ramp = _ramp([Color(1, 0.9, 0.5, 0.0), Color(1, 0.7, 0.28, 0.75), Color(1, 0.38, 0.08, 0.55), Color(0.6, 0.1, 0.05, 0.0)])
	p.mesh = Models.soft_particle(size, Color(1, 0.8, 0.5), true, 1.2)
	return p


## Dark smoke drifting up and sideways.
static func smoke(extents: Vector3, amount := 16, size := 2.4) -> CPUParticles3D:
	var p := _base(amount, 3.0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extents
	p.spread = 20.0
	p.gravity = Vector3(0.4, 1.0, 0.2)
	p.initial_velocity_min = 0.4
	p.initial_velocity_max = 1.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.6
	var c := Curve.new()
	c.add_point(Vector2(0, 0.4))
	c.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = c
	p.color_ramp = _ramp([Color(0.5, 0.47, 0.44, 0.0), Color(0.5, 0.47, 0.44, 0.22), Color(0.6, 0.58, 0.56, 0.0)])
	p.mesh = Models.soft_particle(size, Color(1, 1, 1), false)
	return p


## A one-shot puff of dust, as when a building rises or falls.
static func dust(radius: float, amount := 24) -> CPUParticles3D:
	var p := _base(amount, 1.6)
	p.one_shot = true
	p.explosiveness = 0.85
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = radius
	p.spread = 70.0
	p.gravity = Vector3(0, -0.6, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 3.0
	p.scale_amount_min = 0.8
	p.scale_amount_max = 1.8
	var c := Curve.new()
	c.add_point(Vector2(0, 0.6))
	c.add_point(Vector2(1, 1.5))
	p.scale_amount_curve = c
	p.color_ramp = _ramp([Color(0.75, 0.67, 0.55, 0.0), Color(0.74, 0.66, 0.54, 0.55), Color(0.74, 0.66, 0.54, 0.0)])
	p.mesh = Models.soft_particle(2.0, Color(1, 1, 1), false)
	return p
