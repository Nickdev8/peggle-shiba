extends Node2D
@onready var ammoviewer: Node2D = $"../ammoviewer"

@export var projectile_parent: Node = null

@onready var cursor: Sprite2D = %cursor
@onready var sack: Node2D = $sack
@onready var band_right: Node2D = $band_right

@export var cross_screen_time: float = 1.33
@export var leash_pixels: int = 32
@export var follow_half_life: float = 0.08

# NEW: precise power mapping across full screen
@export var power_curve_gamma: float = 0.55      # <1 => more low-end precision
@export var power_precision_boost: float = 0.5   # 0..1: blend in extra S-curve shaping
@export var power_min_speed_frac: float = 0.015  # floor as % of v_max (tiny, but non-zero)

# trajectory sim params
@export var traj_points: int = 48
@export var traj_max_time: float = 5.0
@export var traj_step: float = 0.05

# visual polish
@export var band_segments: int = 10
@export var band_bow: float = 0.18
@export var band_width: float = 2.0

# trajectory/dots styling
const PREVIEW_LENGTH_PX := 100.0
const DOT_SPACING_PX    := 3.0
const DOT_R_START       := 2.5
const DOT_R_END         := 0.6
const LAST_TRAJ_ALPHA   := 0.45

const POST_SHOT_DRAW_SECS := 0.15

@export var elastic_settle_time: float = 0.22
@export var elastic_damping_ratio: float = 0.55
@export var elastic_center_local: Vector2 = Vector2(0, 6)

@export var touch_fire_on_release: bool = true
@export var touch_min_pull_px: float = 12.0
@export var enable_haptics_on_shot: bool = false
@export var touch_release_idle_grace: float = 0.08

var ProjectileScene := preload("res://scenes/newprojectile.tscn")
var _reloading: bool = false

var cursor_speed: float = 120.0
var max_distance: float = 16.0
var cursor_position: Vector2
var _last_mouse_pos: Vector2
var _mouse_active_time: float = 0.0
const MOUSE_IDLE_GRACE := 0.25

var _screen_drag_max: float = 80.0

var _loaded_projectile: Node2D = null

var _traj_full: PackedVector2Array = PackedVector2Array()
var _traj_short: PackedVector2Array = PackedVector2Array()
var _last_shot_full: PackedVector2Array = PackedVector2Array()

var _follow_draw_time: float = 0.0
var _follow_draw_proj: Node2D = null
var _follow_draw_anchor_local: Vector2 = Vector2.ZERO

var _draw_anchor_local: Vector2 = Vector2.ZERO
var _draw_anchor_vel: Vector2 = Vector2.ZERO
var _spring_started: bool = false

var _touch_active: bool = false
var _touch_id: int = -1
var _touch_pos: Vector2 = Vector2.ZERO
var _touch_events_seen_this_frame: bool = false
var _touch_idle_timer: float = 0.0
var _mouse_hold: bool = false

func _ready() -> void:
	var vr := get_viewport().get_visible_rect()
	var center := vr.size * 0

	cursor_position = center
	cursor.global_position = center
	_last_mouse_pos = center

	# unchanged: keyboard cursor crossing time
	max_distance = float(leash_pixels)

	# NEW: power normalization uses the centered screen radius (center → edge),
	# so it works perfectly for 320×180 or any viewport size.
	var half := Vector2(float(vr.size.x), float(vr.size.y)) * 0.5
	_screen_drag_max = min(half.x, half.y)  # use the limiting axis (circle inside the screen)

	call_deferred("_spawn_loaded_projectile")

	_draw_anchor_local = to_local(sack.global_position)
	_rebuild_trajectory()
	queue_redraw()


