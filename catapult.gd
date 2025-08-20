extends Node2D

@export var sack: Node2D
@export var maxdistance: float = 50.0
@export var stiffness: float = 12.0   # spring stiffness
@export var damping: float = 2.5      # resistance, keeps it from oscillating forever

var velocity: Vector2 = Vector2.ZERO

func _process(delta: float) -> void:
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mouse: Vector2 = get_global_mouse_position()
		var dir: Vector2 = global_position.direction_to(mouse)
		var d: float = global_position.distance_to(mouse)

		# Desired target = inside circle at maxdistance, pointing toward mouse
		var clamped_len: float = min(d, maxdistance)
		var target: Vector2 = global_position + dir * clamped_len

		# Spring force toward target
		var displacement: Vector2 = sack.global_position - target
		var accel: Vector2 = -stiffness * displacement - damping * velocity

		# Integrate
		velocity += accel * delta
		sack.global_position += velocity * delta
	else:
		# Reset when not dragging
		velocity = Vector2.ZERO
		sack.global_position = global_position
