extends Node
class_name BodyPartHealthAPI
## HTTP client for body part health API communication with backend server

# Signals
signal health_received(health_data: Dictionary)
signal health_updated(health_data: Dictionary)
signal healing_started(body_part: String)
signal healing_cancelled
signal request_failed(error: String)
signal connected_to_server
signal disconnected_from_server

# Configuration
@export var server_url: String = "http://localhost:5000"
@export var auto_sync_interval: float = 5.0  # Seconds between auto-sync

# HTTP Request nodes
var http_request: HTTPRequest
var pending_requests: Dictionary = {}
var auth_token: String = ""
var is_connected: bool = false

# Sync timer
var sync_timer: Timer

func _ready():
	# Create HTTP request node
	http_request = HTTPRequest.new()
	http_request.request_completed.connect(_on_request_completed)
	add_child(http_request)

	# Create sync timer
	sync_timer = Timer.new()
	sync_timer.wait_time = auto_sync_interval
	sync_timer.autostart = false
	sync_timer.timeout.connect(_on_sync_timer_timeout)
	add_child(sync_timer)

## Set the authentication token for API requests
func set_auth_token(token: String):
	auth_token = token
	if not token.is_empty():
		is_connected = true
		connected_to_server.emit()
		sync_timer.start()
	else:
		is_connected = false
		disconnected_from_server.emit()
		sync_timer.stop()

## Get current body part health from server
func get_health() -> void:
	_make_request("/api/BodyPartHealth", HTTPClient.METHOD_GET, {}, "get_health")

## Initialize body part health on server
func initialize_health() -> void:
	_make_request("/api/BodyPartHealth/initialize", HTTPClient.METHOD_POST, {}, "initialize_health")

## Apply damage to a specific body part
func damage_body_part(body_part: String, amount: float) -> void:
	var body = {
		"bodyPart": body_part,
		"amount": amount
	}
	_make_request("/api/BodyPartHealth/damage", HTTPClient.METHOD_POST, body, "damage_body_part")

## Heal a specific body part
func heal_body_part(body_part: String, amount: float) -> void:
	var body = {
		"bodyPart": body_part,
		"amount": amount
	}
	_make_request("/api/BodyPartHealth/heal", HTTPClient.METHOD_POST, body, "heal_body_part")

## Start healing a body part (with timer)
func start_healing(body_part: String) -> void:
	var body = {
		"bodyPart": body_part
	}
	_make_request("/api/BodyPartHealth/start-healing", HTTPClient.METHOD_POST, body, "start_healing")

## Cancel current healing action
func cancel_healing() -> void:
	_make_request("/api/BodyPartHealth/cancel-healing", HTTPClient.METHOD_POST, {}, "cancel_healing")

## Update healing progress
func update_healing_progress(progress: float) -> void:
	_make_request("/api/BodyPartHealth/healing-progress?progress=%s" % progress, HTTPClient.METHOD_POST, {}, "healing_progress")

## Fully heal all body parts
func full_heal() -> void:
	_make_request("/api/BodyPartHealth/full-heal", HTTPClient.METHOD_POST, {}, "full_heal")

## Sync current health state to server
func sync_health(current_hp_values: Dictionary, active_effects: Array = [], healing_state: Dictionary = {}) -> void:
	var body = {
		"currentHpValues": current_hp_values
	}

	if not active_effects.is_empty():
		body["activeEffects"] = active_effects

	if not healing_state.is_empty():
		body["healingState"] = healing_state

	_make_request("/api/BodyPartHealth/sync", HTTPClient.METHOD_POST, body, "sync_health")

## Apply level bonus to max HP
func apply_level_bonus(level: int) -> void:
	_make_request("/api/BodyPartHealth/apply-level-bonus/%d" % level, HTTPClient.METHOD_POST, {}, "apply_level_bonus")

## Get another player's body part health
func get_player_health(player_id: int) -> void:
	_make_request("/api/BodyPartHealth/player/%d" % player_id, HTTPClient.METHOD_GET, {}, "get_player_health")

# ============================================
# INTERNAL METHODS
# ============================================

func _make_request(endpoint: String, method: int, body: Dictionary, request_type: String) -> void:
	if auth_token.is_empty() and not endpoint.contains("player/"):
		request_failed.emit("Not authenticated")
		return

	var url = server_url + endpoint
	var headers = [
		"Content-Type: application/json"
	]

	if not auth_token.is_empty():
		headers.append("Authorization: Bearer " + auth_token)

	var body_string = ""
	if not body.is_empty():
		body_string = JSON.stringify(body)

	# Store request type for response handling
	pending_requests[http_request.get_instance_id()] = request_type

	var error = http_request.request(url, headers, method, body_string)
	if error != OK:
		request_failed.emit("HTTP request failed: " + str(error))
		pending_requests.erase(http_request.get_instance_id())

