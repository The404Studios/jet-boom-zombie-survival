extends Control
class_name AuthScreen

# Beautiful animated authentication screen
# Requires: Access Key -> Login/Register -> Main Menu

signal authentication_complete(player_data: Dictionary)
signal back_to_menu

# Auth states
enum AuthState { ACCESS_KEY, LOGIN, REGISTER }
var current_state: AuthState = AuthState.ACCESS_KEY

# Backend reference
var backend: Node = null

# UI containers
var main_container: Control
var background: ColorRect
var particles_container: Control
var logo_container: VBoxContainer
var form_container: PanelContainer
var form_inner: VBoxContainer

# Access key form
var access_key_container: VBoxContainer
var access_key_input: LineEdit
var access_key_button: Button
var access_key_error: Label

# Login form
var login_container: VBoxContainer
var login_username: LineEdit
var login_password: LineEdit
var login_button: Button
var login_error: Label

# Register form
var register_container: VBoxContainer
var register_username: LineEdit
var register_email: LineEdit
var register_password: LineEdit
var register_confirm: LineEdit
var register_button: Button
var register_error: Label

# Loading indicator
var loading_spinner: Control
var loading_label: Label

# Animation state
var is_loading: bool = false
var particle_nodes: Array = []
var time_elapsed: float = 0.0

func _ready():
	backend = get_node_or_null("/root/Backend")

	# Create the full UI
	_create_background()
	_create_particles()
	_create_main_ui()

	# Connect backend signals
	_connect_signals()

	# Check if we already have a valid access key
	if backend and backend.has_valid_access_key():
		current_state = AuthState.LOGIN
		# Check if already authenticated
		if backend.is_authenticated:
			authentication_complete.emit(backend.current_player)
			return

	# Show initial state with animation
	_show_current_state()
	_animate_entrance()

func _process(delta):
	time_elapsed += delta
	_update_particles(delta)
	_update_loading_spinner(delta)

# ============================================
# UI CREATION
# ============================================

func _create_background():
	# Gradient background
	background = ColorRect.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.02, 0.02, 0.05, 1.0)
	add_child(background)

	# Add subtle gradient overlay
	var gradient_overlay = ColorRect.new()
	gradient_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	gradient_overlay.color = Color(0.05, 0.02, 0.08, 0.5)
	add_child(gradient_overlay)

func _create_particles():
	particles_container = Control.new()
	particles_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	particles_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(particles_container)

	# Create floating particles
	for i in range(30):
		var particle = ColorRect.new()
		particle.size = Vector2(randf_range(2, 6), randf_range(2, 6))
		particle.color = Color(1.0, 0.8, 0.3, randf_range(0.1, 0.3))
		particle.position = Vector2(randf_range(0, 1920), randf_range(0, 1080))
		particle.set_meta("speed", randf_range(20, 60))
		particle.set_meta("drift", randf_range(-30, 30))
		particle.set_meta("phase", randf_range(0, TAU))
		particles_container.add_child(particle)
		particle_nodes.append(particle)

func _update_particles(delta: float):
	var viewport_size = get_viewport_rect().size
	for particle in particle_nodes:
		if not is_instance_valid(particle):
			continue
		var speed = particle.get_meta("speed")
		var drift = particle.get_meta("drift")
		var phase = particle.get_meta("phase")

		particle.position.y -= speed * delta
		particle.position.x += sin(time_elapsed + phase) * drift * delta

		# Wrap around
		if particle.position.y < -10:
			particle.position.y = viewport_size.y + 10
			particle.position.x = randf_range(0, viewport_size.x)

func _create_main_ui():
	main_container = Control.new()
	main_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(main_container)

	# Center everything
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	main_container.add_child(center)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 30)
	center.add_child(main_vbox)

	# Logo/Title section
	_create_logo_section(main_vbox)

	# Form panel
	_create_form_panel(main_vbox)

	# Loading indicator
	_create_loading_indicator(main_vbox)

