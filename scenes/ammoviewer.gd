extends Node2D

signal next_ammo_ready(ammo_index: int)

@onready var spawnpoint: Node2D = $spawnpoint
@export var preview_count: int = 5

const ProjectileScene := preload("res://scenes/previewprojectile.tscn")

# queue[0] = TOP (newest), queue.back() = BOTTOM (next-to-fire)
var preview_queue: Array[int] = []

func _ready() -> void:
	randomize() # one-time: make randi_range truly random each run
	_init_preview()

# ---------------------------
# Initialization / layout
# ---------------------------
func _init_preview() -> void:
	# clear visuals
	for c in spawnpoint.get_children():
		c.queue_free()
	preview_queue.clear()

	# 1) Build the data first (TOP->BOTTOM order in the array)
	for i in range(preview_count):
		preview_queue.push_back(randi_range(0, 5))

	# 2) Now spawn visuals in the SAME order as the array (do NOT move to top)
	for i in range(preview_queue.size()):
		_add_preview_proj(preview_queue[i], false)

	_layout_previews()

func _layout_previews() -> void:
	# child index i == queue index i
	# i=0 is TOP visually, i=last is BOTTOM
	var n := spawnpoint.get_child_count()
	for i in range(n):
		var child := spawnpoint.get_child(i)
		# Position/animate each child here if you want, e.g.:
		# child.position = Vector2(0, i * 24)

func _add_preview_proj(ammo_index: int, insert_at_top: bool) -> Node2D:
	var p := ProjectileScene.instantiate()
	if p == null:
		push_error("ProjectileScene failed to instantiate")
		return null

	spawnpoint.add_child(p)

	if insert_at_top:
		# Only used when adding a BRAND-NEW preview during gameplay
		spawnpoint.move_child(p, 0)

	_set_proj_index(p, ammo_index)

	# mark as preview (not a real, fired projectile)
	if p.has_method("set_loaded"):
		p.call("set_loaded", false)

	return p

# ---------------------------
# Consume bottom (next-to-fire), add new at top
# ---------------------------
func load_next() -> void:
	if preview_queue.is_empty():
		return

	# BOTTOM is next-to-fire
	var next_index: int = preview_queue.back()

	# 1) drop the bottom preview (visual)
	var child_count := spawnpoint.get_child_count()
	if child_count > 0:
		var falling := spawnpoint.get_child(child_count - 1) # bottom child
		spawnpoint.remove_child(falling)
		add_child(falling)     # preserve global transform
		_make_preview_fall(falling)

	# 2) pop from the back of the queue (bottom)
	preview_queue.pop_back()

	# 3) tell the weapon code which ammo to spawn
	emit_signal("next_ammo_ready", next_index)

	# 4) add a brand-new preview at the TOP (front)
	var new_idx := randi_range(0, 5)
	preview_queue.push_front(new_idx)
	_add_preview_proj(new_idx, true)

	# 5) re-layout so everything marches downward
	_layout_previews()

# ---------------------------
# Helpers
# ---------------------------
func _set_proj_index(proj: Node, ammo_index: int) -> void:
	if proj.sprite and proj.sprite.has_method("set_ammo_index"):
		proj.sprite.call("set_ammo_index", ammo_index)

func _make_preview_fall(node: Node) -> void:
	var collider := node.get_node_or_null("CollisionShape2D")
	if collider and collider is CollisionShape2D:
		(collider as CollisionShape2D).disabled = true

	var v := VisibleOnScreenNotifier2D.new()
	node.add_child(v)
	v.connect("screen_exited", Callable(node, "queue_free"))
