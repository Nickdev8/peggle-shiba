extends Node2D

@export var cursor: Node2D
@export var sack: Node2D
@export var pole_left: Node2D
@export var pole_right: Node2D
@export var cross_screen_time: float = 1.33
@export var leash_pixels: int = 32
@export var follow_half_life: float = 0.1

var ProjectileScene := preload("res://scenes/Projectile.tscn")

var cursor_speed := 240.0
var max_distance := 16.0
var cursor_position: Vector2
var _last_mouse_pos: Vector2
var _mouse_active_time := 0.0
const MOUSE_IDLE_GRACE := 0.25

var _loaded_projectile: RigidBody2D = null

func _ready() -> void:
	var vw := float(get_viewport().get_visible_rect().size.x)
	cursor_speed = vw / max(0.05, cross_screen_time)
	max_distance = float(leash_pixels)
	cursor_position = sack.global_position
	_last_mouse_pos = get_global_mouse_position()
	_update_cursor(false, cursor_position)


func _physics_process(delta: float) -> void:
	# --- controls unchanged ---
	var axis := Input.get_vector("catapult-Left", "catapult-Right", "catapult-Up", "catapult-Down")
	if axis.length() > 1.0: axis = axis.normalized()
	if axis != Vector2.ZERO:
		cursor_position += axis * cursor_speed * delta
		var vr := get_viewport().get_visible_rect()
		cursor_position = cursor_position.clamp(vr.position + Vector2.ONE, vr.position + vr.size - Vector2.ONE)
		_mouse_active_time = 0.0
		_update_cursor(true, cursor_position)

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
		

	var target := _clamped_target(cursor_position)
	var t := 1.0 - exp(-0.69314718056 * delta / max(0.0001, follow_half_life))
	sack.global_position = _pixel_snap(sack.global_position.lerp(target, t))

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cursor_position = mouse_pos
		_update_cursor(true, cursor_position)
		sack.global_position = _pixel_snap(_clamped_target(cursor_position))

	if _loaded_projectile:
		# Defer is safest for RigidBody2D while frozen.
		_loaded_projectile.set_deferred("global_position", sack.global_position)
	else:
		# If somehow missing (despawned or not created), ensure we have one.
		_spawn_loaded_projectile()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		_shoot_loaded()

# ---- helpers ----

func _spawn_loaded_projectile() -> void:
	if _loaded_projectile: return
	_loaded_projectile = ProjectileScene.instantiate()
	_loaded_projectile.freeze = true
	_loaded_projectile.global_position = sack.global_position
	_loaded_projectile.show()
	# Using call_deferred avoids edge cases if current_scene isn’t ready in this exact tick.
	get_tree().current_scene.call_deferred("add_child", _loaded_projectile)

func _shoot_loaded() -> void:
	if _loaded_projectile == null: 
		_spawn_loaded_projectile()
		return
	var dir: Vector2 = sack.global_position.direction_to(global_position)
	var dis: float = sack.global_position.distance_to(global_position)
	_loaded_projectile.shoot(dir, dis, sack.global_position)
	_loaded_projectile = null
	# Auto-load the next round so it’s visible immediately.
	_spawn_loaded_projectile()

func _clamped_target(pos: Vector2) -> Vector2:
	var to_target := pos - global_position
	var dist := to_target.length()
	if dist <= max_distance or dist == 0.0:
		return _pixel_snap(pos)
	return _pixel_snap(global_position + to_target.normalized() * max_distance)

func _update_cursor(_show_it: bool, pos: Vector2) -> void:
	cursor.global_position = _pixel_snap(pos)
	queue_redraw()

func _pixel_snap(v: Vector2) -> Vector2:
	return Vector2(round(v.x), round(v.y))

func _draw() -> void:
	draw_line(pole_left.position, sack.position + Vector2(-4,5), Color.WHEAT, 2)
	draw_line(pole_right.position, sack.position + Vector2(4,5), Color.WHEAT, 2)
