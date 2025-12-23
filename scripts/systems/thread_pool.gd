extends Node

# Thread pool for async operations
# Handles pathfinding, resource loading, and other heavy computations

class WorkerThread:
	var thread: Thread
	var is_busy: bool = false
	var current_task: Callable
	var task_id: int = 0

class Task:
	var id: int
	var callable: Callable
	var callback: Callable
	var priority: int = 0
	var result = null
	var is_complete: bool = false

const MAX_THREADS: int = 4
const MAX_TASKS_PER_FRAME: int = 10

var worker_threads: Array[WorkerThread] = []
var task_queue: Array[Task] = []
var completed_tasks: Array[Task] = []
var next_task_id: int = 0
var task_mutex: Mutex
var is_shutting_down: bool = false

func _ready():
	task_mutex = Mutex.new()
	_initialize_threads()

func _initialize_threads():
	# Create worker threads
	for i in MAX_THREADS:
		var worker = WorkerThread.new()
		worker.thread = Thread.new()
		worker_threads.append(worker)

	print("Thread pool initialized with %d threads" % MAX_THREADS)

func _process(_delta):
	# Process completed tasks
	_process_completed_tasks()

	# Assign tasks to idle threads
	_assign_tasks_to_threads()

func _process_completed_tasks():
	task_mutex.lock()

	var tasks_processed = 0
	var i = 0
	while i < completed_tasks.size() and tasks_processed < MAX_TASKS_PER_FRAME:
		var task = completed_tasks[i]

		if task.callback and task.callback.is_valid():
			task.callback.call(task.result)

		completed_tasks.remove_at(i)
		tasks_processed += 1

	task_mutex.unlock()

func _assign_tasks_to_threads():
	if task_queue.is_empty():
		return

	task_mutex.lock()

	# Sort tasks by priority
	task_queue.sort_custom(func(a, b): return a.priority > b.priority)

	# Find idle threads and assign tasks
	for worker in worker_threads:
		if task_queue.is_empty():
			break

		if not worker.is_busy:
			var task = task_queue.pop_front()
			_start_task_on_thread(worker, task)

	task_mutex.unlock()

func _start_task_on_thread(worker: WorkerThread, task: Task):
	worker.is_busy = true
	worker.current_task = task.callable
	worker.task_id = task.id

	# Start thread
	worker.thread.start(_thread_work.bind(worker, task))

func _thread_work(worker: WorkerThread, task: Task):
	# Execute task
	var result = null

	if task.callable and task.callable.is_valid():
		result = task.callable.call()

	# Store result
	task_mutex.lock()
	task.result = result
	task.is_complete = true
	completed_tasks.append(task)
	task_mutex.unlock()

	# Mark worker as idle
	call_deferred("_finish_thread_work", worker)

func _finish_thread_work(worker: WorkerThread):
	if worker.thread.is_alive():
		worker.thread.wait_to_finish()

	worker.is_busy = false
	worker.current_task = Callable()
	worker.task_id = 0

# Public API

func submit_task(callable: Callable, callback: Callable = Callable(), priority: int = 0) -> int:
	if is_shutting_down:
		return -1

	task_mutex.lock()

	var task = Task.new()
	task.id = next_task_id
	next_task_id += 1
	task.callable = callable
	task.callback = callback
	task.priority = priority

	task_queue.append(task)

	task_mutex.unlock()

	return task.id

func cancel_task(task_id: int) -> bool:
	task_mutex.lock()

	# Try to remove from queue
	for i in range(task_queue.size()):
		if task_queue[i].id == task_id:
			task_queue.remove_at(i)
			task_mutex.unlock()
			return true

	task_mutex.unlock()
	return false

func get_active_task_count() -> int:
	var count = 0
	for worker in worker_threads:
		if worker.is_busy:
			count += 1
	return count

func get_queued_task_count() -> int:
	task_mutex.lock()
	var count = task_queue.size()
	task_mutex.unlock()
	return count

func shutdown():
	is_shutting_down = true

	task_mutex.lock()
	task_queue.clear()
	task_mutex.unlock()

	# Wait for all threads to finish
	for worker in worker_threads:
		if worker.thread.is_alive():
			worker.thread.wait_to_finish()

	print("Thread pool shut down")

func _exit_tree():
	shutdown()
