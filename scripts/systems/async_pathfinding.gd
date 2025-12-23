extends Node

# Async pathfinding system using thread pool
# Handles pathfinding requests without blocking main thread

signal path_found(request_id: int, path: PackedVector3Array)
signal path_failed(request_id: int)

var thread_pool = null
var navigation_map: RID
var next_request_id: int = 0

func _ready():
	# Get thread pool
	if has_node("/root/ThreadPool"):
		thread_pool = get_node("/root/ThreadPool")

	# Get default navigation map
	navigation_map = get_world_3d().navigation_map

func request_path(start: Vector3, end: Vector3, callback: Callable = Callable()) -> int:
	if not thread_pool:
		push_error("Thread pool not available for async pathfinding")
		return -1

	var request_id = next_request_id
	next_request_id += 1

	# Create pathfinding task
	var task_callable = func():
		return _calculate_path(start, end)

	var result_callback = func(result):
		_on_path_calculated(request_id, result, callback)

	# Submit to thread pool
	thread_pool.submit_task(task_callable, result_callback, 1)

	return request_id

func _calculate_path(start: Vector3, end: Vector3) -> PackedVector3Array:
	# Use NavigationServer3D for pathfinding
	var path = NavigationServer3D.map_get_path(
		navigation_map,
		start,
		end,
		true
	)

	return path

func _on_path_calculated(request_id: int, path: PackedVector3Array, callback: Callable):
	if path.size() > 0:
		path_found.emit(request_id, path)

		if callback and callback.is_valid():
			callback.call(path)
	else:
		path_failed.emit(request_id)

		if callback and callback.is_valid():
			callback.call(PackedVector3Array())

# Batch pathfinding for multiple agents
func request_paths_batch(requests: Array, callback: Callable = Callable()) -> int:
	if not thread_pool:
		return -1

	var request_id = next_request_id
	next_request_id += 1

	var task_callable = func():
		return _calculate_paths_batch(requests)

	var result_callback = func(result):
		_on_paths_calculated_batch(request_id, result, callback)

	thread_pool.submit_task(task_callable, result_callback, 1)

	return request_id

func _calculate_paths_batch(requests: Array) -> Array:
	var results = []

	for req in requests:
		var start = req.get("start", Vector3.ZERO)
		var end = req.get("end", Vector3.ZERO)
		var path = _calculate_path(start, end)
		results.append(path)

	return results

func _on_paths_calculated_batch(request_id: int, paths: Array, callback: Callable):
	if callback and callback.is_valid():
		callback.call(paths)
