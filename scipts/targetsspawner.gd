extends Node2D

var TargetScene := preload("res://scenes/target.tscn")

var levels: Array[String] = [
	"eooexxxx                xxxx",
	"         xx                 ",
	"         xx             x  x",
	"e                        xx ",
	"  e                         ",
	"    e                       ",
	"      e                     ",
	"        e                   ",
	"          e                 ",
	"                     xxxx   ",
]


# If true, we keep everything inside WIDTH; if false, we always maximize height even if it overflows horizontally.
const CONTAIN_WITHIN_WIDTH := false

func _ready() -> void:
	var rows: int = levels.size()
	var cols: int = 0
	for s in levels:
		if s.length() > cols:
			cols = s.length()

	if rows <= 1 or cols <= 1:
		return

	# Always maximize height: cell from HEIGHT & rows
	var cell_from_height: float = Global.HEIGHT / float(rows - 1)

	# Optional clamp to fit WIDTH as well
	var cell_from_width: float = Global.WIDTH / float(cols - 1)
	var cell: float = min(cell_from_height, cell_from_width) if CONTAIN_WITHIN_WIDTH else cell_from_height

	# Center the grid based on the chosen cell size
	var grid_w: float = cell * float(cols - 1)
	var grid_h: float = cell * float(rows - 1)
	var x_offset: float = -grid_w / 2.0
	var y_offset: float = -grid_h / 2.0

	for i in range(rows):
		var row: String = levels[i].rpad(cols, " ")
		for j in range(cols):
			var ch := row[j]
			if ch == "x" or ch == "o" or ch == "e":
				var pos := Vector2(j * cell + x_offset, i * cell + y_offset - 30.0)
				_spawn_target(pos, 1 if ch == "x" else 0 if ch == "o" else 3)

func _spawn_target(pos: Vector2, sprite_frame) -> void:
	var target = TargetScene.instantiate()
	var target_sprite: AnimatedSprite2D = target.get_child(0)
	target_sprite.frame = sprite_frame
	target.global_position = pos
	target.show()
	add_child(target)
