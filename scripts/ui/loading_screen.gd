extends CanvasLayer
class_name LoadingScreen

# Loading screen with progress bar and tips
# Shows during map transitions and initial load

signal loading_complete
signal loading_cancelled

# UI References
var background: ColorRect
var container: VBoxContainer
var title_label: Label
var subtitle_label: Label
var progress_bar: ProgressBar
var progress_label: Label
var tip_label: Label
var cancel_button: Button
var spinner: Control

# Loading state
var is_loading: bool = false
var current_progress: float = 0.0
var target_progress: float = 0.0
var load_operations: Array = []
var current_operation: int = 0

# Visual settings
@export var fade_duration: float = 0.5
@export var progress_smooth_speed: float = 3.0
@export var tip_change_interval: float = 5.0

# Tips
var tips: Array = [
	"Barricade doors to slow down zombies!",
	"Headshots deal 2x damage to zombies.",
	"Stick with your team - lone wolves don't survive long.",
	"Engineers can repair barricades faster than other classes.",
	"Use sigils to teleport to linked locations.",
	"The Scout class can see zombies through walls on the minimap.",
	"Medics heal nearby allies passively.",
	"Save your points for emergencies - you might need that ammo.",
	"Different zombie types have different weaknesses.",
	"Check corners - crawlers like to hide.",
	"The Tank class can draw zombie aggro with their taunt ability.",
	"Demolitionists take reduced damage from their own explosives.",
	"Special zombies spawn more frequently in later waves.",
	"Extract before the timer runs out or lose your loot!",
	"Trading with teammates can give you the weapon you need.",
	"Voice chat helps coordinate with your team.",
	"Press TAB to view the scoreboard during gameplay.",
	"Hold Q to open the weapon wheel for quick switching.",
	"Reload before a big fight - don't get caught empty!",
	"Killing zombies earns points to buy weapons and upgrades."
]

var tip_timer: float = 0.0
var current_tip_index: int = 0
var spinner_rotation: float = 0.0

func _ready():
	layer = 100  # Above everything
	_create_ui()
	visible = false

