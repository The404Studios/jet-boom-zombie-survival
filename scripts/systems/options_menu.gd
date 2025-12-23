extends Control
class_name OptionsMenu

@export var psx_post_process_material: ShaderMaterial

@onready var dither_slider: HSlider = $Panel/VBox/DitherSlider if has_node("Panel/VBox/DitherSlider") else null
@onready var color_depth_slider: HSlider = $Panel/VBox/ColorDepthSlider if has_node("Panel/VBox/ColorDepthSlider") else null
@onready var vertex_snap_slider: HSlider = $Panel/VBox/VertexSnapSlider if has_node("Panel/VBox/VertexSnapSlider") else null
@onready var scanlines_check: CheckBox = $Panel/VBox/ScanlinesCheck if has_node("Panel/VBox/ScanlinesCheck") else null
@onready var fps_label: Label = $Panel/VBox/FPSLabel if has_node("Panel/VBox/FPSLabel") else null

var fps_limit: int = 144

func _ready():
	visible = false

func _input(event):
	if event.is_action_pressed("ui_cancel"):
		toggle_menu()

func toggle_menu():
	visible = !visible
	if visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_dither_changed(value: float):
	if psx_post_process_material:
		psx_post_process_material.set_shader_parameter("dither_amount", value)

func _on_color_depth_changed(value: float):
	if psx_post_process_material:
		psx_post_process_material.set_shader_parameter("color_depth", value)

func _on_scanlines_toggled(enabled: bool):
	if psx_post_process_material:
		psx_post_process_material.set_shader_parameter("enable_scanlines", enabled)

func _on_fps_limit_changed(value: float):
	fps_limit = int(value)
	Engine.max_fps = fps_limit
	if fps_label:
		fps_label.text = "FPS Limit: %d" % fps_limit

func _process(_delta):
	# Update FPS display
	if fps_label and visible:
		fps_label.text = "FPS: %d / %d" % [Engine.get_frames_per_second(), fps_limit]
