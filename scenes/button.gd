extends Button
const BUTTON_2 = preload("res://assets/button2.png")
const BUTTON = preload("res://assets/button.png")

func _process(delta: float) -> void:
	if not button_pressed:
		icon = BUTTON_2

func _on_pressed() -> void:
	icon = BUTTON


func _on_toggled(toggled_on: bool) -> void:
	print(toggled_on)


func _on_button_up() -> void:
	print("up")