func _create_ui():
	# Full screen dark background
	background = ColorRect.new()
	background.color = Color(0.05, 0.05, 0.08, 1.0)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(background)

	# Main container
	container = VBoxContainer.new()
	container.set_anchors_preset(Control.PRESET_CENTER)
	container.grow_horizontal = Control.GROW_DIRECTION_BOTH
	container.grow_vertical = Control.GROW_DIRECTION_BOTH
	container.custom_minimum_size = Vector2(600, 400)
	container.add_theme_constant_override("separation", 20)
	background.add_child(container)

	# Center the container
	container.position = Vector2(-300, -200)
	container.set_anchors_preset(Control.PRESET_CENTER)

	# Logo/Title area
	var title_container = VBoxContainer.new()
	title_container.add_theme_constant_override("separation", 5)
	container.add_child(title_container)

	title_label = Label.new()
	title_label.text = "ZOMBIE SURVIVAL"
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	title_container.add_child(title_label)

	subtitle_label = Label.new()
	subtitle_label.text = "Loading..."
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.add_theme_font_size_override("font_size", 18)
	subtitle_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title_container.add_child(subtitle_label)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	container.add_child(spacer)

	# Spinner (simple rotating element)
	var spinner_container = CenterContainer.new()
	container.add_child(spinner_container)

	spinner = Control.new()
	spinner.custom_minimum_size = Vector2(60, 60)
	spinner_container.add_child(spinner)

	# Create spinner visuals using ColorRects
	for i in range(8):
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		var angle = i * TAU / 8
		var radius = 25.0
		dot.position = Vector2(30 + cos(angle) * radius - 4, 30 + sin(angle) * radius - 4)
		dot.color = Color(1, 0.8, 0.3, 1.0 - (i * 0.1))
		spinner.add_child(dot)

	# Progress bar container
	var progress_container = VBoxContainer.new()
	progress_container.add_theme_constant_override("separation", 8)
	container.add_child(progress_container)

	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(500, 20)
	progress_bar.max_value = 100.0
	progress_bar.value = 0.0
	progress_bar.show_percentage = false
	progress_container.add_child(progress_bar)

	# Style the progress bar
	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.15, 0.15, 0.18)
	bar_bg.corner_radius_top_left = 4
	bar_bg.corner_radius_top_right = 4
	bar_bg.corner_radius_bottom_left = 4
	bar_bg.corner_radius_bottom_right = 4
	progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.3, 0.7, 0.3)
	bar_fill.corner_radius_top_left = 4
	bar_fill.corner_radius_top_right = 4
	bar_fill.corner_radius_bottom_left = 4
	bar_fill.corner_radius_bottom_right = 4
	progress_bar.add_theme_stylebox_override("fill", bar_fill)

	progress_label = Label.new()
	progress_label.text = "0%"
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	progress_label.add_theme_font_size_override("font_size", 14)
	progress_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	progress_container.add_child(progress_label)

	# Tip container at bottom
	var tip_container = PanelContainer.new()
	tip_container.custom_minimum_size = Vector2(500, 60)
	container.add_child(tip_container)

	var tip_style = StyleBoxFlat.new()
	tip_style.bg_color = Color(0.1, 0.1, 0.12, 0.8)
	tip_style.corner_radius_top_left = 8
	tip_style.corner_radius_top_right = 8
	tip_style.corner_radius_bottom_left = 8
	tip_style.corner_radius_bottom_right = 8
	tip_container.add_theme_stylebox_override("panel", tip_style)

	var tip_margin = MarginContainer.new()
	tip_margin.add_theme_constant_override("margin_left", 15)
	tip_margin.add_theme_constant_override("margin_right", 15)
	tip_margin.add_theme_constant_override("margin_top", 10)
	tip_margin.add_theme_constant_override("margin_bottom", 10)
	tip_container.add_child(tip_margin)

	var tip_vbox = VBoxContainer.new()
	tip_vbox.add_theme_constant_override("separation", 5)
	tip_margin.add_child(tip_vbox)

	var tip_header = Label.new()
	tip_header.text = "TIP:"
	tip_header.add_theme_font_size_override("font_size", 12)
	tip_header.add_theme_color_override("font_color", Color(1, 0.8, 0.3))
	tip_vbox.add_child(tip_header)

	tip_label = Label.new()
	tip_label.text = tips[0]
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.add_theme_font_size_override("font_size", 14)
	tip_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	tip_vbox.add_child(tip_label)

	# Cancel button (optional, hidden by default)
	cancel_button = Button.new()
	cancel_button.text = "CANCEL"
	cancel_button.custom_minimum_size = Vector2(120, 35)
	cancel_button.visible = false
	cancel_button.pressed.connect(_on_cancel_pressed)
	container.add_child(cancel_button)

	# Center align button
	var button_container = CenterContainer.new()
	container.add_child(button_container)
	button_container.add_child(cancel_button)

func _process(delta):
	if not is_loading:
		return

	# Animate spinner
	spinner_rotation += delta * 180  # degrees per second
	if spinner:
		spinner.rotation_degrees = spinner_rotation

	# Smooth progress
	current_progress = lerp(current_progress, target_progress, delta * progress_smooth_speed)
	progress_bar.value = current_progress
	progress_label.text = "%d%%" % int(current_progress)

	# Cycle tips
	tip_timer += delta
	if tip_timer >= tip_change_interval:
		tip_timer = 0.0
		_show_next_tip()

	# Check if loading complete
	if current_progress >= 99.5 and target_progress >= 100.0:
		_on_loading_complete()

func _show_next_tip():
	current_tip_index = (current_tip_index + 1) % tips.size()

	# Fade out/in animation
	var tween = create_tween()
	tween.tween_property(tip_label, "modulate:a", 0.0, 0.2)
	tween.tween_callback(func(): tip_label.text = tips[current_tip_index])
	tween.tween_property(tip_label, "modulate:a", 1.0, 0.2)

