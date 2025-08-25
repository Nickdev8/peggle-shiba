extends Node2D

@onready var sprite: Sprite2D = $Sprite2D

@export var radius: float = 6.0

# Global forces / stepping
@export var gravity: float = 800.0
@export var base_steps: int = 6              # minimum substeps
@export var max_steps_cap: int = 32          # safety cap
@export var bounds: Rect2 = Rect2(-90.0, -160.0, 180.0, 320.0)

# Walls
@export var wall_restitution: float = 0.25
@export var wall_friction: float = 0.35

# Pegs
@export var peg_restitution: float = 0.15
@export var peg_friction: float = 0.55
@export var peg_slop: float = 0.5            # extra separation (pixels)
@export var peg_cluster_iters: int = 2       # resolve clusters a couple times

# Rotation / spin
var angular_velocity: float = 0.0
@export var rotation_damping: float = 0.985
@export var max_spin: float = 25.0

# Runtime
var vel: Vector2 = Vector2.ZERO
var _is_loaded: bool = false

# Peg bookkeeping
var _hit_pegs: Array[Node] = []
var _scheduled_pegs: Dictionary = {} # Node -> true

func _ready() -> void:
	var vp := get_viewport()
	if vp:
		var size: Vector2i = vp.get_visible_rect().size
		bounds = Rect2(-float(size.x) * 0.5, -float(size.y) * 0.5, float(size.x), float(size.y))

func _process(delta: float) -> void:
	sprite.update_shoot(vel)


func set_loaded(loaded: bool) -> void:
	_is_loaded = loaded
	set_physics_process(not loaded)

func shoot(origin: Vector2, direction: Vector2, ease: float) -> void:
	sprite.render_shoot()
	if bounds.size == Vector2.ZERO:
		bounds = Rect2(-90.0, -160.0, 180.0, 320.0)

	var r: float = maxf(1.0, radius)
	origin.x = clampf(origin.x, bounds.position.x + r, bounds.position.x + bounds.size.x - r)
	origin.y = clampf(origin.y, bounds.position.y + r, bounds.position.y + bounds.size.y - r)
	global_position = origin

	var spd: float = direction.length()
	if spd > 1.0:
		vel = direction
	else:
		var width: float = bounds.size.x
		var v_min: float = width / maxf(0.05, 0.75)   # min_cross_time
		var v_max: float = width / maxf(0.05, 0.55)   # max_cross_time
		var launch_speed: float = lerpf(v_min, v_max, clampf(ease, 0.0, 1.0))
		var dir: Vector2 = direction if direction.length_squared() >= 1e-6 else Vector2(0, -1)
		vel = dir.normalized() * launch_speed

	angular_velocity = vel.length() / maxf(radius, 0.001) * 0.15
	set_loaded(false)

