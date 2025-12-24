extends Node
# Note: Do not use class_name here - this script is an autoload singleton
# Access via: TradingSystem (the autoload name)

signal trade_requested(from_player: int, to_player: int)
signal trade_accepted(trade_id: int)
signal trade_declined(trade_id: int)
signal trade_completed(trade_id: int)
signal trade_cancelled(trade_id: int)
signal item_added_to_trade(trade_id: int, player_id: int, item: Resource)
signal item_removed_from_trade(trade_id: int, player_id: int, item: Resource)
signal player_ready_changed(trade_id: int, player_id: int, is_ready: bool)

class TradeSession:
	var id: int
	var player1_id: int
	var player2_id: int
	var player1_items: Array = []
	var player2_items: Array = []
	var player1_currency: int = 0
	var player2_currency: int = 0
	var player1_ready: bool = false
	var player2_ready: bool = false
	var created_at: float
	var status: String = "pending"  # pending, active, completed, cancelled

	func _init(p1: int, p2: int):
		player1_id = p1
		player2_id = p2
		created_at = Time.get_unix_time_from_system()

var active_trades: Dictionary = {}  # trade_id -> TradeSession
var pending_requests: Array = []  # Array of trade requests
var next_trade_id: int = 1

const TRADE_TIMEOUT: float = 300.0  # 5 minute timeout

func _ready():
	# Clean up old trades periodically
	var timer = Timer.new()
	timer.wait_time = 30.0
	timer.timeout.connect(_cleanup_expired_trades)
	timer.autostart = true
	add_child(timer)

func request_trade(from_player: int, to_player: int) -> int:
	# Check if either player is already in a trade
	for trade_id in active_trades:
		var trade = active_trades[trade_id]
		if trade.player1_id == from_player or trade.player2_id == from_player:
			print("Player %d is already in a trade" % from_player)
			return -1
		if trade.player1_id == to_player or trade.player2_id == to_player:
			print("Player %d is already in a trade" % to_player)
			return -1

	var trade = TradeSession.new(from_player, to_player)
	trade.id = next_trade_id
	next_trade_id += 1

	pending_requests.append(trade)
	trade_requested.emit(from_player, to_player)

	# Network replicate
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_request_trade_rpc.rpc(trade.id, from_player, to_player)

	return trade.id

@rpc("authority", "call_local", "reliable")
func _request_trade_rpc(trade_id: int, from_player: int, to_player: int):
	# Client-side handling of trade request
	if multiplayer.get_unique_id() == to_player:
		# Show trade request UI to target player
		print("Trade request from player %d" % from_player)

func accept_trade(trade_id: int) -> bool:
	for i in range(pending_requests.size()):
		if pending_requests[i].id == trade_id:
			var trade = pending_requests[i]
			trade.status = "active"
			active_trades[trade_id] = trade
			pending_requests.remove_at(i)
			trade_accepted.emit(trade_id)

			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				_accept_trade_rpc.rpc(trade_id)

			return true
	return false

@rpc("authority", "call_local", "reliable")
func _accept_trade_rpc(trade_id: int):
	trade_accepted.emit(trade_id)

func decline_trade(trade_id: int) -> bool:
	for i in range(pending_requests.size()):
		if pending_requests[i].id == trade_id:
			pending_requests.remove_at(i)
			trade_declined.emit(trade_id)

			if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
				_decline_trade_rpc.rpc(trade_id)

			return true
	return false

@rpc("authority", "call_local", "reliable")
func _decline_trade_rpc(trade_id: int):
	trade_declined.emit(trade_id)

func add_item_to_trade(trade_id: int, player_id: int, item: Resource) -> bool:
	if not active_trades.has(trade_id):
		return false

	var trade = active_trades[trade_id]

	# Reset ready status when items change
	trade.player1_ready = false
	trade.player2_ready = false

	if player_id == trade.player1_id:
		trade.player1_items.append(item)
	elif player_id == trade.player2_id:
		trade.player2_items.append(item)
	else:
		return false

	item_added_to_trade.emit(trade_id, player_id, item)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var trade = active_trades[trade_id]
		_sync_trade_items.rpc(trade_id, trade.player1_items.size(), trade.player2_items.size(),
			trade.player1_currency, trade.player2_currency)

	return true

func remove_item_from_trade(trade_id: int, player_id: int, item_index: int) -> bool:
	if not active_trades.has(trade_id):
		return false

	var trade = active_trades[trade_id]
	var item: Resource = null

	# Reset ready status when items change
	trade.player1_ready = false
	trade.player2_ready = false

	if player_id == trade.player1_id:
		if item_index < trade.player1_items.size():
			item = trade.player1_items[item_index]
			trade.player1_items.remove_at(item_index)
	elif player_id == trade.player2_id:
		if item_index < trade.player2_items.size():
			item = trade.player2_items[item_index]
			trade.player2_items.remove_at(item_index)
	else:
		return false

	if item:
		item_removed_from_trade.emit(trade_id, player_id, item)

		if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
			var trade_data = active_trades[trade_id]
			_sync_trade_items.rpc(trade_id, trade_data.player1_items.size(), trade_data.player2_items.size(),
				trade_data.player1_currency, trade_data.player2_currency)

		return true

	return false