# ============================================
# PUBLIC API
# ============================================

func show_loading(title: String = "Loading...", allow_cancel: bool = false):
	"""Show the loading screen"""
	is_loading = true
	current_progress = 0.0
	target_progress = 0.0
	tip_timer = 0.0

	subtitle_label.text = title
	cancel_button.visible = allow_cancel

	# Randomize starting tip
	current_tip_index = randi() % tips.size()
	tip_label.text = tips[current_tip_index]

	# Fade in
	visible = true
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, fade_duration)

func hide_loading():
	"""Hide the loading screen"""
	is_loading = false

	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	tween.tween_callback(func(): visible = false)

func set_progress(progress: float, status_text: String = ""):
	"""Set loading progress (0-100)"""
	target_progress = clamp(progress, 0.0, 100.0)

	if not status_text.is_empty():
		subtitle_label.text = status_text

func set_status(text: String):
	"""Update status text"""
	subtitle_label.text = text

func add_tip(tip: String):
	"""Add a custom tip"""
	tips.append(tip)

func set_tips(custom_tips: Array):
	"""Replace tips with custom array"""
	tips = custom_tips

# ============================================
# ASYNC LOADING HELPERS
# ============================================

func start_loading_scene(scene_path: String):
	"""Start loading a scene asynchronously"""
	show_loading("Loading Map...")

	# Use ResourceLoader for async loading
	var error = ResourceLoader.load_threaded_request(scene_path)
	if error != OK:
		push_error("Failed to start loading scene: %s" % scene_path)
		set_status("Error loading scene!")
		return

	# Monitor loading
	_monitor_scene_load(scene_path)

func _monitor_scene_load(scene_path: String):
	"""Monitor async scene loading progress"""
	var progress_array = []

	while true:
		var status = ResourceLoader.load_threaded_get_status(scene_path, progress_array)

		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var progress = progress_array[0] * 100.0 if progress_array.size() > 0 else 0.0
				set_progress(progress, "Loading assets...")
				await get_tree().process_frame

			ResourceLoader.THREAD_LOAD_LOADED:
				set_progress(100.0, "Complete!")
				var scene = ResourceLoader.load_threaded_get(scene_path)
				await get_tree().create_timer(0.5).timeout
				loading_complete.emit()
				# Scene is ready - caller should handle scene change
				return scene

			ResourceLoader.THREAD_LOAD_FAILED:
				set_status("Failed to load scene!")
				push_error("Failed to load scene: %s" % scene_path)
				return null

			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				set_status("Invalid scene!")
				push_error("Invalid scene resource: %s" % scene_path)
				return null

func load_multiple_resources(resources: Array) -> Dictionary:
	"""Load multiple resources with combined progress"""
	show_loading("Loading resources...")

	var loaded = {}
	var total = resources.size()
	var current = 0

	for res_path in resources:
		set_status("Loading: %s" % res_path.get_file())

		# Start async load
		ResourceLoader.load_threaded_request(res_path)

		# Wait for it
		var progress_array = []
		while true:
			var status = ResourceLoader.load_threaded_get_status(res_path, progress_array)

			if status == ResourceLoader.THREAD_LOAD_LOADED:
				loaded[res_path] = ResourceLoader.load_threaded_get(res_path)
				current += 1
				set_progress((float(current) / total) * 100.0)
				break
			elif status == ResourceLoader.THREAD_LOAD_FAILED:
				push_error("Failed to load: %s" % res_path)
				current += 1
				break
			elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var sub_progress = progress_array[0] if progress_array.size() > 0 else 0.0
				var total_progress = ((current + sub_progress) / total) * 100.0
				set_progress(total_progress)

			await get_tree().process_frame

	set_progress(100.0, "Complete!")
	await get_tree().create_timer(0.3).timeout
	loading_complete.emit()

	return loaded

# ============================================
# CALLBACKS
# ============================================

func _on_cancel_pressed():
	is_loading = false
	loading_cancelled.emit()
	hide_loading()

func _on_loading_complete():
	is_loading = false
	loading_complete.emit()