func _physics_process(delta: float) -> void:
	# --- Adaptive sub-stepping: keep displacement per substep ~< radius*0.5
	var desired: float = (vel.length() * delta) / maxf(1.0, radius * 0.5)
	var extra_steps: int = int(ceil(desired))
	var steps: int = clampi(max(base_steps, extra_steps), base_steps, max_steps_cap)
	var h: float = delta / float(steps)

	for _i in range(steps):
		vel.y += gravity * h
		var new_pos: Vector2 = global_position + vel * h

		# Walls
		if new_pos.x - radius < bounds.position.x:
			var n: Vector2 = Vector2(1, 0)
			new_pos.x = bounds.position.x + radius
			_apply_wall_response(n)
		if new_pos.x + radius > bounds.position.x + bounds.size.x:
			var n2: Vector2 = Vector2(-1, 0)
			new_pos.x = bounds.position.x + bounds.size.x - radius
			_apply_wall_response(n2)
		if new_pos.y - radius < bounds.position.y:
			var n3: Vector2 = Vector2(0, 1)
			new_pos.y = bounds.position.y + radius
			_apply_wall_response(n3)

		# Off-screen (bottom drain)
		if new_pos.y - radius > bounds.position.y + bounds.size.y:
			get_child(0).modulate.a = 0.0
			await get_tree().create_timer(0.2).timeout
			_free_marked_pegs()
			queue_free()
			return

		# --- Peg cluster resolve ---
		# Grab pegs once per substep (not inside inner loops)
		var pegs: Array = get_tree().get_nodes_in_group("peg")
		for _cluster in range(peg_cluster_iters):
			var sum_n: Vector2 = Vector2.ZERO
			var deepest_pen: float = -1e20
			var deep_n: Vector2 = Vector2.UP
			var deep_center: Vector2 = Vector2.ZERO
			var deep_pr: float = 0.0
			var cluster_count: int = 0

			for peg: Node in pegs:
				var p2d := peg as Node2D
				if p2d == null:
					continue

				var pr: float = 10.0
				if peg.has_method("get"):
					var maybe_r: Variant = peg.get("radius")
					if typeof(maybe_r) == TYPE_FLOAT or typeof(maybe_r) == TYPE_INT:
						pr = float(maybe_r)

				var to_ball: Vector2 = new_pos - p2d.global_position
				var dist: float = to_ball.length()
				var min_dist: float = radius + pr
				var penetration: float = min_dist - dist

				if penetration > 0.0:
					# Safe normal (fallback to velocity/up if centered)
					var n_local: Vector2 = to_ball / dist if dist > 0.0001 else (vel.normalized() if vel.length_squared() > 0.0 else Vector2.UP)

					sum_n += n_local
					if penetration > deepest_pen:
						deepest_pen = penetration
						deep_n = n_local
						deep_center = p2d.global_position
						deep_pr = pr
					cluster_count += 1

					# Mark/schedule each touched peg, but only apply one response later
					_mark_peg(peg)
					_schedule_clear_peg(peg)

			if cluster_count == 0:
				break

			var n_use: Vector2 = sum_n.normalized() if sum_n.length_squared() > 0.0001 else deep_n

			# Depenetrate to deepest peg surface + small slop
			var target_dist: float = radius + deep_pr + peg_slop
			new_pos = deep_center + deep_n * target_dist

			# Reduce friction when wedged in a cluster so we "slip" out
			var friction_scale: float = 0.25 if (cluster_count >= 2) else 1.0
			_apply_peg_response_scaled(n_use, friction_scale)

		global_position = new_pos

	# Rotation update
	rotation += angular_velocity * delta
	angular_velocity *= rotation_damping
	angular_velocity = clampf(angular_velocity, -max_spin, max_spin)

# -----------------------
# Collision responses
# -----------------------
func _apply_wall_response(n: Vector2) -> void:
	var t: Vector2 = Vector2(-n.y, n.x)
	var v_n: float = vel.dot(n)
	var v_t: float = vel.dot(t)
	var v_n_after: float = -v_n * wall_restitution
	var v_t_after: float = v_t * (1.0 - clampf(wall_friction, 0.0, 1.0))
	vel = n * v_n_after + t * v_t_after
	var dv_t: float = v_t_after - v_t
	angular_velocity += -dv_t / maxf(radius, 0.001)

func _apply_peg_response_scaled(n: Vector2, friction_scale: float) -> void:
	var t: Vector2 = Vector2(-n.y, n.x)
	var v_n: float = vel.dot(n)
	var v_t: float = vel.dot(t)

	var v_n_after: float = -v_n * peg_restitution
	var eff_friction: float = clampf(peg_friction * friction_scale, 0.0, 1.0)
	var v_t_after: float = v_t * (1.0 - eff_friction)

	vel = n * v_n_after + t * v_t_after

	var dv_t: float = v_t_after - v_t
	angular_velocity += -dv_t / maxf(radius, 0.001)

# --- peg helpers ---
func _mark_peg(peg: Node) -> void:
	if peg != null and peg.is_in_group("peg") and not _hit_pegs.has(peg):
		_hit_pegs.append(peg)
		var peg_sprite: AnimatedSprite2D = peg.get_child(0)
		if peg_sprite:
			peg_sprite.modulate.a = 0.5

func _schedule_clear_peg(peg: Node) -> void:
	if peg == null or _scheduled_pegs.has(peg):
		return
	_scheduled_pegs[peg] = true
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(peg):
		peg.queue_free()
	_scheduled_pegs.erase(peg)

func _free_marked_pegs() -> void:
	for p in _hit_pegs:
		if is_instance_valid(p):
			p.queue_free()
	_hit_pegs.clear()

func _exit_tree() -> void:
	_free_marked_pegs()
