extends Node
class_name ThreadScheduler

# Thread scheduler for distributing heavy operations across frames and threads
# Prevents frame hitches by spreading work over multiple frames
# Uses Godot's WorkerThreadPool for true parallel processing

signal task_completed(task_id: String, result: Variant)
signal task_failed(task_id: String, error: String)
signal batch_completed(batch_id: String)

enum TaskPriority {
	LOW = 0,
	NORMAL = 1,
	HIGH = 2,
	CRITICAL = 3
}

# Task queue for frame-distributed work
var task_queue: Array = []  # Array of TaskData
var running_tasks: Dictionary = {}  # task_id -> TaskData

# Frame budget settings
var max_frame_time_ms: float = 4.0  # Max time per frame for scheduled tasks
var min_tasks_per_frame: int = 1    # Always process at least this many

# Thread pool task IDs
var thread_tasks: Dictionary = {}  # internal_id -> task_id

# Deferred call queue (main thread callbacks)
var deferred_callbacks: Array = []
var deferred_mutex: Mutex = Mutex.new()

# Stats
var stats: Dictionary = {
	"tasks_queued": 0,
	"tasks_completed": 0,
	"tasks_failed": 0,
	"avg_task_time_ms": 0.0,
	"total_time_ms": 0.0
}

class TaskData:
	var id: String = ""
	var callable: Callable
	var args: Array = []
	var priority: int = TaskPriority.NORMAL
	var use_thread: bool = false
	var callback: Callable
	var batch_id: String = ""

# Batch processing
var batches: Dictionary = {}  # batch_id -> BatchData

class BatchData:
	var id: String = ""
	var total_tasks: int = 0
	var completed_tasks: int = 0
	var failed_tasks: int = 0
	var callback: Callable

func _ready():
	add_to_group("thread_scheduler")
	set_process(true)

func _process(_delta):
	# Process frame-distributed tasks
	_process_frame_tasks()

	# Process deferred callbacks (results from thread tasks)
	_process_deferred_callbacks()

func _process_frame_tasks():
	"""Process queued tasks within frame budget"""
	if task_queue.size() == 0:
		return

	var start_time = Time.get_ticks_usec()
	var tasks_processed = 0

	while task_queue.size() > 0:
		var elapsed_ms = (Time.get_ticks_usec() - start_time) / 1000.0

		# Check frame budget (but always do minimum)
		if tasks_processed >= min_tasks_per_frame and elapsed_ms >= max_frame_time_ms:
			break

		# Get highest priority task
		var task = _get_next_task()
		if not task:
			break

		# Execute task
		var task_start = Time.get_ticks_usec()
		_execute_task(task)
		var task_time = (Time.get_ticks_usec() - task_start) / 1000.0

		# Update stats
		stats.total_time_ms += task_time
		stats.tasks_completed += 1
		stats.avg_task_time_ms = stats.total_time_ms / stats.tasks_completed

		tasks_processed += 1

func _get_next_task() -> TaskData:
	"""Get the next task based on priority"""
	if task_queue.size() == 0:
		return null

	# Sort by priority (higher first)
	task_queue.sort_custom(func(a, b): return a.priority > b.priority)

	return task_queue.pop_front()

func _execute_task(task: TaskData):
	"""Execute a single task"""
	var result = null
	var error = ""

	try:
		if task.args.size() > 0:
			result = task.callable.callv(task.args)
		else:
			result = task.callable.call()
	except:
		error = "Task execution failed"
		stats.tasks_failed += 1

	# Handle callback
	if error == "":
		if task.callback.is_valid():
			task.callback.call(result)
		task_completed.emit(task.id, result)
	else:
		task_failed.emit(task.id, error)

	# Handle batch
	if task.batch_id != "":
		_update_batch(task.batch_id, error == "")

func _process_deferred_callbacks():
	"""Process callbacks that need to run on main thread"""
	deferred_mutex.lock()
	var callbacks = deferred_callbacks.duplicate()
	deferred_callbacks.clear()
	deferred_mutex.unlock()

	for cb in callbacks:
		if cb.callable.is_valid():
			cb.callable.callv(cb.args)

# ============================================
# TASK SCHEDULING API
# ============================================

func schedule_task(callable: Callable, args: Array = [], priority: int = TaskPriority.NORMAL, callback: Callable = Callable()) -> String:
	"""Schedule a task to run within frame budget"""
	var task = TaskData.new()
	task.id = _generate_task_id()
	task.callable = callable
	task.args = args
	task.priority = priority
	task.callback = callback
	task.use_thread = false

	task_queue.append(task)
	stats.tasks_queued += 1

	return task.id

func schedule_threaded(callable: Callable, args: Array = [], callback: Callable = Callable()) -> String:
	"""Schedule a task to run on worker thread pool"""
	var task_id = _generate_task_id()

	# Create wrapper that handles callback
	var wrapper = func():
		var result = null
		if args.size() > 0:
			result = callable.callv(args)
		else:
			result = callable.call()

		# Queue callback for main thread
		if callback.is_valid():
			_queue_deferred_callback(callback, [result])

		# Emit completion on main thread
		call_deferred("_on_thread_task_complete", task_id, result)

		return result

	var internal_id = WorkerThreadPool.add_task(wrapper)
	thread_tasks[internal_id] = task_id
	running_tasks[task_id] = {"type": "thread", "internal_id": internal_id}

	return task_id

