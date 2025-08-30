extends Node2D

signal next_ammo_ready(ammo_index: int) # emit so another script can spawn the real projectile

@onready var spawnpoint: Node2D = $spawnpoint

@export var preview_count: int = 5

const ProjectileScene := preload("res://scenes/previewprojectile.tscn")

# queue order mirrors visual order:
#   queue[0] = TOP (newest), queue.back() = BOTTOM (next-to-fire)
var preview_queue: Array[int] = []

func _ready() -> void:
	_init_preview()

# ---------------------------
# Initialization / layout
# ---------------------------
func _init_preview() -> void:
	# clear visuals
	for c in spawnpoint.get_children():
		c.queue_free()
	preview_queue.clear()

	# Build so that the FIRST created ends at the BOTTOM.
	# We insert each new element at the TOP (front), pushing older ones downward.
	for i in range(preview_count):
		var idx := randi_range(0, 5)
		preview_queue.push_front(idx)      # put newest at TOP
		_add_preview_proj(idx, true)
		_layout_previews()
		await get_tree().create_timer(0.01).timeout

func _layout_previews() -> void:
	# child index i == queue index i
	# i=0 is TOP visually, i=last is BOTTOM
	var n := spawnpoint.get_child_count()
	for i in range(n):
		var child := spawnpoint.get_child(i)

func _add_preview_proj(ammo_index: int, insert_at_top: bool) -> Node2D:
	var p := ProjectileScene.instantiate()
	if p == null:
		push_error("ProjectileScene failed to instantiate")
		return null

	spawnpoint.add_child(p)
	if insert_at_top:
		# make it the first child so others shift down
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
	print_debug(preview_queue)
	if proj.sprite and proj.sprite.has_method("set_ammo_index"):
		proj.sprite.call("set_ammo_index", ammo_index)
		return

func _make_preview_fall(node: Node) -> void:
	# optional: disable collisions so it doesn't interfere
	var collider := node.get_node_or_null("CollisionShape2D")
	if collider and collider is CollisionShape2D:
		(collider as CollisionShape2D).disabled = true

	# auto-clean when off-screen
	var v := VisibleOnScreenNotifier2D.new()
	node.add_child(v)
	v.connect("screen_exited", Callable(node, "queue_free"))
