@tool
extends Node

## Auto Runner for Godot AI Builder
## =================================
## Automatically runs scenes after modifications.

# Signal declarations
signal scene_ready(data: Dictionary)
signal execution_failed(error: Dictionary)
signal execution_started(scene_path: String)
signal execution_completed(scene_path: String, result: Dictionary)

# Execution state
var _is_running: bool = false
var _current_scene: String = ""
var _execution_start_time: float = 0.0
var _execution_timeout: float = 300.0  # 5 minutes default timeout

# Queue management
var _run_queue: Array = []
var _processing_queue: bool = false


## Lifecycle
## ========

func _ready() -> void:
	"""
	Initialize the auto runner.
	"""
	print("[Auto Runner] Initialized")


## Public Methods
## =============

func run_scene(command: Dictionary) -> Dictionary:
	"""
	Executes a scene.
	
	Args:
		command: Dictionary containing:
			- scene_path: String (required) - Path to scene
			- wait_for_completion: bool (optional) - Wait for execution
			- timeout: float (optional) - Execution timeout
	
	Returns:
		Dictionary with execution result
	"""
	var result: Dictionary = {
		"status": "error",
		"error": "",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	var scene_path: String = command.get("scene_path", "")
	var wait_for_completion: bool = command.get("wait_for_completion", false)
	var timeout: float = command.get("timeout", _execution_timeout)
	
	if scene_path.is_empty():
		result["error"] = "Scene path is required"
		execution_failed.emit(result)
		return result
	
	# Validate scene exists
	if not FileAccess.file_exists(scene_path):
		result["error"] = "Scene not found: %s" % scene_path
		execution_failed.emit(result)
		return result
	
	# Load the scene
	var scene: PackedScene = load(scene_path)
	if scene == null:
		result["error"] = "Failed to load scene: %s" % scene_path
		execution_failed.emit(result)
		return result
	
	_current_scene = scene_path
	_execution_start_time = Time.get_unix_time_from_system()
	
	execution_started.emit(scene_path)
	
	# Change to the scene
	var tree: SceneTree = get_tree()
	if tree == null:
		result["error"] = "SceneTree not available"
		execution_failed.emit(result)
		return result
	
	var error: Error = tree.change_scene_to_packed(scene)
	if error != OK:
		result["error"] = "Failed to change scene: %d" % error
		execution_failed.emit(result)
		return result
	
	_is_running = true
	
	print("[Auto Runner] Running scene: %s" % scene_path)
	
	# Wait for scene to be ready
	await _wait_for_scene_ready(timeout)
	
	if _is_running:
		result["status"] = "success"
		result["scene_path"] = scene_path
		result["execution_time"] = Time.get_unix_time_from_system() - _execution_start_time
		
		execution_completed.emit(scene_path, result)
		
		var data: Dictionary = {
			"scene_path": scene_path,
			"execution_time": result["execution_time"]
		}
		scene_ready.emit(data)
	
	return result


func queue_auto_run(command: Dictionary) -> void:
	"""
	Queues a scene to run after current operations.
	
	Args:
		command: Run command
	"""
	_run_queue.append(command)
	
	if not _processing_queue:
		_process_run_queue()


func stop_execution() -> void:
	"""
	Stops the current execution.
	"""
	if _is_running:
		_is_running = false
		
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.current_scene = null
		
		print("[Auto Runner] Execution stopped")


func get_status() -> Dictionary:
	"""
	Returns current execution status.
	"""
	var status: Dictionary = {
		"running": _is_running,
		"scene": _current_scene,
		"execution_time": 0.0,
		"queue_size": _run_queue.size()
	}
	
	if _is_running:
		status["execution_time"] = Time.get_unix_time_from_system() - _execution_start_time
	
	return status


## Internal Methods
## ==============

func _wait_for_scene_ready(timeout: float) -> void:
	"""
	Waits for the scene to be ready or timeout.
	
	Args:
		timeout: Maximum time to wait in seconds
	"""
	var start_time: float = Time.get_unix_time_from_system()
	var tree: SceneTree = get_tree()
	
	while _is_running and (Time.get_unix_time_from_system() - start_time) < timeout:
		if tree != null and tree.current_scene != null:
			# Check if scene is fully loaded
			var root: Node = tree.current_scene
			if root != null:
				# Scene is ready when root is in tree
				if root.is_inside_tree():
					return
		
		await get_tree().process_frame
	
	if _is_running:
		print("[Auto Runner] Timeout waiting for scene ready")


func _process_run_queue() -> void:
	"""
	Processes the run queue.
	"""
	_processing_queue = true
	
	while not _run_queue.is_empty():
		var command: Dictionary = _run_queue.pop_front()
		
		var result: Dictionary = run_scene(command)
		
		if result.get("status") != "success":
			execution_failed.emit(result)
			break
		
		# Wait between runs
		await get_tree().create_timer(0.5).timeout
	
	_processing_queue = false


## Utility Methods
## ==============

func set_timeout(timeout: float) -> void:
	"""
	Sets the execution timeout.
	
	Args:
		timeout: Timeout in seconds
	"""
	_execution_timeout = max(1.0, timeout)
	print("[Auto Runner] Timeout set to %d seconds" % _execution_timeout)


func clear_queue() -> void:
	"""
	Clears the run queue.
	"""
	_run_queue.clear()
	print("[Auto Runner] Queue cleared")
