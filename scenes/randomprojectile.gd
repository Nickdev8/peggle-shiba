extends Sprite2D

const heads: Array =[
	preload("res://assets/organizers/zach.png"),
	preload("res://assets/organizers/jered.png"),
	preload("res://assets/organizers/kailing.png"),
	preload("res://assets/organizers/paolo.png"),
	preload("res://assets/organizers/thomas.png"),
	preload("res://assets/organizers/tongyu.png")
]

const heads_fire: Array =[
	preload("res://assets/organizers/zachscream.png"),
	preload("res://assets/organizers/jaredscreeming.png"),
	preload("res://assets/organizers/kailingscreeming.png"),
	preload("res://assets/organizers/paoloscreeming.png"),
	preload("res://assets/organizers/thomasscreem.png"),
	preload("res://assets/organizers/tongyuscreem.png")
]

var index: int = -1
var has_been_shot: bool = false

func _ready() -> void:
	if index != -1:
		texture = heads[index]
		
func set_ammo_index(newindex:int):
	index = newindex
	texture = heads[index]
	

func render_shoot():
	has_been_shot = true

func update_shoot(vel:Vector2):
	if has_been_shot and !vel.length() < 100:
		texture = heads_fire[index]
	else:
		texture = heads[index]	
