extends Node

# EventBus - Central signal hub for decoupled game event communication
# Use this instead of direct node-to-node signal connections for global events
# Note: These signals are intentionally emitted from external code, not within this class

# ============================================
# PLAYER EVENTS
# ============================================
@warning_ignore("unused_signal")
signal player_spawned(player: Node, peer_id: int)
@warning_ignore("unused_signal")
signal player_died(player: Node, peer_id: int, killer_id: int)
@warning_ignore("unused_signal")
signal player_respawned(player: Node, peer_id: int)
@warning_ignore("unused_signal")
signal player_damaged(player: Node, damage: float, source: Node)
@warning_ignore("unused_signal")
signal player_healed(player: Node, amount: float)
@warning_ignore("unused_signal")
signal player_score_changed(peer_id: int, new_score: int)

# ============================================
# WEAPON EVENTS
# ============================================
@warning_ignore("unused_signal")
signal weapon_fired(player: Node, weapon_name: String, position: Vector3, direction: Vector3)
@warning_ignore("unused_signal")
signal weapon_reloaded(player: Node, weapon_name: String)
@warning_ignore("unused_signal")
signal weapon_switched(player: Node, old_weapon: String, new_weapon: String)
@warning_ignore("unused_signal")
signal ammo_changed(player: Node, current: int, reserve: int)

# ============================================
# ZOMBIE EVENTS
# ============================================
@warning_ignore("unused_signal")
signal zombie_spawned(zombie: Node, zombie_type: String)
@warning_ignore("unused_signal")
signal zombie_died(zombie: Node, killer: Node, position: Vector3)
@warning_ignore("unused_signal")
signal zombie_damaged(zombie: Node, damage: float, source: Node)
@warning_ignore("unused_signal")
signal zombie_reached_target(zombie: Node, target: Node)

# ============================================
# WAVE EVENTS
# ============================================
@warning_ignore("unused_signal")
signal wave_started(wave_number: int)
@warning_ignore("unused_signal")
signal wave_completed(wave_number: int)
@warning_ignore("unused_signal")
signal wave_failed(wave_number: int)
@warning_ignore("unused_signal")
signal intermission_started(duration: float)
@warning_ignore("unused_signal")
signal all_waves_completed

# ============================================
# GAME STATE EVENTS
# ============================================
@warning_ignore("unused_signal")
signal game_started
@warning_ignore("unused_signal")
signal game_paused
@warning_ignore("unused_signal")
signal game_resumed
@warning_ignore("unused_signal")
signal game_over(victory: bool)
@warning_ignore("unused_signal")
signal match_found(lobby_id: int)
@warning_ignore("unused_signal")
signal loading_started
@warning_ignore("unused_signal")
signal loading_completed

# ============================================
# NETWORK EVENTS
# ============================================
@warning_ignore("unused_signal")
signal peer_connected(peer_id: int, player_info: Dictionary)
@warning_ignore("unused_signal")
signal peer_disconnected(peer_id: int)
@warning_ignore("unused_signal")
signal server_started
@warning_ignore("unused_signal")
signal server_stopped
@warning_ignore("unused_signal")
signal connected_to_server
@warning_ignore("unused_signal")
signal disconnected_from_server
@warning_ignore("unused_signal")
signal connection_failed

# ============================================
# ECONOMY EVENTS
# ============================================
@warning_ignore("unused_signal")
signal currency_changed(peer_id: int, new_amount: int)
@warning_ignore("unused_signal")
signal item_purchased(peer_id: int, item_id: String, cost: int)
@warning_ignore("unused_signal")
signal item_sold(peer_id: int, item_id: String, value: int)
@warning_ignore("unused_signal")
signal trade_started(trade_id: int, player1_id: int, player2_id: int)
@warning_ignore("unused_signal")
signal trade_completed(trade_id: int)
@warning_ignore("unused_signal")
signal trade_cancelled(trade_id: int)

# ============================================
# UI EVENTS
# ============================================
@warning_ignore("unused_signal")
signal notification_requested(message: String, type: String, duration: float)
@warning_ignore("unused_signal")
signal popup_requested(title: String, message: String, buttons: Array)
@warning_ignore("unused_signal")
signal popup_closed(result: int)
@warning_ignore("unused_signal")
signal menu_opened(menu_name: String)
@warning_ignore("unused_signal")
signal menu_closed(menu_name: String)