func _create_logo_section(parent: Control):
	logo_container = VBoxContainer.new()
	logo_container.add_theme_constant_override("separation", 10)
	parent.add_child(logo_container)

	# Main title
	var title = Label.new()
	title.text = "ZOMBIE SURVIVAL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	title.add_theme_color_override("font_shadow_color", Color(0.8, 0.4, 0.1, 0.5))
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	logo_container.add_child(title)

	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "THE LAST STAND"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8, 0.8))
	logo_container.add_child(subtitle)

	# Server status
	var server_label = Label.new()
	server_label.name = "ServerStatus"
	server_label.text = "Server: 162.248.94.23"
	server_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	server_label.add_theme_font_size_override("font_size", 12)
	server_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5, 0.7))
	logo_container.add_child(server_label)

func _create_form_panel(parent: Control):
	form_container = PanelContainer.new()
	form_container.custom_minimum_size = Vector2(420, 0)
	parent.add_child(form_container)

	# Style the panel
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.95)
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_color = Color(1, 0.75, 0.2, 0.4)
	style.shadow_color = Color(0, 0, 0, 0.5)
	style.shadow_size = 10
	form_container.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 35)
	margin.add_theme_constant_override("margin_right", 35)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 30)
	form_container.add_child(margin)

	form_inner = VBoxContainer.new()
	form_inner.add_theme_constant_override("separation", 20)
	margin.add_child(form_inner)

	# Create all form containers
	_create_access_key_form()
	_create_login_form()
	_create_register_form()

func _create_access_key_form():
	access_key_container = VBoxContainer.new()
	access_key_container.add_theme_constant_override("separation", 15)
	form_inner.add_child(access_key_container)

	# Title
	var title = Label.new()
	title.text = "ACCESS KEY REQUIRED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	access_key_container.add_child(title)

	# Description
	var desc = Label.new()
	desc.text = "Enter your server-issued access key to continue"
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	access_key_container.add_child(desc)

	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size.y = 10
	access_key_container.add_child(spacer)

	# Access key input
	access_key_input = _create_styled_input("Enter access key...", false)
	access_key_input.text_submitted.connect(_on_access_key_submitted)
	access_key_container.add_child(access_key_input)

	# Error label
	access_key_error = _create_error_label()
	access_key_container.add_child(access_key_error)

	# Submit button
	access_key_button = _create_styled_button("VALIDATE KEY", Color(0.3, 0.5, 0.8))
	access_key_button.pressed.connect(_on_access_key_submit)
	access_key_container.add_child(access_key_button)

func _create_login_form():
	login_container = VBoxContainer.new()
	login_container.add_theme_constant_override("separation", 12)
	login_container.visible = false
	form_inner.add_child(login_container)

	# Title
	var title = Label.new()
	title.text = "SIGN IN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	login_container.add_child(title)

	# Username
	var user_label = _create_field_label("Username")
	login_container.add_child(user_label)
	login_username = _create_styled_input("Enter username...")
	login_container.add_child(login_username)

	# Password
	var pass_label = _create_field_label("Password")
	login_container.add_child(pass_label)
	login_password = _create_styled_input("Enter password...", true)
	login_password.text_submitted.connect(_on_login_submitted)
	login_container.add_child(login_password)

	# Error label
	login_error = _create_error_label()
	login_container.add_child(login_error)

	# Login button
	login_button = _create_styled_button("SIGN IN", Color(0.3, 0.6, 0.3))
	login_button.pressed.connect(_on_login_submit)
	login_container.add_child(login_button)

	# Switch to register
	var switch_box = HBoxContainer.new()
	switch_box.alignment = BoxContainer.ALIGNMENT_CENTER
	switch_box.add_theme_constant_override("separation", 8)
	login_container.add_child(switch_box)

	var switch_label = Label.new()
	switch_label.text = "Don't have an account?"
	switch_label.add_theme_font_size_override("font_size", 12)
	switch_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	switch_box.add_child(switch_label)

	var switch_btn = Button.new()
	switch_btn.text = "Register"
	switch_btn.flat = true
	switch_btn.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	switch_btn.add_theme_font_size_override("font_size", 12)
	switch_btn.pressed.connect(_switch_to_register)
	switch_box.add_child(switch_btn)

