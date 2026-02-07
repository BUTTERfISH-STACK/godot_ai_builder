@tool
extends Node

## Runtime Monitor for Godot AI Builder
## =====================================
## Monitors runtime execution and captures runtime errors and exceptions.

# Signal declarations
signal runtime_exception(exception: Dictionary)
signal runtime_warning(warning: Dictionary)
signal runtime_log(log: Dictionary)
signal scene_loaded(scene_path: String)
signal scene_unloaded(scene_path: String)

# Monitoring state
var _is_monitoring: bool = false
var _monitored_scene: String = ""
var _exception_handlers: Array = []
var _log_buffer: Array = []
const MAX_LOG_BUFFER: int = 1000


## Lifecycle
## ========

func _ready() -> void:
	"""
	Initialize the runtime monitor.
	"""
	print("[Runtime Monitor] Initialized")


func _process(_delta: float) -> void:
	"""
	Process runtime monitoring.
	"""
	if not _is_monitoring:
		return
	
	_monitor_runtime_state()


## Public Methods
## =============

func start_monitoring(scene_path: String = "") -> void:
	"""
	Starts runtime monitoring.
	
	Args:
		scene_path: Optional path to the scene being monitored
	"""
	_is_monitoring = true
	_monitored_scene = scene_path
	
	print("[Runtime Monitor] Started monitoring" + ("" if scene_path.is_empty() else " scene: %s" % scene_path))
	
	# Connect to scene signals if in editor
	if Engine.is_editor_hint():
		_connect_editor_signals()


func stop_monitoring() -> void:
	"""
	Stops runtime monitoring.
	"""
	_is_monitoring = false
	_monitored_scene = ""
	
	print("[Runtime Monitor] Stopped monitoring")
	
	# Disconnect from signals
	_disconnect_signals()


func is_active() -> bool:
	"""
	Returns whether monitoring is active.
	"""
	return _is_monitoring


func get_monitored_scene() -> String:
	"""
	Returns the path of the monitored scene.
	"""
	return _monitored_scene


func capture_exception(exception_data: Dictionary) -> Dictionary:
	"""
	Captures and processes an exception.
	
	Args:
		exception_data: Exception information
	
	Returns:
		Standardized exception dictionary
	"""
	var exception: Dictionary = _standardize_exception(exception_data)
	
	# Add stack trace
	_add_stack_trace(exception)
	
	# Log the exception
	_log_exception(exception)
	
	# Emit signal
	runtime_exception.emit(exception)
	
	return exception


func capture_warning(warning_data: Dictionary) -> Dictionary:
	"""
	Captures a runtime warning.
	
	Args:
		warning_data: Warning information
	
	Returns:
		Standardized warning dictionary
	"""
	var warning: Dictionary = {
		"type": "warning",
		"timestamp": Time.get_unix_time_from_system(),
		"message": "",
		"source": "",
		"line": 0
	}
	
	# Map fields
	var message: String = warning_data.get("message", warning_data.get("msg", ""))
	if not message.is_empty():
		warning["message"] = message
	
	warning["source"] = warning_data.get("source", warning_data.get("file", ""))
	warning["line"] = warning_data.get("line", warning_data.get("line_number", 0))
	
	runtime_warning.emit(warning)
	
	return warning


func log_message(level: String, message: String, data: Dictionary = {}) -> void:
	"""
	Logs a runtime message.
	
	Args:
		level: Log level (debug, info, warning, error)
		message: Log message
		data: Additional log data
	"""
	var log_entry: Dictionary = {
		"level": level,
		"message": message,
		"timestamp": Time.get_unix_time_from_system(),
		"data": data
	}
	
	_log_buffer.append(log_entry)
	
	# Trim buffer if too large
	if _log_buffer.size() > MAX_LOG_BUFFER:
		_log_buffer = _log_buffer.slice(-MAX_LOG_BUFFER)
	
	var log: Dictionary = {
		"level": level,
		"message": message,
		"timestamp": log_entry["timestamp"]
	}
	runtime_log.emit(log)


func get_log_buffer(filter: Dictionary = {}) -> Array:
	"""
	Returns the log buffer.
	
	Args:
		filter: Optional filters (level, since)
	
	Returns:
		Array of log entries
	"""
	var filtered: Array = _log_buffer.duplicate()
	
	if filter.has("level"):
		var level: String = filter["level"]
		filtered = filtered.filter(func(e): return e.get("level", "") == level)
	
	if filter.has("since"):
		var since: float = filter["since"]
		filtered = filtered.filter(func(e): return e.get("timestamp", 0.0) >= since)
	
	return filtered


func clear_log_buffer() -> void:
	"""
	Clears the log buffer.
	"""
	_log_buffer.clear()


## Internal Methods
## ==============

func _connect_editor_signals() -> void:
	"""
	Connects to Godot Editor signals for monitoring.
	"""
	var tree: SceneTree = get_tree()
	
	# Connect scene change signals
	if tree.has_signal("scene_changed"):
		tree.scene_changed.connect(_on_scene_changed)
	
	if tree.has_signal("scene_loaded"):
		tree.scene_loaded.connect(_on_scene_loaded)
	
	if tree.has_signal("scene_unloaded"):
		tree.scene_unloaded.connect(_on_scene_unloaded)


