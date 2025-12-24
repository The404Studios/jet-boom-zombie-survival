extends Node

# Async resource loader using thread pool
# Handles loading resources without freezing the game

signal resource_loaded(resource_path: String, resource: Resource)
signal resource_load_failed(resource_path: String)

var thread_pool = null
var loading_resources: Dictionary = {} # path -> bool

func _ready():
	# Get thread pool
	if has_node("/root/ThreadPool"):
		thread_pool = get_node("/root/ThreadPool")

func load_resource_async(resource_path: String, callback: Callable = Callable()) -> void:
	if loading_resources.has(resource_path):
		print("Resource already loading: %s" % resource_path)
		return

	# Check if already loaded
	if ResourceLoader.has_cached(resource_path):
		var resource = ResourceLoader.load(resource_path)
		if callback and callback.is_valid():
			callback.call(resource)
		resource_loaded.emit(resource_path, resource)
		return

	# Mark as loading
	loading_resources[resource_path] = true

	# Create loading task
	var task_callable = func():
		return _load_resource_threaded(resource_path)

	var result_callback = func(result):
		_on_resource_loaded(resource_path, result, callback)

	if thread_pool:
		thread_pool.submit_task(task_callable, result_callback, 0)
	else:
		# Fallback to direct loading
		var resource = ResourceLoader.load(resource_path)
		_on_resource_loaded(resource_path, resource, callback)

func _load_resource_threaded(resource_path: String) -> Resource:
	# Load resource on worker thread
	var resource = ResourceLoader.load(resource_path, "", ResourceLoader.CACHE_MODE_REUSE)
	return resource

func _on_resource_loaded(resource_path: String, resource: Resource, callback: Callable):
	loading_resources.erase(resource_path)

	if resource:
		resource_loaded.emit(resource_path, resource)

		if callback and callback.is_valid():
			callback.call(resource)
	else:
		push_error("Failed to load resource: %s" % resource_path)
		resource_load_failed.emit(resource_path)

		if callback and callback.is_valid():
			callback.call(null)

func load_resources_batch(resource_paths: Array, callback: Callable = Callable()) -> void:
	var resources = {}
	# Use a dictionary to hold count - lambdas capture references to objects, not primitives
	var state = {"pending": resource_paths.size()}

	if state.pending == 0:
		if callback and callback.is_valid():
			callback.call(resources)
		return

	for path in resource_paths:
		load_resource_async(path, func(resource):
			resources[path] = resource
			state.pending -= 1

			if state.pending == 0:
				if callback and callback.is_valid():
					callback.call(resources)
		)

func is_loading(resource_path: String) -> bool:
	return loading_resources.has(resource_path)

func cancel_loading(resource_path: String):
	loading_resources.erase(resource_path)

# Preload common resources
func preload_common_resources():
	var common_resources = [
		"res://resources/weapons/pistol.tres",
		"res://resources/weapons/ak47.tres",
		"res://resources/zombies/shambler.tres",
		"res://resources/zombies/runner.tres"
	]

	load_resources_batch(common_resources, func(_resources):
		print("Common resources preloaded")
	)
