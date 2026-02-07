extends Object
class_name MarchingSquaresThreadPool

var max_threads: int = 4
var threads: Array = []
var job_queue: Array = []

var queue_mutex := Mutex.new()
var running := false

var _finished_count : int = 0
var _finish_mutex := Mutex.new()


func _init(p_max_threads := 4):
	max_threads = p_max_threads


func start():
	running = true
	for i in range(max_threads):
		var t := Thread.new()
		threads.append(t)
		t.start(_worker_loop)

func wait():
	for t in threads:
		if t.is_started():
			t.wait_to_finish()


## True when all workers finished. Call wait() after to join threads.
func is_done() -> bool:
	_finish_mutex.lock()
	var done := _finished_count >= threads.size()
	_finish_mutex.unlock()
	return done


func enqueue(job: Callable):
	if running:
		push_error("Can't enque on running pool")
		return
	queue_mutex.lock()
	job_queue.append(job)
	queue_mutex.unlock()


func _worker_loop():
	while running:
		queue_mutex.lock()
		if job_queue.size() == 0:
			running = false
			queue_mutex.unlock()
			break
		else:
			var job : Callable = job_queue.pop_front()
			queue_mutex.unlock()
			job.call()
	_finish_mutex.lock()
	_finished_count += 1
	_finish_mutex.unlock()