func _disconnect_signals() -> void:
	"""
	Disconnects from Godot Editor signals.
	"""
	var tree: SceneTree = get_tree()
	
	if tree.has_signal("scene_changed") and tree.is_connected("scene_changed", _on_scene_changed):
		tree.scene_changed.disconnect(_on_scene_changed)
	
	if tree.has_signal("scene_loaded") and tree.is_connected("scene_loaded", _on_scene_loaded):
		tree.scene_loaded.disconnect(_on_scene_loaded)
	
	if tree.has_signal("scene_unloaded") and tree.is_connected("scene_unloaded", _on_scene_unloaded):
		tree.scene_unloaded.disconnect(_on_scene_unloaded)


func _monitor_runtime_state() -> void:
	"""
	Monitors the current runtime state.
	"""
	# Check for hanging operations
	# Monitor frame time
	# Check for memory issues
	pass


func _standardize_exception(exception_data: Dictionary) -> Dictionary:
	"""
	Standardizes exception data.
	"""
	var exception: Dictionary = {
		"type": "exception",
		"timestamp": Time.get_unix_time_from_system(),
		"message": "",
		"name": "",
		"stack": "",
		"source": "",
		"line": 0,
		"handled": false
	}
	
	# Map fields
	exception["message"] = exception_data.get("message", exception_data.get("msg", ""))
	exception["name"] = exception_data.get("name", exception_data.get("exception", "Error"))
	exception["source"] = exception_data.get("source", exception_data.get("file", ""))
	exception["line"] = exception_data.get("line", exception_data.get("line_number", 0))
	exception["stack"] = exception_data.get("stack", exception_data.get("stack_trace", ""))
	
	return exception


func _add_stack_trace(exception: Dictionary) -> void:
	"""
	Adds stack trace to exception.
	"""
	if not exception.has("stack") or exception["stack"].is_empty():
		exception["stack"] = _capture_stack_trace()


func _capture_stack_trace() -> String:
	"""
	Captures the current stack trace.
	"""
	var stack: Array = []
	
	# Get stack frames
	var frames: Array = get_stack()
	if frames.is_empty():
		return ""
	
	for frame: Dictionary in frames:
		var frame_str: String = ""
		
		if frame.has("source"):
			frame_str += frame["source"]
		
		if frame.has("line"):
			frame_str += ":%d" % frame["line"]
		
		if frame.has("function"):
			frame_str += " in function '%s'" % frame["function"]
		
		elif frame.has("method"):
			frame_str += " in method '%s'" % frame["method"]
		
		stack.append(frame_str)
	
	return "\n".join(stack)


func _log_exception(exception: Dictionary) -> void:
	"""
	Logs an exception.
	"""
	print("[Runtime Monitor] Exception: %s" % exception.get("message", "Unknown"))
	if exception.has("stack") and not exception["stack"].is_empty():
		print("[Runtime Monitor] Stack trace:\n%s" % exception["stack"])


func _on_scene_changed(scene: Node) -> void:
	"""
	Handles scene changes.
	"""
	var scene_path: String = ""
	if scene != null and scene.has_method("get_scene_file_path"):
		scene_path = scene.get_scene_file_path()
	
	_monitored_scene = scene_path
	
	log_message("info", "Scene changed", {"scene_path": scene_path})


func _on_scene_loaded(scene: Node) -> void:
	"""
	Handles scene loaded.
	"""
	var scene_path: String = ""
	if scene != null:
		if scene.has_method("get_scene_file_path"):
			scene_path = scene.get_scene_file_path()
		elif scene.scene_file_path != null:
			scene_path = scene.scene_file_path
	
	scene_loaded.emit(scene_path)
	
	log_message("info", "Scene loaded", {"scene_path": scene_path})


func _on_scene_unloaded(scene: Node) -> void:
	"""
	Handles scene unloaded.
	"""
	var scene_path: String = ""
	if scene != null:
		if scene.has_method("get_scene_file_path"):
			scene_path = scene.get_scene_file_path()
		elif scene.scene_file_path != null:
			scene_path = scene.scene_file_path
	
	scene_unloaded.emit(scene_path)
	
	log_message("info", "Scene unloaded", {"scene_path": scene_path})


## Utility Methods
## ==============

func get_runtime_info() -> Dictionary:
	"""
	Returns current runtime information.
	"""
	var info: Dictionary = {
		"monitoring": _is_monitoring,
		"monitored_scene": _monitored_scene,
		"frame_count": Engine.get_frames_drawn(),
		"runtime": Engine.get_time_since_start(),
		"delta": Engine.get_physics_time_step()
	}
	
	# Get scene tree info
	var tree: SceneTree = get_tree()
	if tree != null:
		info["root_node"] = tree.get_root().get_name() if tree.get_root() else ""
		info["child_count"] = tree.get_root().get_child_count() if tree.get_root() else 0
	
	return info


func add_exception_handler(handler: Callable) -> int:
	"""
	Adds an exception handler.
	
	Args:
		handler: Callable to invoke on exception
	
	Returns:
		Handler ID
	"""
	var handler_id: int = _exception_handlers.size()
	_exception_handlers.append(handler)
	return handler_id


func remove_exception_handler(handler_id: int) -> void:
	"""
	Removes an exception handler.
	
	Args:
		handler_id: ID of handler to remove
	"""
	if handler_id >= 0 and handler_id < _exception_handlers.size():
		_exception_handlers.remove_at(handler_id)
