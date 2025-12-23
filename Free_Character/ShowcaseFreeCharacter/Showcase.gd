extends Spatial

func _ready():
	pass # Replace with function body.

func _on_Timer_timeout():
	GBackgroundLoader.goto_scene("res://Showcase2.tscn")
