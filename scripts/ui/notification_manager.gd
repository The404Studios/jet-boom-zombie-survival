extends CanvasLayer
class_name NotificationManager

# In-game notification and announcement system
# Displays wave announcements, achievements, pickups, etc.

signal notification_shown(text: String, type: int)
signal announcement_shown(title: String, subtitle: String)

enum NotificationType {
	INFO,
	SUCCESS,
	WARNING,
	ERROR,
	PICKUP,
	ACHIEVEMENT,
	WAVE,
	BOSS
}

# Containers
@onready var notification_container: VBoxContainer = $NotificationContainer
@onready var announcement_container: CenterContainer = $AnnouncementContainer

# Settings
@export var max_notifications: int = 5
@export var notification_duration: float = 3.0
@export var announcement_duration: float = 4.0
@export var notification_fade_time: float = 0.3

# Colors by type
var type_colors: Dictionary = {
	NotificationType.INFO: Color(0.8, 0.8, 0.8),
	NotificationType.SUCCESS: Color(0.3, 1, 0.3),
	NotificationType.WARNING: Color(1, 0.8, 0.3),
	NotificationType.ERROR: Color(1, 0.3, 0.3),
	NotificationType.PICKUP: Color(0.5, 0.8, 1),
	NotificationType.ACHIEVEMENT: Color(1, 0.8, 0),
	NotificationType.WAVE: Color(0.8, 0.6, 1),
	NotificationType.BOSS: Color(1, 0.2, 0.2)
}

# Icons by type (emoji fallback)
var type_icons: Dictionary = {
	NotificationType.INFO: "i",
	NotificationType.SUCCESS: "+",
	NotificationType.WARNING: "!",
	NotificationType.ERROR: "X",
	NotificationType.PICKUP: ">",
	NotificationType.ACHIEVEMENT: "*",
	NotificationType.WAVE: "~",
	NotificationType.BOSS: "!"
}

# Active notifications
var active_notifications: Array = []
var announcement_queue: Array = []
var is_showing_announcement: bool = false

func _ready():
	_setup_containers()

func _setup_containers():
	# Create notification container if not exists
	if not notification_container:
		notification_container = VBoxContainer.new()
		notification_container.name = "NotificationContainer"
		notification_container.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		notification_container.position = Vector2(-300, 10)
		notification_container.size = Vector2(280, 400)
		add_child(notification_container)

	# Create announcement container if not exists
	if not announcement_container:
		announcement_container = CenterContainer.new()
		announcement_container.name = "AnnouncementContainer"
		announcement_container.set_anchors_preset(Control.PRESET_CENTER_TOP)
		announcement_container.position = Vector2(0, 100)
		announcement_container.visible = false
		add_child(announcement_container)

# ============================================
# NOTIFICATIONS (Small, stacking)
# ============================================

func notify(text: String, type: NotificationType = NotificationType.INFO, duration: float = -1):
	"""Show a notification"""
	if duration < 0:
		duration = notification_duration

	var notification = _create_notification(text, type)
	notification_container.add_child(notification)
	active_notifications.append(notification)

	# Limit notifications
	while active_notifications.size() > max_notifications:
		var old = active_notifications.pop_front()
		if is_instance_valid(old):
			old.queue_free()

	# Animate in
	notification.modulate.a = 0
	notification.position.x = 50
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(notification, "modulate:a", 1.0, notification_fade_time)
	tween.tween_property(notification, "position:x", 0.0, notification_fade_time)

	# Schedule removal
	await get_tree().create_timer(duration).timeout

	if is_instance_valid(notification):
		_remove_notification(notification)

	notification_shown.emit(text, type)

func _create_notification(text: String, type: NotificationType) -> PanelContainer:
	var panel = PanelContainer.new()

	# Styling
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.15, 0.85)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.border_width_left = 3
	style.border_color = type_colors.get(type, Color.WHITE)
	panel.add_theme_stylebox_override("panel", style)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)

	var hbox = HBoxContainer.new()
	margin.add_child(hbox)

	# Icon
	var icon = Label.new()
	icon.text = "[%s]" % type_icons.get(type, "?")
	icon.modulate = type_colors.get(type, Color.WHITE)
	hbox.add_child(icon)

	# Text
	var label = Label.new()
	label.text = " " + text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(200, 0)
	hbox.add_child(label)

	return panel

func _remove_notification(notification: Node):
	if not is_instance_valid(notification):
		return

	var tween = create_tween()
	tween.tween_property(notification, "modulate:a", 0.0, notification_fade_time)
	tween.tween_callback(notification.queue_free)

	active_notifications.erase(notification)