func _create_register_form():
	register_container = VBoxContainer.new()
	register_container.add_theme_constant_override("separation", 10)
	register_container.visible = false
	form_inner.add_child(register_container)

	# Title
	var title = Label.new()
	title.text = "CREATE ACCOUNT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	register_container.add_child(title)

	# Username
	var user_label = _create_field_label("Username")
	register_container.add_child(user_label)
	register_username = _create_styled_input("Choose username...")
	register_container.add_child(register_username)

	# Email
	var email_label = _create_field_label("Email")
	register_container.add_child(email_label)
	register_email = _create_styled_input("Enter email...")
	register_container.add_child(register_email)

	# Password
	var pass_label = _create_field_label("Password")
	register_container.add_child(pass_label)
	register_password = _create_styled_input("Choose password...", true)
	register_container.add_child(register_password)

	# Confirm password
	var confirm_label = _create_field_label("Confirm Password")
	register_container.add_child(confirm_label)
	register_confirm = _create_styled_input("Confirm password...", true)
	register_confirm.text_submitted.connect(_on_register_submitted)
	register_container.add_child(register_confirm)

	# Error label
	register_error = _create_error_label()
	register_container.add_child(register_error)

	# Register button
	register_button = _create_styled_button("CREATE ACCOUNT", Color(0.3, 0.5, 0.7))
	register_button.pressed.connect(_on_register_submit)
	register_container.add_child(register_button)

	# Switch to login
	var switch_box = HBoxContainer.new()
	switch_box.alignment = BoxContainer.ALIGNMENT_CENTER
	switch_box.add_theme_constant_override("separation", 8)
	register_container.add_child(switch_box)

	var switch_label = Label.new()
	switch_label.text = "Already have an account?"
	switch_label.add_theme_font_size_override("font_size", 12)
	switch_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	switch_box.add_child(switch_label)

	var switch_btn = Button.new()
	switch_btn.text = "Sign In"
	switch_btn.flat = true
	switch_btn.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	switch_btn.add_theme_font_size_override("font_size", 12)
	switch_btn.pressed.connect(_switch_to_login)
	switch_box.add_child(switch_btn)

func _create_loading_indicator(parent: Control):
	var loading_box = VBoxContainer.new()
	loading_box.add_theme_constant_override("separation", 10)
	loading_box.visible = false
	loading_box.name = "LoadingBox"
	parent.add_child(loading_box)

	# Spinner container
	loading_spinner = Control.new()
	loading_spinner.custom_minimum_size = Vector2(40, 40)
	loading_box.add_child(loading_spinner)

	# Create spinner dots
	for i in range(8):
		var dot = ColorRect.new()
		dot.size = Vector2(6, 6)
		dot.color = Color(1, 0.85, 0.3, 0.8)
		loading_spinner.add_child(dot)

	loading_label = Label.new()
	loading_label.text = "Connecting..."
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	loading_label.add_theme_font_size_override("font_size", 14)
	loading_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	loading_box.add_child(loading_label)

func _update_loading_spinner(delta: float):
	if not is_loading or not loading_spinner:
		return

	var center = loading_spinner.size / 2
	var radius = 15.0
	var dots = loading_spinner.get_children()
	for i in range(dots.size()):
		var angle = (time_elapsed * 3.0) + (i * TAU / dots.size())
		var dot = dots[i] as ColorRect
		if dot:
			dot.position = center + Vector2(cos(angle), sin(angle)) * radius - dot.size / 2
			dot.modulate.a = 0.3 + 0.7 * ((sin(angle + time_elapsed * 2) + 1) / 2)

# ============================================
# HELPER FUNCTIONS
# ============================================

func _create_styled_input(placeholder: String, secret: bool = false) -> LineEdit:
	var input = LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = secret
	input.custom_minimum_size = Vector2(0, 45)
	input.add_theme_font_size_override("font_size", 15)

	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.3, 0.4)
	style.content_margin_left = 15
	style.content_margin_right = 15
	input.add_theme_stylebox_override("normal", style)

	var focus_style = style.duplicate()
	focus_style.border_color = Color(1, 0.75, 0.2, 0.8)
	input.add_theme_stylebox_override("focus", focus_style)

	return input

