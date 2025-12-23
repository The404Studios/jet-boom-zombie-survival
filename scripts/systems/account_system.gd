extends Node
class_name AccountSystem

signal account_loaded(account_data: Dictionary)
signal account_created(username: String)
signal steam_connected(steam_id: int, username: String)
signal login_failed(reason: String)

const SAVE_PATH = "user://account_data.save"

var account_data: Dictionary = {
	"username": "",
	"steam_id": 0,
	"created_at": 0,
	"last_login": 0,
	"playtime_seconds": 0,
	"rank": 1,
	"prestige": 0,
	"experience": 0,
	"currency": {
		"coins": 0,
		"premium": 0
	},
	"statistics": {
		"zombies_killed": 0,
		"waves_survived": 0,
		"games_played": 0,
		"deaths": 0,
		"headshots": 0,
		"damage_dealt": 0,
		"healing_done": 0
	},
	"unlocks": [],
	"settings": {
		"mouse_sensitivity": 0.003,
		"fov": 90,
		"master_volume": 1.0,
		"music_volume": 0.8,
		"sfx_volume": 1.0,
		"gore_enabled": true
	}
}

var is_logged_in: bool = false
var steam_manager: Node = null

func _ready():
	# Try to connect to Steam
	_try_steam_connection()

	# Load saved account data
	_load_account()

func _try_steam_connection():
	steam_manager = get_node_or_null("/root/SteamManager")

	if steam_manager and steam_manager.is_steam_running:
		account_data.steam_id = steam_manager.steam_id
		account_data.username = steam_manager.steam_username
		steam_connected.emit(steam_manager.steam_id, steam_manager.steam_username)
		print("Connected to Steam as: %s" % steam_manager.steam_username)
	else:
		print("Steam not available - using local account")

func _load_account():
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			var result = json.parse(file.get_as_text())
			file.close()

			if result == OK:
				var loaded_data = json.data
				# Merge loaded data with defaults
				for key in loaded_data:
					if account_data.has(key):
						account_data[key] = loaded_data[key]

				is_logged_in = true
				account_data.last_login = Time.get_unix_time_from_system()
				account_loaded.emit(account_data)
				print("Account loaded: %s" % account_data.username)
				return

	# No save file - check if we have Steam username
	if account_data.username.is_empty():
		if steam_manager and steam_manager.is_steam_running:
			account_data.username = steam_manager.steam_username
		else:
			# Will prompt for username
			account_data.username = ""

func create_account(username: String) -> bool:
	if username.length() < 3:
		login_failed.emit("Username must be at least 3 characters")
		return false

	if username.length() > 20:
		login_failed.emit("Username must be 20 characters or less")
		return false

	account_data.username = username
	account_data.created_at = Time.get_unix_time_from_system()
	account_data.last_login = account_data.created_at

	# Give starter currency
	account_data.currency.coins = 1000

	save_account()
	is_logged_in = true
	account_created.emit(username)
	print("Account created: %s" % username)
	return true

func save_account():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(account_data, "\t"))
		file.close()
		print("Account saved")

func get_username() -> String:
	return account_data.username

func get_rank() -> int:
	return account_data.rank

func get_prestige() -> int:
	return account_data.prestige

func get_currency(currency_type: String) -> int:
	return account_data.currency.get(currency_type, 0)

func add_currency(currency_type: String, amount: int):
	if account_data.currency.has(currency_type):
		account_data.currency[currency_type] += amount
		save_account()

func spend_currency(currency_type: String, amount: int) -> bool:
	if get_currency(currency_type) >= amount:
		account_data.currency[currency_type] -= amount
		save_account()
		return true
	return false

func add_experience(amount: int):
	account_data.experience += amount

	# Check for level up
	var exp_needed = get_experience_for_level(account_data.rank + 1)
	while account_data.experience >= exp_needed and account_data.rank < 100:
		account_data.experience -= exp_needed
		account_data.rank += 1
		exp_needed = get_experience_for_level(account_data.rank + 1)
		print("Level up! Now rank %d" % account_data.rank)

	save_account()

func get_experience_for_level(level: int) -> int:
	# Exponential scaling
	return int(100 * pow(1.2, level - 1))

func prestige() -> bool:
	if account_data.rank >= 100:
		account_data.rank = 1
		account_data.experience = 0
		account_data.prestige += 1
		save_account()
		return true
	return false

func update_statistic(stat_name: String, value: int):
	if account_data.statistics.has(stat_name):
		account_data.statistics[stat_name] += value

func get_statistic(stat_name: String) -> int:
	return account_data.statistics.get(stat_name, 0)

func add_playtime(seconds: float):
	account_data.playtime_seconds += int(seconds)

func get_playtime_formatted() -> String:
	var total_seconds = account_data.playtime_seconds
	var hours = total_seconds / 3600
	var minutes = (total_seconds % 3600) / 60
	return "%dh %dm" % [hours, minutes]

func unlock_item(item_id: String) -> bool:
	if item_id not in account_data.unlocks:
		account_data.unlocks.append(item_id)
		save_account()
		return true
	return false

func is_unlocked(item_id: String) -> bool:
	return item_id in account_data.unlocks

func update_setting(setting_name: String, value):
	if account_data.settings.has(setting_name):
		account_data.settings[setting_name] = value
		save_account()

func get_setting(setting_name: String):
	return account_data.settings.get(setting_name)

func needs_account_setup() -> bool:
	return account_data.username.is_empty()

func load_account():
	_load_account()
