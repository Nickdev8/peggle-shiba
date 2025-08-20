extends Node2D

@export var where_do_projectiles_spawn_in_scene: NodePath
@export var cursor: Node2D
@export var cursor_speed: float = 400.0
@export var sack: Node2D
@export var max_distance: float = 50.0
@export var follow_speed: float = 12.0   

var cursor_position: Vector2
var _last_mouse_pos: Vector2
var _mouse_active_time := 0.0
const MOUSE_IDLE_GRACE := 0.25  

func _ready() -> void:
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

		# Clamp inside screen
		var viewport_rect := get_viewport().get_visible_rect()
		cursor_position = cursor_position.clamp(
			viewport_rect.position,
			viewport_rect.position + viewport_rect.size
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
	var t := 1.0 - pow(0.001, follow_speed * delta)
	sack.global_position = sack.global_position.lerp(target, t)

	# -------- direct placement with mouse button (not needed anymore) ----
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		cursor_position = mouse_pos
		_update_cursor(true, cursor_position)
		sack.global_position = _clamped_target(cursor_position)

func _clamped_target(pos: Vector2) -> Vector2:
	var to_target := pos - global_position
	var dist := to_target.length()
	if dist <= max_distance or dist == 0.0:
		return pos
	var dir := to_target / dist
	var gain := clampf(dist / (max_distance * 2.0), 1.0, 2.5)
	return global_position + dir * max_distance * gain

func _update_cursor(show_it: bool, pos: Vector2) -> void:
	cursor.global_position = pos
	#if show_it:
		#cursor.show()
	#else:
		#cursor.hide()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		var dir := (sack.global_position.direction_to(global_position))
		var dis := (sack.global_position.distance_to(global_position))
		var scene := preload("res://Projectile.tscn")
		var projectile := scene.instantiate()
		
		var parent: Node2D = %Main
		parent.add_child(projectile)

		get_tree().current_scene.add_child(projectile)
		projectile.global_position = sack.global_position

		# launch
		if projectile.has_method("shoot"):
			projectile.shoot(dir, dis)
