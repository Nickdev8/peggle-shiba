extends Node2D

@export var where_do_projectiles_spawn_in_scene: NodePath
@export var cursor: Node2D
@export var sack: Node2D

# --- Tunables for 320x180 ---
@export var cross_screen_time: float = 1.33  # seconds to traverse width; 1.33s => ~240 px/s at 320px
@export var leash_pixels: int = 32           # max leash radius around this node
@export var follow_half_life: float = 0.1    # seconds; lower = snappier

# Internals
var ProjectileScene := preload("res://Projectile.tscn")
var cursor_speed := 240.0
var max_distance := 32.0
var cursor_position: Vector2
var _last_mouse_pos: Vector2
var _mouse_active_time := 0.0
const MOUSE_IDLE_GRACE := 0.25

func _ready() -> void:
	# Derive speed from current viewport width, so it scales if you ever change resolution.
	var vw := float(get_viewport().get_visible_rect().size.x)
	cursor_speed = vw / max(0.05, cross_screen_time)  # e.g. 320/1.33 ≈ 240
	max_distance = float(leash_pixels)

	cursor_position = sack.global_position
	_last_mouse_pos = get_global_mouse_position()
	_update_cursor(false, cursor_position)

func _physics_process(delta: float) -> void:
	# -------- READ ACTIONS (constant speed) --------
	var axis := Input.get_vector("catapult-Left", "catapult-Right", "catapult-Up", "catapult-Down")
	if axis.length() > 1.0:
		axis = axis.normalized()
	if axis != Vector2.ZERO:
		cursor_position += axis * cursor_speed * delta

		# Clamp inside the visible viewport (respecting letterbox)
		var vr := get_viewport().get_visible_rect()
		# Optional 1px safe margin to avoid touching edges on tiny screens
		var margin := Vector2(1, 1)
		cursor_position = cursor_position.clamp(
			vr.position + margin,
			vr.position + vr.size - margin
		)

		_mouse_active_time = 0.0  # keyboard/gamepad took over
		_update_cursor(true, cursor_position)

	# -------- MOUSE AIM --------
	var mouse_pos := get_global_mouse_position()
	if mouse_pos != _last_mouse_pos:
		_mouse_active_time = MOUSE_IDLE_GRACE
		_last_mouse_pos = mouse_pos

	if _mouse_active_time > 0.0:
		cursor_position = mouse_pos
		_update_cursor(true, cursor_position)
		_mouse_active_time -= delta
	elif axis == Vector2.ZERO:
		_update_cursor(false, cursor_position)

	# -------- MOVE SACK TOWARD CLAMPED TARGET --------
	var target := _clamped_target(cursor_position)
	# Exponential smoothing using half-life (time to halve remaining error)
	# t = 1 - exp(-ln(2) * dt / half_life)
	var t := 1.0 - exp(-0.69314718056 * delta / max(0.0001, follow_half_life))
	sack.global_position = _pixel_snap(sack.global_position.lerp(target, t))

	# -------- Optional direct placement with mouse button --------
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cursor_position = mouse_pos
		_update_cursor(true, cursor_position)
		sack.global_position = _pixel_snap(_clamped_target(cursor_position))

func _clamped_target(pos: Vector2) -> Vector2:
	# Keep within a circle of radius max_distance around this node (no overshoot).
	var to_target := pos - global_position
	var dist := to_target.length()
	if dist <= max_distance or dist == 0.0:
		return _pixel_snap(pos)
	var dir := to_target / dist
	return _pixel_snap(global_position + dir * max_distance)

func _update_cursor(show_it: bool, pos: Vector2) -> void:
	cursor.global_position = _pixel_snap(pos)
	# If you want to hide the cursor when idle, uncomment below:
	# if show_it: cursor.show() else: cursor.hide()

func _pixel_snap(v: Vector2) -> Vector2:
	# Pixel-perfect positions for a 320x180 render; avoids subpixel shimmer when upscaling.
	return Vector2(round(v.x), round(v.y))

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		var dir := (sack.global_position.direction_to(global_position))
		var dis := (sack.global_position.distance_to(global_position))
		fire(dir, dis)

func fire(dir: Vector2, dis: float) -> void:
	var p: RigidBody2D = ProjectileScene.instantiate()
	p.global_position = sack.global_position
	get_tree().current_scene.add_child(p)
	p.shoot(dir, dis, sack.global_position)