# ============================================
# ANNOUNCEMENTS (Large, centered)
# ============================================

func announce(title: String, subtitle: String = "", duration: float = -1):
	"""Show a large centered announcement"""
	if duration < 0:
		duration = announcement_duration

	announcement_queue.append({
		"title": title,
		"subtitle": subtitle,
		"duration": duration
	})

	if not is_showing_announcement:
		_show_next_announcement()

func _show_next_announcement():
	if announcement_queue.is_empty():
		is_showing_announcement = false
		return

	is_showing_announcement = true
	var data = announcement_queue.pop_front()

	# Create announcement panel
	var panel = _create_announcement(data.title, data.subtitle)
	announcement_container.add_child(panel)
	announcement_container.visible = true

	# Animate in
	panel.scale = Vector2(0.5, 0.5)
	panel.modulate.a = 0

	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(panel, "scale", Vector2(1, 1), 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(panel, "modulate:a", 1.0, 0.2)

	announcement_shown.emit(data.title, data.subtitle)

	# Wait for duration
	await get_tree().create_timer(data.duration).timeout

	if not is_instance_valid(panel):
		_show_next_announcement()
		return

	# Animate out
	var out_tween = create_tween()
	out_tween.set_parallel(true)
	out_tween.tween_property(panel, "scale", Vector2(0.8, 0.8), 0.2)
	out_tween.tween_property(panel, "modulate:a", 0.0, 0.2)
	out_tween.chain().tween_callback(func():
		panel.queue_free()
		announcement_container.visible = false
		_show_next_announcement()
	)

func _create_announcement(title: String, subtitle: String) -> Control:
	var container = VBoxContainer.new()
	container.alignment = BoxContainer.ALIGNMENT_CENTER
	container.pivot_offset = container.size / 2

	# Title
	var title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", Color.WHITE)
	title_label.add_theme_color_override("font_outline_color", Color.BLACK)
	title_label.add_theme_constant_override("outline_size", 4)
	container.add_child(title_label)

	# Subtitle
	if not subtitle.is_empty():
		var sub_label = Label.new()
		sub_label.text = subtitle
		sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub_label.add_theme_font_size_override("font_size", 24)
		sub_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		sub_label.add_theme_color_override("font_outline_color", Color.BLACK)
		sub_label.add_theme_constant_override("outline_size", 2)
		container.add_child(sub_label)

	return container

# ============================================
# CONVENIENCE METHODS
# ============================================

func notify_pickup(item_name: String, amount: int = 1):
	"""Notify item pickup"""
	var text = item_name
	if amount > 1:
		text = "%s x%d" % [item_name, amount]
	notify(text, NotificationType.PICKUP)

func notify_achievement(achievement_name: String):
	"""Notify achievement unlocked"""
	notify("Achievement: " + achievement_name, NotificationType.ACHIEVEMENT, 5.0)

func notify_wave_start(wave_number: int):
	"""Announce wave start"""
	announce("WAVE %d" % wave_number, "Survive!", 3.0)

func notify_wave_complete(wave_number: int):
	"""Announce wave complete"""
	announce("WAVE %d COMPLETE" % wave_number, "Prepare for the next wave", 3.0)

func notify_boss_spawn(boss_name: String):
	"""Announce boss spawn"""
	announce("BOSS INCOMING", boss_name, 4.0)

func notify_player_joined(player_name: String):
	"""Notify player joined"""
	notify(player_name + " joined the game", NotificationType.INFO)

func notify_player_left(player_name: String):
	"""Notify player left"""
	notify(player_name + " left the game", NotificationType.WARNING)

func notify_player_died(player_name: String, killer_name: String = ""):
	"""Notify player death"""
	if killer_name.is_empty():
		notify(player_name + " died", NotificationType.ERROR)
	else:
		notify(player_name + " was killed by " + killer_name, NotificationType.ERROR)

func notify_game_over(victory: bool):
	"""Announce game over"""
	if victory:
		announce("VICTORY!", "You survived the zombie horde!", 5.0)
	else:
		announce("GAME OVER", "The zombies have won...", 5.0)

func notify_intermission(seconds: int):
	"""Notify intermission start"""
	notify("Intermission: %d seconds" % seconds, NotificationType.WAVE)

func clear_all():
	"""Clear all notifications and announcements"""
	for notification in active_notifications:
		if is_instance_valid(notification):
			notification.queue_free()
	active_notifications.clear()

	announcement_queue.clear()

	for child in announcement_container.get_children():
		child.queue_free()

	is_showing_announcement = false