func set_currency_offer(trade_id: int, player_id: int, amount: int) -> bool:
	if not active_trades.has(trade_id):
		return false

	var trade = active_trades[trade_id]

	# Reset ready status
	trade.player1_ready = false
	trade.player2_ready = false

	if player_id == trade.player1_id:
		trade.player1_currency = amount
	elif player_id == trade.player2_id:
		trade.player2_currency = amount
	else:
		return false

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		var trade_data = active_trades[trade_id]
		_sync_trade_items.rpc(trade_id, trade_data.player1_items.size(), trade_data.player2_items.size(),
			trade_data.player1_currency, trade_data.player2_currency)

	return true

func set_player_ready(trade_id: int, player_id: int, is_ready: bool) -> bool:
	if not active_trades.has(trade_id):
		return false

	var trade = active_trades[trade_id]

	if player_id == trade.player1_id:
		trade.player1_ready = is_ready
	elif player_id == trade.player2_id:
		trade.player2_ready = is_ready
	else:
		return false

	player_ready_changed.emit(trade_id, player_id, is_ready)

	# Check if both players are ready
	if trade.player1_ready and trade.player2_ready:
		_complete_trade(trade_id)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_sync_ready_status.rpc(trade_id, trade.player1_ready, trade.player2_ready)

	return true

@rpc("authority", "call_local", "reliable")
func _sync_trade_items(trade_id: int, p1_item_count: int, p2_item_count: int, p1_currency: int, p2_currency: int):
	# Sync trade state to clients
	if active_trades.has(trade_id):
		var trade = active_trades[trade_id]
		trade.player1_currency = p1_currency
		trade.player2_currency = p2_currency
		# Note: Item sync would require serialization - counts are synced for now
		print("Trade %d synced: P1=%d items, P2=%d items" % [trade_id, p1_item_count, p2_item_count])

@rpc("authority", "call_local", "reliable")
func _sync_ready_status(trade_id: int, p1_ready: bool, p2_ready: bool):
	if active_trades.has(trade_id):
		var trade = active_trades[trade_id]
		trade.player1_ready = p1_ready
		trade.player2_ready = p2_ready

func _complete_trade(trade_id: int):
	if not active_trades.has(trade_id):
		return

	var trade = active_trades[trade_id]

	# Transfer items
	# Player 1 receives Player 2's items
	# Player 2 receives Player 1's items

	# This would integrate with InventorySystem
	var inventory_system = get_node_or_null("/root/GameManager/InventorySystem")

	# Transfer currency
	var player_persistence = get_node_or_null("/root/PlayerPersistence")
	if player_persistence:
		# Deduct from player 1, add to player 2
		# Deduct from player 2, add to player 1
		pass

	trade.status = "completed"
	trade_completed.emit(trade_id)

	# Clean up
	active_trades.erase(trade_id)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_complete_trade_rpc.rpc(trade_id)

@rpc("authority", "call_local", "reliable")
func _complete_trade_rpc(trade_id: int):
	trade_completed.emit(trade_id)
	if active_trades.has(trade_id):
		active_trades.erase(trade_id)

func cancel_trade(trade_id: int, player_id: int) -> bool:
	if not active_trades.has(trade_id):
		return false

	var trade = active_trades[trade_id]

	# Verify player is in this trade
	if player_id != trade.player1_id and player_id != trade.player2_id:
		return false

	trade.status = "cancelled"
	trade_cancelled.emit(trade_id)
	active_trades.erase(trade_id)

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_cancel_trade_rpc.rpc(trade_id)

	return true

@rpc("authority", "call_local", "reliable")
func _cancel_trade_rpc(trade_id: int):
	trade_cancelled.emit(trade_id)
	if active_trades.has(trade_id):
		active_trades.erase(trade_id)

func get_trade(trade_id: int) -> TradeSession:
	return active_trades.get(trade_id)

func get_player_active_trade(player_id: int) -> TradeSession:
	for trade_id in active_trades:
		var trade = active_trades[trade_id]
		if trade.player1_id == player_id or trade.player2_id == player_id:
			return trade
	return null

func _cleanup_expired_trades():
	var current_time = Time.get_unix_time_from_system()
	var expired_trades = []

	for trade_id in active_trades:
		var trade = active_trades[trade_id]
		if current_time - trade.created_at > TRADE_TIMEOUT:
			expired_trades.append(trade_id)

	for trade_id in expired_trades:
		trade_cancelled.emit(trade_id)
		active_trades.erase(trade_id)

	# Clean up expired pending requests
	var expired_requests = []
	for i in range(pending_requests.size()):
		if current_time - pending_requests[i].created_at > 60.0:  # 1 minute for requests
			expired_requests.append(i)

	for i in range(expired_requests.size() - 1, -1, -1):
		pending_requests.remove_at(expired_requests[i])
