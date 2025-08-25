extends Sprite2D

const heads: Array =[
	preload("res://assets/organizers/jered.png"),
	preload("res://assets/organizers/kailing.png"),
	preload("res://assets/organizers/paolo.png"),
	preload("res://assets/organizers/thomas.png"),
	preload("res://assets/organizers/tongyu.png"),
	preload("res://assets/organizers/zach.png")
]

const heads_fire: Array =[
	preload("res://assets/organizers/jaredscreeming.png"),
	preload("res://assets/organizers/kailingscreeming.png"),
	preload("res://assets/organizers/paoloscreeming.png"),
	preload("res://assets/organizers/thomasscreem.png"),
	preload("res://assets/organizers/tongyuscreem.png"),
	preload("res://assets/organizers/zachscream.png")
]

var index: int
var has_been_shot: bool = false

func _ready() -> void:
	index = randi_range(0, heads.size()-1)
	texture = heads[index]

func render_shoot():
	has_been_shot = true

func update_shoot(vel:Vector2):
	var is_still:bool = false
	if vel < Vector2(50,20) and vel > Vector2.ZERO:
		is_still = true
	elif vel > Vector2(-50,-20) and vel < Vector2.ZERO:
		is_still = true
	
	if has_been_shot and !is_still:
		texture = heads_fire[index]
	else:
		texture = heads[index]	
