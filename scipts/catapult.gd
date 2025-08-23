extends Node2D

@export var projectile_parent: Node = null
@export var cursor: Node2D
@export var sack: Node2D
@export var pole_left: Node2D
@export var pole_right: Node2D
@export var cross_screen_time: float = 1.33
@export var leash_pixels: int = 32
@export var follow_half_life: float = 0.08

# trajectory sim params
@export var traj_points: int = 48
@export var traj_max_time: float = 5.0
@export var traj_step: float = 0.05

# visual polish
@export var band_segments: int = 10
@export var band_bow: float = 0.18
@export var band_width: float = 2.0

# --- NEW: display styling ---
const PREVIEW_LENGTH_PX := 70.0    # only show first ~50 px of current trajectory
const DOT_SPACING_PX    := 3.0     # tight spacing between dots
const DOT_R_START       := 2.5     # starting radius of dot near sling
const DOT_R_END         := 0.6     # smallest radius at 50 px
const LAST_TRAJ_ALPHA   := 0.45    # greyed out previous shot

var ProjectileScene := preload("res://scenes/newprojectile.tscn")
var _reloading: bool = false

var cursor_speed: float = 240.0
var max_distance: float = 16.0
var cursor_position: Vector2
var _last_mouse_pos: Vector2
var _mouse_active_time: float = 0.0
const MOUSE_IDLE_GRACE := 0.25

var _loaded_projectile: Node2D = null

# --- NEW: keep multiple forms of trajectory data ---
var _traj_full: PackedVector2Array = PackedVector2Array()     # full sim for current aim
var _traj_short: PackedVector2Array = PackedVector2Array()    # first 50px resampled for dots
var _last_shot_full: PackedVector2Array = PackedVector2Array()# full sim from previous shot

func _ready() -> void:
	var vr := get_viewport().get_visible_rect()
	var vw := float(vr.size.x)
	cursor_speed = vw / maxf(0.05, cross_screen_time)
	max_distance = float(leash_pixels)

	# If sack isn't set yet, fall back safely
	cursor_position = sack.global_position if (sack and sack.is_inside_tree()) else global_position
	_last_mouse_pos = get_global_mouse_position()
	
	call_deferred("_spawn_loaded_projectile")

	_rebuild_trajectory()
	queue_redraw()


func _physics_process(delta: float) -> void:
	# --- keyboard control ---
	var axis := Input.get_vector("catapult-Left", "catapult-Right", "catapult-Up", "catapult-Down")
	if axis.length() > 1.0:
		axis = axis.normalized()
	if axis != Vector2.ZERO:
		cursor_position += axis * cursor_speed * delta
		cursor_position = _clamp_to_centered_view(cursor_position)
		cursor.global_position = cursor_position
		_mouse_active_time = 0.0

	# --- mouse control with brief grace ---
	var mouse_pos: Vector2 = get_global_mouse_position()
	if mouse_pos != _last_mouse_pos:
		_mouse_active_time = MOUSE_IDLE_GRACE
		_last_mouse_pos = mouse_pos
		cursor.global_position = mouse_pos
	if _mouse_active_time > 0.0:
		cursor_position = _clamp_to_centered_view(mouse_pos)
		_mouse_active_time -= delta

	# --- mirrored target (opposite side of base) ---
	var to_cursor: Vector2 = cursor_position - global_position
	var target_vec: Vector2 = -to_cursor
	var target_len: float = minf(target_vec.length(), max_distance)
	var target_dir: Vector2 = target_vec.normalized() if (target_vec.length_squared() > 1e-6) else Vector2.RIGHT
	var target: Vector2 = global_position + target_dir * target_len

	# --- RADIAL FOLLOW: smooth only the radius, snap the angle ---
	var curr_vec: Vector2 = sack.global_position - global_position
	var curr_len: float = curr_vec.length()
	var t: float = 1.0 - exp(-0.69314718056 * delta / maxf(0.0001, follow_half_life))
	var new_len: float = lerpf(curr_len, target_len, t)
	var new_pos: Vector2 = global_position + target_dir * new_len
	sack.global_position = _pixel_snap(new_pos)

	# keep round glued
	if _loaded_projectile:
		_loaded_projectile.global_position = sack.global_position
	else:
		if not _reloading:
			_spawn_loaded_projectile()

	# update predicted trajectory & redraw
	_rebuild_trajectory()
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot"):
		_shoot_loaded()

# ---- shoot & velocity helpers ----

func _distance_factor() -> float:
	var dist: float = (cursor_position - global_position).length()
	var max_drag: float = max_distance * 3.0
	return clampf(dist / max_drag, 0.0, 1.0)

func _launch_velocity() -> Vector2:
	var p := _get_proj_params()
	var width: float = (p["bounds"] as Rect2).size.x
	var v_min: float = width / maxf(0.05, float(p["min_ct"]))
	var v_max: float = width / maxf(0.05, float(p["max_ct"]))
	var factor: float = _distance_factor()
	var bias: float = 0.75
	factor = pow(factor, bias)
	var speed: float = lerpf(v_min, v_max, factor)

	var aim_at: Vector2 = _clamp_to_centered_view(cursor_position)
	var dir: Vector2 = sack.global_position.direction_to(aim_at)
	if dir.length_squared() < 1e-6:
		dir = Vector2(0, -1)
	return dir * speed