func schedule_batch(tasks: Array, batch_callback: Callable = Callable(), priority: int = TaskPriority.NORMAL) -> String:
	"""Schedule multiple tasks as a batch"""
	var batch_id = _generate_task_id()

	var batch = BatchData.new()
	batch.id = batch_id
	batch.total_tasks = tasks.size()
	batch.callback = batch_callback
	batches[batch_id] = batch

	for task_data in tasks:
		var task = TaskData.new()
		task.id = _generate_task_id()
		task.callable = task_data.callable
		task.args = task_data.get("args", [])
		task.priority = priority
		task.callback = task_data.get("callback", Callable())
		task.batch_id = batch_id

		task_queue.append(task)
		stats.tasks_queued += 1

	return batch_id

func schedule_chunked(items: Array, process_func: Callable, chunk_size: int = 10, callback: Callable = Callable()) -> String:
	"""Process a large array in chunks across multiple frames"""
	var batch_id = _generate_task_id()
	var total_chunks = ceili(float(items.size()) / chunk_size)

	var batch = BatchData.new()
	batch.id = batch_id
	batch.total_tasks = total_chunks
	batch.callback = callback
	batches[batch_id] = batch

	for i in range(0, items.size(), chunk_size):
		var chunk = items.slice(i, min(i + chunk_size, items.size()))

		var task = TaskData.new()
		task.id = _generate_task_id()
		task.callable = process_func
		task.args = [chunk]
		task.priority = TaskPriority.LOW
		task.batch_id = batch_id

		task_queue.append(task)
		stats.tasks_queued += 1

	return batch_id

func schedule_delayed(callable: Callable, delay_frames: int, args: Array = []) -> String:
	"""Schedule a task to run after a delay (in frames)"""
	var task_id = _generate_task_id()

	var delayed_task = func():
		for i in range(delay_frames):
			await get_tree().process_frame
		if args.size() > 0:
			callable.callv(args)
		else:
			callable.call()

	delayed_task.call()

	return task_id

# ============================================
# BATCH MANAGEMENT
# ============================================

func _update_batch(batch_id: String, success: bool):
	"""Update batch progress"""
	if not batches.has(batch_id):
		return

	var batch = batches[batch_id]
	if success:
		batch.completed_tasks += 1
	else:
		batch.failed_tasks += 1

	# Check if batch is complete
	if batch.completed_tasks + batch.failed_tasks >= batch.total_tasks:
		if batch.callback.is_valid():
			batch.callback.call(batch.completed_tasks, batch.failed_tasks)
		batch_completed.emit(batch_id)
		batches.erase(batch_id)

func get_batch_progress(batch_id: String) -> Dictionary:
	"""Get progress of a batch"""
	if not batches.has(batch_id):
		return {"complete": true}

	var batch = batches[batch_id]
	return {
		"total": batch.total_tasks,
		"completed": batch.completed_tasks,
		"failed": batch.failed_tasks,
		"progress": float(batch.completed_tasks + batch.failed_tasks) / batch.total_tasks,
		"complete": false
	}

# ============================================
# INTERNAL
# ============================================

func _generate_task_id() -> String:
	return "task_%d_%d" % [Time.get_ticks_msec(), randi()]

func _queue_deferred_callback(callable: Callable, args: Array = []):
	"""Queue a callback to run on main thread"""
	deferred_mutex.lock()
	deferred_callbacks.append({"callable": callable, "args": args})
	deferred_mutex.unlock()

func _on_thread_task_complete(task_id: String, result: Variant):
	"""Handle thread task completion on main thread"""
	if running_tasks.has(task_id):
		running_tasks.erase(task_id)
	task_completed.emit(task_id, result)
	stats.tasks_completed += 1

# ============================================
# UTILITY
# ============================================

func cancel_task(task_id: String) -> bool:
	"""Cancel a pending task"""
	for i in range(task_queue.size()):
		if task_queue[i].id == task_id:
			task_queue.remove_at(i)
			return true
	return false

func cancel_batch(batch_id: String):
	"""Cancel all tasks in a batch"""
	var to_remove = []
	for i in range(task_queue.size()):
		if task_queue[i].batch_id == batch_id:
			to_remove.append(i)

	for i in range(to_remove.size() - 1, -1, -1):
		task_queue.remove_at(to_remove[i])

	batches.erase(batch_id)

func get_queue_size() -> int:
	"""Get number of pending tasks"""
	return task_queue.size()

func clear_queue():
	"""Clear all pending tasks"""
	task_queue.clear()
	batches.clear()

func get_stats() -> Dictionary:
	"""Get scheduler statistics"""
	return {
		"queue_size": task_queue.size(),
		"running_threads": running_tasks.size(),
		"active_batches": batches.size(),
		"tasks_queued": stats.tasks_queued,
		"tasks_completed": stats.tasks_completed,
		"tasks_failed": stats.tasks_failed,
		"avg_task_time_ms": stats.avg_task_time_ms
	}

func print_stats():
	"""Print scheduler stats to console"""
	var s = get_stats()
	print("=== Thread Scheduler Stats ===")
	print("Queue Size: %d" % s.queue_size)
	print("Running Threads: %d" % s.running_threads)
	print("Active Batches: %d" % s.active_batches)
	print("Tasks: %d queued, %d completed, %d failed" % [
		s.tasks_queued, s.tasks_completed, s.tasks_failed
	])
	print("Avg Task Time: %.3fms" % s.avg_task_time_ms)
