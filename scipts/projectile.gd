extends RigidBody2D

@export var cross_screen_time_fast: float = 0.50
@export var cross_screen_time_slow: float = 0.90
@export var min_pull_pixels: float = 6.0
@export var max_pull_pixels: float = 32.0
@export var curve_exponent: float = 1.35
@export var gravity_px_s2: float = 720.0

@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
var onscreen: VisibleOnScreenNotifier2D

var _hitobjects: Array[Node] = []
var _vw: float = 320.0

func _ready() -> void:
	onscreen = get_node_or_null("VisibleOnScreenNotifier2D") as VisibleOnScreenNotifier2D
	if onscreen == null:
		onscreen = VisibleOnScreenNotifier2D.new()
		add_child(onscreen)

	if not onscreen.screen_exited.is_connected(_on_screen_exited):
		onscreen.screen_exited.connect(_on_screen_exited)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

	contact_monitor = true
	max_contacts_reported = 8

	var vp := get_viewport()
	if vp:
		_vw = float(vp.get_visible_rect().size.x)

	var g: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
	if g <= 0.0: g = 980.0
	gravity_scale = gravity_px_s2 / g

func shoot(direction: Vector2, distance: float, pos: Vector2) -> void:
	collision_shape_2d.disabled = false
	global_position = pos

	var denom: float = maxf(0.00001, (max_pull_pixels - min_pull_pixels))
	var pull: float = clampf((distance - min_pull_pixels) / denom, 0.0, 1.0)
	var eased: float = pow(pull, curve_exponent)

	var v_min: float = _vw / maxf(0.05, cross_screen_time_slow)
	var v_max: float = _vw / maxf(0.05, cross_screen_time_fast)
	var launch_speed: float = lerpf(v_min, v_max, eased)

	linear_velocity = direction.normalized() * launch_speed
	freeze = false
	sleeping = false

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("destructible") and not _hitobjects.has(body):
		_hitobjects.append(body)
		var object_sprite: Sprite2D = body.get_child(0)
		object_sprite.self_modulate.a = 0.5

func _on_screen_exited() -> void:
	for body in _hitobjects:
		if is_instance_valid(body):
			body.queue_free()
	_hitobjects.clear()

	queue_free()