func _physics_process(delta: float) -> void:
	_touch_events_seen_this_frame = false

	# --- keyboard (unchanged) ---
	var axis := Input.get_vector("catapult-Left", "catapult-Right", "catapult-Up", "catapult-Down")
	var speed := cursor_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= 0.3
	if Input.is_key_pressed(KEY_CTRL):
		speed *= 2
		
	if axis.length() > 1.0:
		axis = axis.normalized()
	if axis != Vector2.ZERO:
		cursor_position += axis * speed * delta
		cursor_position = _clamp_to_centered_view(cursor_position)
		cursor.global_position = cursor_position
		_mouse_active_time = 0.0

	# --- unified pointer (unchanged behavior) ---
	var used_pointer := false
	if _touch_active:
		cursor.global_position = _touch_pos
		cursor_position = _clamp_to_centered_view(_touch_pos)
		used_pointer = true
	else:
		if _mouse_hold:
			var mouse_pos: Vector2 = get_global_mouse_position()
			cursor.global_position = mouse_pos
			cursor_position = _clamp_to_centered_view(mouse_pos)
			used_pointer = true

	# mirrored target & sack leash (unchanged visuals/feel)
	var to_cursor: Vector2 = cursor_position - global_position
	var target_vec: Vector2 = -to_cursor
	var target_len: float = minf(target_vec.length(), max_distance)
	var target_dir: Vector2 = target_vec.normalized() if (target_vec.length_squared() > 1e-6) else Vector2.RIGHT
	var target: Vector2 = global_position + target_dir * target_len

	# radial follow (unchanged)
	var curr_vec: Vector2 = sack.global_position - global_position
	var curr_len: float = curr_vec.length()
	var t: float = 1.0 - exp(-0.69314718056 * delta / maxf(0.0001, follow_half_life))
	var new_len: float = lerpf(curr_len, target_len, t)
	var new_pos: Vector2 = global_position + target_dir * new_len
	sack.global_position = _pixel_snap(new_pos)

	if _loaded_projectile:
		_loaded_projectile.global_position = sack.global_position
		_loaded_projectile.rotation = _aim_angle()   # <— rotate during aim
	else:
		if not _reloading:
			_spawn_loaded_projectile()

	_rebuild_trajectory()

	if _follow_draw_time > 0.0:
		_follow_draw_time = maxf(0.0, _follow_draw_time - delta)

	_update_elastic_anchor(delta)

	# touch release fallback (unchanged)
	if _touch_active:
		if _touch_events_seen_this_frame:
			_touch_idle_timer = 0.0
		else:
			_touch_idle_timer += delta
			if _touch_idle_timer >= touch_release_idle_grace:
				if touch_fire_on_release:
					var pull_len := (cursor_position - global_position).length()
					if pull_len >= touch_min_pull_px:
						_shoot_loaded()
				_touch_active = false
				_touch_id = -1
				_touch_idle_timer = 0.0

	queue_redraw()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		var pull_len := (cursor_position - global_position).length()
		if not _reloading and _loaded_projectile and pull_len >= touch_min_pull_px:
			_shoot_loaded()
		return
	
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT:
			_mouse_hold = event.pressed
			if _mouse_hold:
				var mouse_pos := get_global_mouse_position()
				cursor.global_position = mouse_pos
				cursor_position = _clamp_to_centered_view(mouse_pos)
			return

	# touch begin
	if event is InputEventScreenTouch and event.pressed:
		_touch_events_seen_this_frame = true
		if not _touch_active:
			_touch_active = true
			_touch_id = event.index
			_touch_pos = event.position
			cursor.global_position = event.position
			cursor_position = _clamp_to_centered_view(event.position)
		return

	# touch end
	if event is InputEventScreenTouch and not event.pressed:
		_touch_events_seen_this_frame = true
		if _touch_active and event.index == _touch_id:
			if touch_fire_on_release:
				var pull_len := (cursor_position - global_position).length()
				if pull_len >= touch_min_pull_px:
					_shoot_loaded()
			_touch_active = false
			_touch_id = -1
			_touch_idle_timer = 0.0
		return

	# touch drag
	if event is InputEventScreenDrag:
		_touch_events_seen_this_frame = true
		if _touch_active and event.index == _touch_id:
			_touch_pos = event.position
		return


# ---- shoot & velocity helpers ----

func _distance_factor() -> float:
	var dist: float = (_clamp_to_centered_view(cursor_position) - global_position).length()
	var vr := get_viewport().get_visible_rect()
	var half := Vector2(float(vr.size.x), float(vr.size.y)) * 0.5
	var max_drag: float = maxf(1.0, min(half.x, half.y))

	var f := clampf(dist / max_drag, 0.0, 1.0)

	# 1) gamma (more resolution at small pulls)
	var f_gamma := pow(f, clampf(power_curve_gamma, 0.05, 3.0))
	# 2) S-curve (smoothstep) to further open the low end
	var f_s := f_gamma * f_gamma * (3.0 - 2.0 * f_gamma)
	# 3) blend to taste
	return lerpf(f_gamma, f_s, clampf(power_precision_boost, 0.0, 1.0))


func _launch_velocity() -> Vector2:
	var p := _get_proj_params()
	var width: float = (p["bounds"] as Rect2).size.x
	var v_max: float = width / maxf(0.05, float(p["max_ct"]))

	var factor: float = _distance_factor()
	var min_floor := clampf(power_min_speed_frac, 0.0, 0.25) * v_max
	var speed: float = max(min_floor, v_max * factor)

	var dir: Vector2 = _aim_dir()
	return dir * speed



