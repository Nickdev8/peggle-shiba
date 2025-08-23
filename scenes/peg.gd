extends Node2D
@export var radius: float = 6.0
@export var is_goal: bool = false

func _ready() -> void:
	add_to_group("peg")
	if is_goal: add_to_group("destructible")