func _create_styled_button(text: String, color: Color) -> Button:
	var btn = Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 50)
	btn.add_theme_font_size_override("font_size", 16)

	var style = StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", style)

	var hover_style = style.duplicate()
	hover_style.bg_color = color.lightened(0.15)
	btn.add_theme_stylebox_override("hover", hover_style)

	var pressed_style = style.duplicate()
	pressed_style.bg_color = color.darkened(0.15)
	btn.add_theme_stylebox_override("pressed", pressed_style)

	var disabled_style = style.duplicate()
	disabled_style.bg_color = Color(0.2, 0.2, 0.25)
	btn.add_theme_stylebox_override("disabled", disabled_style)

	return btn

func _create_field_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	return label

func _create_error_label() -> Label:
	var label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.visible = false
	return label

# ============================================
# ANIMATIONS
# ============================================

func _animate_entrance():
	# Animate logo
	logo_container.modulate.a = 0
	logo_container.position.y = -30
	var logo_tween = create_tween()
	logo_tween.set_parallel(true)
	logo_tween.tween_property(logo_container, "modulate:a", 1.0, 0.6).set_ease(Tween.EASE_OUT)
	logo_tween.tween_property(logo_container, "position:y", 0.0, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

	# Animate form
	form_container.modulate.a = 0
	form_container.scale = Vector2(0.9, 0.9)
	var form_tween = create_tween()
	form_tween.set_parallel(true)
	form_tween.tween_property(form_container, "modulate:a", 1.0, 0.5).set_delay(0.2)
	form_tween.tween_property(form_container, "scale", Vector2.ONE, 0.5).set_delay(0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _animate_state_transition():
	var tween = create_tween()
	tween.tween_property(form_container, "modulate:a", 0.0, 0.15)
	tween.tween_callback(_show_current_state)
	tween.tween_property(form_container, "modulate:a", 1.0, 0.15)

func _animate_error(error_label: Label, message: String):
	error_label.text = message
	error_label.visible = true
	error_label.modulate.a = 0

	var tween = create_tween()
	tween.tween_property(error_label, "modulate:a", 1.0, 0.2)

	# Shake animation
	var original_pos = form_container.position
	var shake_tween = create_tween()
	shake_tween.tween_property(form_container, "position:x", original_pos.x + 10, 0.05)
	shake_tween.tween_property(form_container, "position:x", original_pos.x - 10, 0.05)
	shake_tween.tween_property(form_container, "position:x", original_pos.x + 5, 0.05)
	shake_tween.tween_property(form_container, "position:x", original_pos.x, 0.05)

func _animate_success():
	var tween = create_tween()
	tween.tween_property(form_container, "scale", Vector2(1.05, 1.05), 0.1)
	tween.tween_property(form_container, "scale", Vector2.ONE, 0.1)

	# Flash the border green
	var style = form_container.get_theme_stylebox("panel") as StyleBoxFlat
	if style:
		var new_style = style.duplicate()
		new_style.border_color = Color(0.3, 1.0, 0.3, 0.8)
		form_container.add_theme_stylebox_override("panel", new_style)
		await get_tree().create_timer(0.3).timeout
		form_container.add_theme_stylebox_override("panel", style)

# ============================================
# STATE MANAGEMENT
# ============================================

func _show_current_state():
	access_key_container.visible = (current_state == AuthState.ACCESS_KEY)
	login_container.visible = (current_state == AuthState.LOGIN)
	register_container.visible = (current_state == AuthState.REGISTER)

	# Clear errors
	access_key_error.visible = false
	login_error.visible = false
	register_error.visible = false

func _switch_to_login():
	current_state = AuthState.LOGIN
	_animate_state_transition()

func _switch_to_register():
	current_state = AuthState.REGISTER
	_animate_state_transition()

func _set_loading(loading: bool, message: String = "Connecting..."):
	is_loading = loading

	var loading_box = get_node_or_null("CenterContainer/VBoxContainer/LoadingBox")
	if loading_box:
		loading_box.visible = loading
		loading_label.text = message

	# Disable/enable buttons
	access_key_button.disabled = loading
	login_button.disabled = loading
	register_button.disabled = loading

	if loading:
		access_key_button.text = "VALIDATING..."
		login_button.text = "SIGNING IN..."
		register_button.text = "CREATING..."
	else:
		access_key_button.text = "VALIDATE KEY"
		login_button.text = "SIGN IN"
		register_button.text = "CREATE ACCOUNT"

# ============================================
# EVENT HANDLERS
# ============================================

func _connect_signals():
	if backend:
		backend.access_key_validated.connect(_on_access_key_validated)
		backend.access_key_failed.connect(_on_access_key_failed)
		backend.logged_in.connect(_on_logged_in)
		backend.login_failed.connect(_on_login_failed)

func _on_access_key_submitted(_text: String):
	_on_access_key_submit()

func _on_access_key_submit():
	if is_loading:
		return

	var key = access_key_input.text.strip_edges()
	if key.length() < 8:
		_animate_error(access_key_error, "Access key must be at least 8 characters")
		return

	_set_loading(true, "Validating access key...")

	if backend:
		backend.validate_access_key(key)
	else:
		# Simulate for testing
		await get_tree().create_timer(1.0).timeout
		_on_access_key_validated()

func _on_access_key_validated():
	_set_loading(false)
	_animate_success()
	await get_tree().create_timer(0.3).timeout
	current_state = AuthState.LOGIN
	_animate_state_transition()

func _on_access_key_failed(error: String):
	_set_loading(false)
	_animate_error(access_key_error, error)

func _on_login_submitted(_text: String):
	_on_login_submit()

func _on_login_submit():
	if is_loading:
		return

	var username = login_username.text.strip_edges()
	var password = login_password.text

	if username.length() < 3:
		_animate_error(login_error, "Username must be at least 3 characters")
		return
	if password.length() < 6:
		_animate_error(login_error, "Password must be at least 6 characters")
		return

	_set_loading(true, "Signing in...")

	if backend:
		backend.login(username, password)
	else:
		# Simulate for testing
		await get_tree().create_timer(1.0).timeout
		_on_logged_in({"username": username, "level": 1})

func _on_register_submitted(_text: String):
	_on_register_submit()

func _on_register_submit():
	if is_loading:
		return

	var username = register_username.text.strip_edges()
	var email = register_email.text.strip_edges()
	var password = register_password.text
	var confirm = register_confirm.text

	if username.length() < 3:
		_animate_error(register_error, "Username must be at least 3 characters")
		return
	if not "@" in email:
		_animate_error(register_error, "Please enter a valid email")
		return
	if password.length() < 6:
		_animate_error(register_error, "Password must be at least 6 characters")
		return
	if password != confirm:
		_animate_error(register_error, "Passwords do not match")
		return

	_set_loading(true, "Creating account...")

	if backend:
		backend.register(username, email, password)
	else:
		# Simulate for testing
		await get_tree().create_timer(1.0).timeout
		_on_logged_in({"username": username, "level": 1})

func _on_logged_in(player_data: Dictionary):
	_set_loading(false)
	_animate_success()
	await get_tree().create_timer(0.5).timeout

	# Fade out
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	await tween.finished

	authentication_complete.emit(player_data)

func _on_login_failed(error: String):
	_set_loading(false)
	if current_state == AuthState.LOGIN:
		_animate_error(login_error, error)
	else:
		_animate_error(register_error, error)

func _exit_tree():
	# Disconnect signals
	if backend:
		if backend.access_key_validated.is_connected(_on_access_key_validated):
			backend.access_key_validated.disconnect(_on_access_key_validated)
		if backend.access_key_failed.is_connected(_on_access_key_failed):
			backend.access_key_failed.disconnect(_on_access_key_failed)
		if backend.logged_in.is_connected(_on_logged_in):
			backend.logged_in.disconnect(_on_logged_in)
		if backend.login_failed.is_connected(_on_login_failed):
			backend.login_failed.disconnect(_on_login_failed)
