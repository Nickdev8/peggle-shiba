extends Area2D

@export var speed: float = 500.0
@export var lifetime: float = 3.0  # seconds before despawn
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	print("Yo I'm here yall")
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _physics_process(delta: float) -> void:
	global_position += velocity * delta

func shoot(direction: Vector2, distance: float) -> void:
	velocity = direction.normalized() * speed * (distance/150) # distance == 0>150
	print(distance)
	print("I'm heading somewhere dude")

func _on_body_entered(body: Node) -> void:
	#queue_free()
	print("i've hitsomething bro")