func _shoot_loaded() -> void:
	if _loaded_projectile == null:
		return

	_last_shot_full = _traj_full.duplicate()

	var v0: Vector2 = _launch_velocity()

	var proj := _loaded_projectile
	_loaded_projectile = null
	_reloading = true

	proj.rotation = _aim_angle()
	
	_follow_draw_time = POST_SHOT_DRAW_SECS
	_follow_draw_proj = proj
	_follow_draw_anchor_local = to_local(sack.global_position)

	_draw_anchor_local = _follow_draw_anchor_local
	_draw_anchor_vel = Vector2.ZERO
	_spring_started = false

	if enable_haptics_on_shot and OS.has_feature("mobile"):
		if Engine.has_singleton("GodotHapticFeedback"):
			var h := Engine.get_singleton("GodotHapticFeedback")
			if h and h.has_method("vibrate"):
				h.vibrate(30)

	if proj.has_method("set_loaded"):
		proj.call("set_loaded", false)

	if not proj.tree_exited.is_connected(_on_projectile_gone):
		proj.tree_exited.connect(_on_projectile_gone)

	if proj.has_method("shoot"):
		proj.call("shoot", sack.global_position, v0, 1.0)


func _on_projectile_gone() -> void:
	_reloading = false
	_spawn_loaded_projectile()
	_rebuild_trajectory()
	_draw_anchor_local = to_local(sack.global_position)
	_draw_anchor_vel = Vector2.ZERO
	_spring_started = false
	queue_redraw()


func _get_proj_params() -> Dictionary:
	var g: float = 800.0
	var min_ct: float = 0.75
	var max_ct: float = 0.55
	var r: float = 6.0
	var bounds: Rect2 = Rect2()

	if _loaded_projectile and _loaded_projectile.has_method("get"):
		var v = _loaded_projectile
		var maybe: Variant = v.get("gravity");         if typeof(maybe) == TYPE_FLOAT or typeof(maybe) == TYPE_INT: g = float(maybe)
		maybe = v.get("min_cross_time");                if typeof(maybe) == TYPE_FLOAT or typeof(maybe) == TYPE_INT: min_ct = float(maybe)
		maybe = v.get("max_cross_time");                if typeof(maybe) == TYPE_FLOAT or typeof(maybe) == TYPE_INT: max_ct = float(maybe)
		maybe = v.get("radius");                        if typeof(maybe) == TYPE_FLOAT or typeof(maybe) == TYPE_INT: r = float(maybe)
		maybe = v.get("bounds");                        if typeof(maybe) == TYPE_RECT2: bounds = maybe
	if bounds.size == Vector2.ZERO:
		var size: Vector2i = get_viewport().get_visible_rect().size
		bounds = Rect2(-float(size.x) * 0.5, -float(size.y) * 0.5, float(size.x), float(size.y))
	return {
		"gravity": g,
		"min_ct": min_ct,
		"max_ct": max_ct,
		"radius": r,
		"bounds": bounds
	}

# ---- trajectory preview (unchanged) ----

func _rebuild_trajectory() -> void:
	var p := _get_proj_params()
	var g: float = float(p["gravity"])
	var r: float = float(p["radius"])
	var bounds: Rect2 = p["bounds"]

	var start: Vector2 = sack.global_position
	var clamped_start := Vector2(
		clampf(start.x, bounds.position.x + r, bounds.position.x + bounds.size.x - r),
		clampf(start.y, bounds.position.y + r, bounds.position.y + bounds.size.y - r)
	)
	var v0: Vector2 = _launch_velocity()

	_traj_full.resize(0)
	var t_acc: float = 0.0
	var steps: int = int(minf(float(traj_points), ceilf(traj_max_time / traj_step)))
	for _i in range(steps):
		var pos: Vector2 = clamped_start + v0 * t_acc + Vector2(0.0, 0.5 * g * t_acc * t_acc)
		_traj_full.append(to_local(pos))
		if (pos.y - r) > (bounds.position.y + bounds.size.y):
			break
		t_acc += traj_step

	_traj_short = _arc_resample(_traj_full, PREVIEW_LENGTH_PX, DOT_SPACING_PX)

# ---- drawing & helpers (unchanged) ----
# --- helper: aim direction & angle ---
func _aim_dir() -> Vector2:
	var aim_at: Vector2 = _clamp_to_centered_view(cursor_position)
	var d: Vector2 = sack.global_position.direction_to(aim_at)
	return Vector2(0, -1) if d.length_squared() < 1e-6 else d
	
func _aim_angle() -> float:
	return _aim_dir().angle() + PI / 2

