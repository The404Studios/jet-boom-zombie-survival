extends Node

# EventBus - Central signal hub for decoupled game event communication
# Use this instead of direct node-to-node signal connections for global events

# ============================================
# PLAYER EVENTS
# ============================================
signal player_spawned(player: Node, peer_id: int)
signal player_died(player: Node, peer_id: int, killer_id: int)
signal player_respawned(player: Node, peer_id: int)
signal player_damaged(player: Node, damage: float, source: Node)
signal player_healed(player: Node, amount: float)
signal player_score_changed(peer_id: int, new_score: int)

# ============================================
# WEAPON EVENTS
# ============================================
signal weapon_fired(player: Node, weapon_name: String, position: Vector3, direction: Vector3)
signal weapon_reloaded(player: Node, weapon_name: String)
signal weapon_switched(player: Node, old_weapon: String, new_weapon: String)
signal ammo_changed(player: Node, current: int, reserve: int)

# ============================================
# ZOMBIE EVENTS
# ============================================
signal zombie_spawned(zombie: Node, zombie_type: String)
signal zombie_died(zombie: Node, killer: Node, position: Vector3)
signal zombie_damaged(zombie: Node, damage: float, source: Node)
signal zombie_reached_target(zombie: Node, target: Node)

# ============================================
# WAVE EVENTS
# ============================================
signal wave_started(wave_number: int)
signal wave_completed(wave_number: int)
signal wave_failed(wave_number: int)
signal intermission_started(duration: float)
signal all_waves_completed

# ============================================
# GAME STATE EVENTS
# ============================================
signal game_started
signal game_paused
signal game_resumed
signal game_over(victory: bool)
signal match_found(lobby_id: int)
signal loading_started
signal loading_completed

# ============================================
# NETWORK EVENTS
# ============================================
signal peer_connected(peer_id: int, player_info: Dictionary)
signal peer_disconnected(peer_id: int)
signal server_started
signal server_stopped
signal connected_to_server
signal disconnected_from_server
signal connection_failed

# ============================================
# ECONOMY EVENTS
# ============================================
signal currency_changed(peer_id: int, new_amount: int)
signal item_purchased(peer_id: int, item_id: String, cost: int)
signal item_sold(peer_id: int, item_id: String, value: int)
signal trade_started(trade_id: int, player1_id: int, player2_id: int)
signal trade_completed(trade_id: int)
signal trade_cancelled(trade_id: int)

# ============================================
# UI EVENTS
# ============================================
signal notification_requested(message: String, type: String, duration: float)
signal popup_requested(title: String, message: String, buttons: Array)
signal popup_closed(result: int)
signal menu_opened(menu_name: String)
signal menu_closed(menu_name: String)

# ============================================
# PICKUP EVENTS
# ============================================
signal pickup_collected(player: Node, pickup_type: String, amount: float)
signal loot_dropped(position: Vector3, item_data: Resource)
signal loot_collected(player: Node, item_data: Resource)

# ============================================
# AUDIO/VFX EVENTS
# ============================================
signal vfx_requested(effect_type: String, position: Vector3, params: Dictionary)
signal audio_requested(sound_name: String, position: Vector3, volume: float)

# ============================================
# HELPER METHODS
# ============================================

func emit_notification(message: String, type: String = "info", duration: float = 3.0):
	notification_requested.emit(message, type, duration)

func emit_player_kill(player: Node, peer_id: int, killer: Node, killer_id: int):
	"""Convenience method for player death events"""
	player_died.emit(player, peer_id, killer_id)
	if killer:
		# Emit score change for killer
		pass

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