# ============================================
# PICKUP EVENTS
# ============================================
@warning_ignore("unused_signal")
signal pickup_collected(player: Node, pickup_type: String, amount: float)
@warning_ignore("unused_signal")
signal loot_dropped(position: Vector3, item_data: Resource)
@warning_ignore("unused_signal")
signal loot_collected(player: Node, item_data: Resource)

# ============================================
# AUDIO/VFX EVENTS
# ============================================
@warning_ignore("unused_signal")
signal vfx_requested(effect_type: String, position: Vector3, params: Dictionary)
@warning_ignore("unused_signal")
signal audio_requested(sound_name: String, position: Vector3, volume: float)

# ============================================
# HELPER METHODS
# ============================================

func emit_notification(message: String, type: String = "info", duration: float = 3.0):
	notification_requested.emit(message, type, duration)

func emit_player_kill(player: Node, peer_id: int, killer: Node, killer_id: int):
	"""Convenience method for player death events"""
	player_died.emit(player, peer_id, killer_id)
	if killer and killer_id > 0:
		# Award points for the kill
		var points_system = get_node_or_null("/root/PointsSystem")
		if points_system and points_system.has_method("add_points"):
			points_system.add_points(killer_id, 100, "player_kill")

func emit_wave_event(event_type: String, wave_number: int, _extra_data: Dictionary = {}):
	"""Convenience method for wave events"""
	match event_type:
		"started":
			wave_started.emit(wave_number)
		"completed":
			wave_completed.emit(wave_number)
		"failed":
			wave_failed.emit(wave_number)

func emit_network_event(event_type: String, _data: Dictionary = {}):
	"""Convenience method for network events"""
	match event_type:
		"connected":
			connected_to_server.emit()
		"disconnected":
			disconnected_from_server.emit()
		"failed":
			connection_failed.emit()
		"server_started":
			server_started.emit()
		"server_stopped":
			server_stopped.emit()

# ============================================
# UI BINDINGS
# ============================================

func bind_notification_manager(manager: Node):
	"""Bind notification manager to receive events"""
	if not manager:
		return
	if manager.has_method("show_notification"):
		notification_requested.connect(func(msg, type, dur): manager.show_notification(msg, type, dur))
	if manager.has_method("show_wave_notification"):
		wave_started.connect(func(wave): manager.show_wave_notification("Wave %d Started!" % wave))
		wave_completed.connect(func(wave): manager.show_wave_notification("Wave %d Complete!" % wave))

func bind_kill_feed(feed: Node):
	"""Bind kill feed UI to receive kill events"""
	if not feed:
		return
	if feed.has_method("add_kill"):
		player_died.connect(func(player, _peer_id, killer_id):
			var player_name = player.player_name if "player_name" in player else "Player"
			var killer_name = "Unknown"
			var players = get_tree().get_nodes_in_group("player")
			for p in players:
				if "peer_id" in p and p.peer_id == killer_id:
					killer_name = p.player_name if "player_name" in p else "Player"
					break
			feed.add_kill(killer_name, player_name, "")
		)
		zombie_died.connect(func(zombie, killer, _pos):
			if killer and killer.is_in_group("player"):
				var killer_name = killer.player_name if "player_name" in killer else "Player"
				var zombie_type = zombie.zombie_type if "zombie_type" in zombie else "Zombie"
				feed.add_kill(killer_name, zombie_type, "headshot" if zombie.get("was_headshot", false) else "")
		)

func bind_scoreboard(board: Node):
	"""Bind scoreboard to receive score events"""
	if not board:
		return
	if board.has_method("update_player_score"):
		player_score_changed.connect(func(peer_id, score): board.update_player_score(peer_id, score))
	if board.has_method("add_player"):
		player_spawned.connect(func(player, peer_id):
			var player_name = player.player_name if "player_name" in player else "Player"
			board.add_player(peer_id, player_name)
		)
	if board.has_method("remove_player"):
		player_died.connect(func(_player, peer_id, _killer_id): board.mark_player_dead(peer_id) if board.has_method("mark_player_dead") else null)

func bind_damage_numbers(manager: Node):
	"""Bind damage numbers manager to receive damage events"""
	if not manager:
		return
	if manager.has_method("spawn_damage_number"):
		zombie_damaged.connect(func(zombie, damage, _source):
			if is_instance_valid(zombie):
				manager.spawn_damage_number(zombie.global_position + Vector3.UP, damage, false)
		)
		player_damaged.connect(func(player, damage, _source):
			if is_instance_valid(player):
				manager.spawn_damage_number(player.global_position + Vector3.UP, damage, true)
		)
