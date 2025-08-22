extends Node2D

var TargetScene := preload("res://scenes/target.tscn")

var WIDTH: float = 150.0
var HEIGHT: float = 100.0

var levels: Array = [
	["x","x","x","x"],
	["x","x","x","x"],
	["x","x","x","x"]
]

func _ready() -> void:
	var rows: int = levels.size()
	var cols: int = (levels[0] as Array).size()

	# spacing between targets
	var x_spacing: float = 0.0
	var y_spacing: float = 0.0

	if cols > 1:
		x_spacing = WIDTH / (cols - 1)
	if rows > 1:
		y_spacing = HEIGHT / (rows - 1)

	# offset so (0,0) is screen center
	var x_offset: float = -WIDTH / 2.0
	var y_offset: float = -HEIGHT / 2.0

	for i in range(rows):
		var row: Array = levels[i]
		for j in range(row.size()):
			if row[j] == "x":
				var x: float = j * x_spacing + x_offset
				var y: float = i * y_spacing + y_offset - 30
				_spawn_target(Vector2(x, y))

func _spawn_target(pos: Vector2) -> void:
	var _target = TargetScene.instantiate()
	_target.global_position = pos
	_target.show()
	get_tree().current_scene.call_deferred("add_child", _target)