func _on_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	var request_type = pending_requests.get(http_request.get_instance_id(), "unknown")
	pending_requests.erase(http_request.get_instance_id())

	if result != HTTPRequest.RESULT_SUCCESS:
		request_failed.emit("Request failed with result: " + str(result))
		return

	if response_code < 200 or response_code >= 300:
		var error_body = body.get_string_from_utf8()
		request_failed.emit("Server error %d: %s" % [response_code, error_body])
		return

	# Parse response
	var json_string = body.get_string_from_utf8()
	if json_string.is_empty():
		# Success with no body (like cancel healing)
		match request_type:
			"cancel_healing":
				healing_cancelled.emit()
		return

	var json = JSON.new()
	var parse_result = json.parse(json_string)
	if parse_result != OK:
		request_failed.emit("Failed to parse JSON response")
		return

	var data = json.data

	# Handle response based on request type
	match request_type:
		"get_health", "initialize_health":
			var health_data = _parse_health_response(data)
			health_received.emit(health_data)

		"damage_body_part", "heal_body_part", "full_heal", "sync_health":
			if data.has("data"):
				var health_data = _parse_health_response(data.data)
				health_updated.emit(health_data)
			elif data.has("head"):  # Direct health object
				var health_data = _parse_health_response(data)
				health_updated.emit(health_data)

		"start_healing":
			if data.has("data"):
				var health_data = _parse_health_response(data.data)
				if health_data.has("healing_state") and health_data.healing_state.has("body_part"):
					healing_started.emit(health_data.healing_state.body_part)
				health_updated.emit(health_data)

		"cancel_healing":
			healing_cancelled.emit()

		"get_player_health":
			var health_data = _parse_health_response(data)
			health_received.emit(health_data)

func _parse_health_response(data: Dictionary) -> Dictionary:
	var result = {}

	# Parse body parts
	var body_parts = ["head", "chest", "thorax", "leftArm", "rightArm",
					  "leftHand", "rightHand", "leftLeg", "rightLeg",
					  "leftFoot", "rightFoot"]

	for part in body_parts:
		if data.has(part):
			var snake_case_part = _to_snake_case(part)
			result[snake_case_part] = {
				"current_hp": data[part].get("currentHp", 0.0),
				"max_hp": data[part].get("maxHp", 0.0),
				"percentage": data[part].get("percentage", 0.0),
				"is_blacked_out": data[part].get("isBlackedOut", false)
			}

	# Parse active effects
	if data.has("activeEffects"):
		result["active_effects"] = []
		for effect in data.activeEffects:
			result.active_effects.append({
				"type": effect.get("type", ""),
				"body_part": effect.get("bodyPart", ""),
				"remaining_time": effect.get("remainingTime", 0.0),
				"total_duration": effect.get("totalDuration", 0.0),
				"progress": effect.get("progress", 0.0)
			})

	# Parse healing state
	if data.has("healingState") and data.healingState != null:
		result["healing_state"] = {
			"is_healing": data.healingState.get("isHealing", false),
			"body_part": data.healingState.get("bodyPart", ""),
			"progress": data.healingState.get("progress", 0.0)
		}

	# Parse other fields
	result["blacked_out_parts"] = data.get("blackedOutParts", [])
	result["has_bleeding_debuff"] = data.get("hasBleedingDebuff", false)

	return result

func _to_snake_case(camel_case: String) -> String:
	var result = ""
	for i in range(camel_case.length()):
		var c = camel_case[i]
		if c == c.to_upper() and i > 0:
			result += "_"
		result += c.to_lower()
	return result

func _on_sync_timer_timeout() -> void:
	# Auto-sync is disabled by default to reduce server load
	# Enable by calling start_auto_sync()
	pass

## Start automatic health syncing
func start_auto_sync() -> void:
	sync_timer.start()

## Stop automatic health syncing
func stop_auto_sync() -> void:
	sync_timer.stop()

## Convert local body part health to sync format
static func health_to_sync_format(body_part_health: Node) -> Dictionary:
	if not body_part_health or not body_part_health.has_method("get_current_hp"):
		return {}

	var hp_values = {}
	var part_names = ["head", "chest", "thorax", "left_arm", "right_arm",
					  "left_hand", "right_hand", "left_leg", "right_leg",
					  "left_foot", "right_foot"]

	for part_name in part_names:
		# Convert to enum value
		var part_enum = body_part_health.BodyPart.get(part_name.to_upper().replace("_", ""))
		if part_enum != null:
			hp_values[part_name] = body_part_health.get_current_hp(part_enum)

	return hp_values
