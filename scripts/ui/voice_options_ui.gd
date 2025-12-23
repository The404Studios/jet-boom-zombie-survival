extends Control

# Voice chat options menu
# Allows players to configure voice chat settings

@onready var voice_enabled_check = $Panel/MarginContainer/VBoxContainer/VoiceEnabled/CheckButton
@onready var push_to_talk_check = $Panel/MarginContainer/VBoxContainer/PushToTalk/CheckButton
@onready var proximity_check = $Panel/MarginContainer/VBoxContainer/ProximityVoice/CheckButton
@onready var global_voice_check = $Panel/MarginContainer/VBoxContainer/GlobalVoice/CheckButton

@onready var master_volume_slider = $Panel/MarginContainer/VBoxContainer/MasterVolume/HSlider
@onready var master_volume_label = $Panel/MarginContainer/VBoxContainer/MasterVolume/ValueLabel

@onready var voice_volume_slider = $Panel/MarginContainer/VBoxContainer/VoiceVolume/HSlider
@onready var voice_volume_label = $Panel/MarginContainer/VBoxContainer/VoiceVolume/ValueLabel

@onready var mic_gain_slider = $Panel/MarginContainer/VBoxContainer/MicGain/HSlider
@ontml:parameter name="mic_gain_label = $Panel/MarginContainer/VBoxContainer/MicGain/ValueLabel

@onready var test_mic_button = $Panel/MarginContainer/VBoxContainer/TestMicrophone/Button
@onready var voice_indicator = $Panel/MarginContainer/VBoxContainer/VoiceIndicator/ProgressBar

@onready var close_button = $Panel/MarginContainer/VBoxContainer/Buttons/CloseButton
@onready var apply_button = $Panel/MarginContainer/VBoxContainer/Buttons/ApplyButton

var voice_system = null
var is_testing_mic: bool = false

func _ready():
	# Get voice chat system
	if has_node("/root/VoiceChatSystem"):
		voice_system = get_node("/root/VoiceChatSystem")
		voice_system.voice_settings_changed.connect(_on_voice_settings_changed)

	# Connect signals
	voice_enabled_check.toggled.connect(_on_voice_enabled_toggled)
	push_to_talk_check.toggled.connect(_on_push_to_talk_toggled)
	proximity_check.toggled.connect(_on_proximity_toggled)
	global_voice_check.toggled.connect(_on_global_voice_toggled)

	master_volume_slider.value_changed.connect(_on_master_volume_changed)
	voice_volume_slider.value_changed.connect(_on_voice_volume_changed)
	mic_gain_slider.value_changed.connect(_on_mic_gain_changed)

	test_mic_button.pressed.connect(_on_test_mic_pressed)
	close_button.pressed.connect(_on_close_pressed)
	apply_button.pressed.connect(_on_apply_pressed)

	# Load current settings
	_load_current_settings()

	# Hide by default
	visible = false

func _load_current_settings():
	if not voice_system:
		return

	voice_enabled_check.button_pressed = voice_system.is_voice_enabled
	push_to_talk_check.button_pressed = voice_system.is_push_to_talk
	proximity_check.button_pressed = voice_system.proximity_enabled
	global_voice_check.button_pressed = voice_system.global_voice_enabled

	master_volume_slider.value = voice_system.master_volume
	voice_volume_slider.value = voice_system.voice_volume
	mic_gain_slider.value = voice_system.microphone_gain

	_update_volume_labels()

func _update_volume_labels():
	master_volume_label.text = "%d%%" % int(master_volume_slider.value * 100)
	voice_volume_label.text = "%d%%" % int(voice_volume_slider.value * 100)
	mic_gain_label.text = "%d%%" % int(mic_gain_slider.value * 100)

func _on_voice_enabled_toggled(enabled: bool):
	if voice_system:
		voice_system.set_voice_enabled(enabled)

	# Enable/disable other controls
	push_to_talk_check.disabled = not enabled
	proximity_check.disabled = not enabled
	global_voice_check.disabled = not enabled
	voice_volume_slider.editable = enabled
	mic_gain_slider.editable = enabled
	test_mic_button.disabled = not enabled

func _on_push_to_talk_toggled(enabled: bool):
	if voice_system:
		voice_system.set_push_to_talk(enabled)

func _on_proximity_toggled(enabled: bool):
	if voice_system:
		voice_system.set_proximity_enabled(enabled)

	# If proximity is enabled, global voice should be disabled
	if enabled:
		global_voice_check.button_pressed = false

func _on_global_voice_toggled(enabled: bool):
	if voice_system:
		voice_system.set_global_voice_enabled(enabled)

	# If global voice is enabled, proximity should be disabled
	if enabled:
		proximity_check.button_pressed = false

func _on_master_volume_changed(value: float):
	if voice_system:
		voice_system.set_master_volume(value)
	_update_volume_labels()

func _on_voice_volume_changed(value: float):
	if voice_system:
		voice_system.set_voice_volume(value)
	_update_volume_labels()

func _on_mic_gain_changed(value: float):
	if voice_system:
		voice_system.set_microphone_gain(value)
	_update_volume_labels()

func _on_test_mic_pressed():
	if is_testing_mic:
		_stop_mic_test()
	else:
		_start_mic_test()

func _start_mic_test():
	if not voice_system:
		return

	is_testing_mic = true
	test_mic_button.text = "Stop Test"

	# Enable voice recording for testing
	voice_system.start_talking()

func _stop_mic_test():
	if not voice_system:
		return

	is_testing_mic = false
	test_mic_button.text = "Test Microphone"

	# Stop voice recording
	voice_system.stop_talking()

	# Reset indicator
	voice_indicator.value = 0

func _process(_delta):
	if is_testing_mic and voice_system:
		# Update voice activity indicator
		# This would need actual audio level from Steam
		# For now, show that testing is active
		voice_indicator.value = randf_range(0.3, 0.8) if voice_system.is_talking else 0

func _on_voice_settings_changed():
	_load_current_settings()

func _on_close_pressed():
	visible = false

func _on_apply_pressed():
	# Settings are applied in real-time, so just close
	visible = false

func show_options():
	visible = true
	_load_current_settings()

func _exit_tree():
	# Make sure to stop mic test when closing
	if is_testing_mic:
		_stop_mic_test()