func _draw() -> void:
	var right_anchor: Vector2 = to_local(band_right.global_position)
	var left_anchor: Vector2 = right_anchor
	left_anchor.x *= -1

	var sack_pt: Vector2
	if _follow_draw_time > 0.0 and _valid_follow_proj():
		sack_pt = to_local(_follow_draw_proj.global_position)
	elif _reloading:
		sack_pt = _draw_anchor_local
	else:
		sack_pt = to_local(sack.global_position)

	draw_line(left_anchor,  sack_pt + Vector2(0, 5), Color.from_rgba8(233,156,91), 3)
	draw_line(right_anchor, sack_pt + Vector2(0, 5), Color.from_rgba8(233,156,91), 3)

	if _last_shot_full.size() >= 2:
		_draw_dots(_last_shot_full, DOT_SPACING_PX, DOT_R_START * 0.9, DOT_R_START * 0.9, Color(0.65, 0.65, 0.65, LAST_TRAJ_ALPHA))

	if _traj_short.size() >= 1 and not _reloading:
		var count := _traj_short.size()
		for i in count:
			var t := 0.0 if (count <= 1) else float(i) / float(count - 1)
			var r := lerpf(DOT_R_START, DOT_R_END, t)
			draw_circle(_traj_short[i], r, Color(1, 1, 1, 1.0))

func _update_elastic_anchor(delta: float) -> void:
	if _follow_draw_time > 0.0 and _valid_follow_proj():
		_draw_anchor_local = to_local(_follow_draw_proj.global_position)
		_draw_anchor_vel = Vector2.ZERO
		_spring_started = false
		return

	if not _reloading:
		_draw_anchor_local = to_local(sack.global_position)
		_draw_anchor_vel = Vector2.ZERO
		_spring_started = false
		return

	if not _spring_started:
		_draw_anchor_vel = Vector2.ZERO
		_spring_started = true

	var zeta := clampf(elastic_damping_ratio, 0.0, 2.0)
	var settle := maxf(0.05, elastic_settle_time)
	var omega_n := (4.0 / maxf(0.05, zeta * settle)) if zeta > 0.001 else 30.0
	var k := omega_n * omega_n
	var c := 2.0 * zeta * omega_n

	var x := _draw_anchor_local
	var v := _draw_anchor_vel
	var target := elastic_center_local

	var a := -(k * (x - target)) - (c * v)
	v += a * delta
	x += v * delta

	_draw_anchor_local = x
	_draw_anchor_vel = v

func _valid_follow_proj() -> bool:
	return _follow_draw_proj and is_instance_valid(_follow_draw_proj) and _follow_draw_proj.is_inside_tree()

func _arc_resample(points: PackedVector2Array, length_limit_px: float, spacing_px: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() == 0:
		return out

	var acc_len := 0.0
	var seg_acc := 0.0
	var i := 0
	var prev := points[0]
	out.append(prev)

	while i < points.size() - 1 and acc_len < length_limit_px:
		var a := prev
		var b := points[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.0001:
			i += 1
			prev = b
			continue

		var remaining := spacing_px - seg_acc
		if remaining <= seg_len:
			var t := remaining / seg_len
			var p := a.lerp(b, t)
			out.append(p)
			prev = p
			seg_acc = 0.0
			acc_len += remaining
			points[i] = prev
		else:
			seg_acc += seg_len
			acc_len += seg_len
			i += 1
			prev = b

		if acc_len + 0.0001 >= length_limit_px:
			break
	return out

func _draw_dots(poly: PackedVector2Array, spacing_px: float, r_start: float, r_end: float, col: Color) -> void:
	if poly.size() == 0:
		return
	var dots := _arc_resample(poly, 1e9, spacing_px)
	var n := dots.size()
	if n == 0:
		return
	for i in n:
		var t := 0.0 if (n <= 1) else float(i) / float(n - 1)
		var r := lerpf(r_start, r_end, t)
		draw_circle(dots[i], r, col)

func _pixel_snap(v: Vector2) -> Vector2:
	return Vector2(round(v.x), round(v.y))

func _clamp_to_centered_view(p: Vector2) -> Vector2:
	if get_viewport():
		var vr := get_viewport().get_visible_rect()
		var size: Vector2i = vr.size
		var half: Vector2 = Vector2(float(size.x) * 0.5, float(size.y) * 0.5)
		return p.clamp(-half + Vector2.ONE, half - Vector2.ONE)
	return Vector2.ZERO

func _spawn_loaded_projectile() -> void:
	if _loaded_projectile or _reloading:
		return

	var proj := ProjectileScene.instantiate()
	var parent := projectile_parent if projectile_parent != null else get_parent()
	parent.add_child(proj)

	var spawn_pos := sack.global_position if (sack and sack.is_inside_tree()) else global_position
	proj.global_position = spawn_pos

	if proj.has_method("set_loaded"):
		proj.call("set_loaded", true)
	proj.visible = true
	proj.sprite.set_ammo_index(ammoviewer.preview_queue[ammoviewer.preview_queue.size()-1])
	ammoviewer.load_next()
	proj.show()

	_loaded_projectile = proj

func _on_button_pressed() -> void:
	_shoot_loaded()