func _shoot_loaded() -> void:
	if _loaded_projectile == null:
		return

	_last_shot_full = _traj_full.duplicate()

	var v0: Vector2 = _launch_velocity()

	var proj := _loaded_projectile
	_loaded_projectile = null
	_reloading = true

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

# ---- trajectory preview (same math the projectile will use) ----

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

	# build full trajectory in local space
	_traj_full.resize(0)
	var t_acc: float = 0.0
	var steps: int = int(minf(float(traj_points), ceilf(traj_max_time / traj_step)))
	for _i in range(steps):
		var pos: Vector2 = clamped_start + v0 * t_acc + Vector2(0.0, 0.5 * g * t_acc * t_acc)
		_traj_full.append(to_local(pos))
		if (pos.y - r) > (bounds.position.y + bounds.size.y):
			break
		t_acc += traj_step

	# --- NEW: create short, ~50px arc-length sample with tight spacing
	_traj_short = _arc_resample(_traj_full, PREVIEW_LENGTH_PX, DOT_SPACING_PX)

# ---- drawing ----

func _draw() -> void:
	# bands
	var ls: Vector2 = to_local(sack.global_position)
	draw_line(Vector2(-24,10),  ls + Vector2(-4, 7), Color.from_rgba8(233,156,91), 3)
	draw_line(Vector2(24,10), ls + Vector2( 4, 7), Color.from_rgba8(233,156,91), 3)

	# --- NEW: draw last shot full trajectory greyed out (dotted)
	if _last_shot_full.size() >= 2:
		_draw_dots(_last_shot_full, DOT_SPACING_PX, DOT_R_START * 0.9, DOT_R_START * 0.9, Color(0.65, 0.65, 0.65, LAST_TRAJ_ALPHA))

	# --- NEW: draw only first ~50px of current aim as shrinking white dots
	if _traj_short.size() >= 1:
		# sizes fade from DOT_R_START to DOT_R_END over the preview length
		var count := _traj_short.size()
		for i in count:
			var t := 0.0 if (count <= 1) else float(i) / float(count - 1)
			var r := lerpf(DOT_R_START, DOT_R_END, t)
			draw_circle(_traj_short[i], r, Color(1, 1, 1, 1.0))

# ---- NEW: helpers ----

# Resamples 'points' along arc length, returning equally spaced points
# up to 'length_limit_px' (or fewer if path ends), spaced by 'spacing_px'.
func _arc_resample(points: PackedVector2Array, length_limit_px: float, spacing_px: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if points.size() == 0:
		return out

	var acc_len := 0.0
	var seg_acc := 0.0
	var i := 0
	var prev := points[0]
	out.append(prev) # always start with first point

	while i < points.size() - 1 and acc_len < length_limit_px:
		var a := prev
		var b := points[i + 1]
		var seg_len := a.distance_to(b)
		if seg_len <= 0.0001:
			i += 1
			prev = b
			continue

		# advance along the segment by remaining spacing
		var remaining := spacing_px - seg_acc
		if remaining <= seg_len:
			var t := remaining / seg_len
			var p := a.lerp(b, t)
			out.append(p)
			prev = p
			seg_acc = 0.0
			acc_len += remaining
			# stay on same segment (a..b), with new 'a' = p
			# emulate by not incrementing i, but shifting 'a'
			points[i] = prev  # temporary in-place walk
		else:
			seg_acc += seg_len
			acc_len += seg_len
			i += 1
			prev = b

		if acc_len + 0.0001 >= length_limit_px:
			break

	return out

# draws small dots along an existing polyline using arc-length spacing
func _draw_dots(poly: PackedVector2Array, spacing_px: float, r_start: float, r_end: float, col: Color) -> void:
	if poly.size() == 0:
		return
	# build an arc-length sampled list
	var dots := _arc_resample(poly, 1e9, spacing_px) # effectively no limit
	var n := dots.size()
	if n == 0:
		return
	for i in n:
		var t := 0.0 if (n <= 1) else float(i) / float(n - 1)
		var r := lerpf(r_start, r_end, t)
		draw_circle(dots[i], r, col)

# ---- misc utils ----

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

	# If you prefer extra safety, you can also do:
	# parent.call_deferred("add_child", proj)
	# but since we called this via call_deferred from _ready, a normal add_child is fine.
	parent.add_child(proj)

	# Safe spawn position even if sack is missing/not ready
	var spawn_pos := sack.global_position if (sack and sack.is_inside_tree()) else global_position
	proj.global_position = spawn_pos

	if proj.has_method("set_loaded"):
		proj.call("set_loaded", true)
	proj.visible = true
	proj.show()

	_loaded_projectile = proj
