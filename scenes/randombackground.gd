extends TextureRect
const GITHUB = preload("res://assets/backgrounds/github.jpg")
const JUICE = preload("res://assets/backgrounds/juice.JPG")
const KAILING = preload("res://assets/backgrounds/kailing.png")
@onready var texture_rect: TextureRect = $".."

const backgrounds: Array = [GITHUB, JUICE, KAILING]
var index

func _ready() -> void:
	index = randi_range(0, backgrounds.size()-1)
	texture = backgrounds[index]
	texture_rect.position = Vector2.ZERO
	show()
