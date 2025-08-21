extends RigidBody2D

## ---- Designer-friendly knobs ----
@export var cross_screen_time_fast: float = 0.50  # sec to cross screen at max pull
@export var cross_screen_time_slow: float = 0.90  # sec to cross screen at min pull
@export var min_pull_pixels: float = 6.0
@export var max_pull_pixels: float = 32.0         # match your leash/radius
@export var curve_exponent: float = 1.35
@export var lifetime: float = 2.0
@export var gravity_px_s2: float = 720.0
@export var enable_ccd: bool = true

## ---- Internals ----
var _viewport_width: float = 320.0

func _ready() -> void:
	_viewport_width = float(get_viewport().get_visible_rect().size.x)

	# Map desired gravity (px/s^2) to project gravity via gravity_scale
	var project_g: float = float(ProjectSettings.get_setting("physics/2d/default_gravity"))
	if project_g <= 0.0:
		project_g = 980.0
	gravity_scale = gravity_px_s2 / project_g

	# CCD in Godot 4.x uses an enum
	CCDMode = CCD_MODE_CAST_RAY if enable_ccd else CCD_MODE_DISABLED
	
	contact_monitor = true
	max_contacts_reported = 4

	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func shoot(direction: Vector2, distance: float, pos: Vector2) -> void:
	global_position = pos

	# Normalize pull distance to 0..1
	var denom: float = max(1e-5, (max_pull_pixels - min_pull_pixels))
	var pull: float = clamp((distance - min_pull_pixels) / denom, 0.0, 1.0)

	# Ease curve (ease-out)
	var eased: float = pow(pull, curve_exponent)

	# Convert “seconds to cross screen” to speed (px/s)
	var v_min: float = _viewport_width / max(0.05, cross_screen_time_slow)
	var v_max: float = _viewport_width / max(0.05, cross_screen_time_fast)
	var launch_speed: float = lerp(v_min, v_max, eased)

	var dir: Vector2 = direction.normalized()
	linear_velocity = dir * launch_speed
	sleeping = false

func _on_body_entered(body: Node) -> void:
	print("Hit: ", body)
