@tool
extends Node

## Error Handler for Godot AI Builder
## ===================================
## Captures and processes compile and runtime errors from the Godot Editor.
## Provides structured error information for the AI correction loop.

# Signal declarations
signal compile_error(error: Dictionary)
signal runtime_error(error: Dictionary)
signal error_resolved(error: Dictionary)
signal error_logged(error: Dictionary)

# Maximum error history size
const MAX_ERROR_HISTORY: int = 100

# Error categories
const ERROR_CATEGORIES: Dictionary = {
	"SYNTAX": "syntax",
	"SEMANTIC": "semantic",
	"TYPE": "type",
	"REFERENCE": "reference",
	"PERMISSION": "permission",
	"RESOURCE": "resource",
	"STACK_OVERFLOW": "stack_overflow",
	"NULL_POINTER": "null_pointer",
	"INDEX_OUT_OF_BOUNDS": "index_out_of_bounds",
	"INVALID_CAST": "invalid_cast",
	"MATH": "math"
}

# Internal state
var _error_history: Array[Dictionary] = []
var _current_error: Dictionary = {}
var _is_monitoring: bool = false


## Lifecycle
## ========

func _ready() -> void:
	"""
	Initialize the error handler.
	"""
	print("[Error Handler] Initialized")


## Public Methods
## =============

func capture_compile_error(error_data: Dictionary) -> Dictionary:
	"""
	Captures and processes a compile error.
	
	Args:
		error_data: Dictionary containing error information:
			- file: String - Path to the file
			- line: int - Line number
			- column: int - Column number
			- message: String - Error message
			- code: int - Error code
			- severity: String - Error severity
	
	Returns:
		Dictionary with standardized error format
	"""
	var standardized: Dictionary = _standardize_error(error_data, "compile")
	
	# Log to history
	_log_error(standardized)
	
	# Emit signal
	compile_error.emit(standardized)
	
	return standardized


func capture_runtime_error(error_data: Dictionary) -> Dictionary:
	"""
	Captures and processes a runtime error.
	
	Args:
		error_data: Dictionary containing error information:
			- message: String - Error message
			- stack: Array - Stack trace
			- node_path: String - Path to the node (if applicable)
			- scene_path: String - Path to the scene (if applicable)
			- time: float - Time of error
	
	Returns:
		Dictionary with standardized error format
	"""
	var standardized: Dictionary = _standardize_error(error_data, "runtime")
	
	# Extract additional context
	_add_runtime_context(standardized)
	
	# Log to history
	_log_error(standardized)
	
	# Emit signal
	runtime_error.emit(standardized)
	
	return standardized


func capture_script_error(error_data: Dictionary) -> Dictionary:
	"""
	Captures script execution errors.
	
	Args:
		error_data: Dictionary containing error information
	
	Returns:
		Dictionary with standardized error format
	"""
	var standardized: Dictionary = _standardize_error(error_data, "script")
	
	# Determine error type
	_categorize_error(standardized)
	
	# Log to history
	_log_error(standardized)
	
	return standardized


func get_error_history(filter: Dictionary = {}) -> Array:
	"""
	Returns the error history.
	
	Args:
		filter: Optional filters:
			- type: String - Filter by error type
			- since: float - Only errors after timestamp
			- limit: int - Maximum number of errors
	
	Returns:
		Array of error dictionaries
	"""
	var filtered: Array = _error_history.duplicate()
	
	# Apply type filter
	if filter.has("type"):
		var error_type: String = filter["type"]
		filtered = filtered.filter(func(e): return e.get("type", "") == error_type)
	
	# Apply timestamp filter
	if filter.has("since"):
		var since: float = filter["since"]
		filtered = filtered.filter(func(e): return e.get("timestamp", 0.0) >= since)
	
	# Apply limit
	if filter.has("limit"):
		var limit: int = filter["limit"]
		if limit < filtered.size():
			filtered = filtered.slice(0, limit)
	
	return filtered


func clear_error_history() -> void:
	"""
	Clears the error history.
	"""
	_error_history.clear()
	print("[Error Handler] Error history cleared")


func get_last_error() -> Dictionary:
	"""
	Returns the most recent error.
	"""
	if _error_history.is_empty():
		return {}
	return _error_history[-1]


func create_error_response(error: Dictionary) -> Dictionary:
	"""
	Creates a structured error response for the AI.
	
	Args:
		error: Error dictionary
	
	Returns:
		Response dictionary ready to send to AI
	"""
	var response: Dictionary = {
		"status": "error",
		"type": error.get("type", "unknown"),
		"category": error.get("category", "unknown"),
		"file": error.get("file", ""),
		"line": error.get("line", 0),
		"column": error.get("column", 0),
		"message": error.get("message", "Unknown error"),
		"stack": error.get("stack", ""),
		"suggestion": error.get("suggestion", ""),
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Add correction hints
	_add_correction_hints(response)
	
	return response


func create_success_response(data: Dictionary = {}) -> Dictionary:
	"""
	Creates a success response.
	
	Args:
		data: Additional success data
	
	Returns:
		Success response dictionary
	"""
	return {
		"status": "success"
	}.merge(data)


## Internal Methods
## ==============

func _standardize_error(error_data: Dictionary, error_type: String) -> Dictionary:
	"""
	Standardizes error data into a consistent format.
	
	Args:
		error_data: Raw error data
		error_type: Type of error (compile, runtime, script)
	
	Returns:
		Standardized error dictionary
	"""
	var standardized: Dictionary = {
		"type": error_type,
		"timestamp": Time.get_unix_time_from_system(),
		"file": "",
		"line": 0,
		"column": 0,
		"message": "",
		"stack": "",
		"code": 0,
		"severity": "error"
	}
	
	# Map common fields
	var field_mappings: Dictionary = {
		"message": ["message", "msg", "error_message"],
		"file": ["file", "path", "resource_path", "source_file"],
		"line": ["line", "line_number", "ln"],
		"column": ["column", "col", "column_number"],
		"stack": ["stack", "stack_trace", "stacktrace", "debug_trace"],
		"code": ["code", "error_code", "error_number"],
		"severity": ["severity", "level", "error_level"],
		"node_path": ["node_path", "node", "object_path"],
		"scene_path": ["scene_path", "scene", "scene_file"]
	}
	
	for target_field: String in field_mappings:
		var source_fields: Array = field_mappings[target_field]
		for source_field: String in source_fields:
			if error_data.has(source_field):
				standardized[target_field] = error_data[source_field]
				break
	
	# Add default message if not present
	if standardized["message"].is_empty():
		match error_type:
			"compile":
				standardized["message"] = "Compilation error"
			"runtime":
				standardized["message"] = "Runtime error"
			"script":
				standardized["message"] = "Script error"
			_:
				standardized["message"] = "Unknown error"
	
	return standardized


func _add_runtime_context(error: Dictionary) -> void:
	"""
	Adds runtime context to an error.
	"""
	# Get current scene info
	var scene_root: Node = get_tree().edited_scene_root
	if scene_root != null:
		if not error.has("scene_path"):
			error["scene_path"] = scene_root.scene_file_path
		
		if not error.has("node_path"):
			# Try to find the node that caused the error
			error["node_path"] = ""
	
	# Get call stack if available
	if Engine.has_main_loop():
		var main_loop: Node = Engine.get_main_loop()
		if main_loop != null:
			pass  # Additional context could be gathered here


func _categorize_error(error: Dictionary) -> void:
	"""
	Categorizes an error based on its message.
	"""
	var message: String = error.get("message", "").to_lower()
	
	var category: String = "unknown"
	
	# Check for specific error patterns
	if "null" in message and ("pointer" in message or "instance" in message or "access" in message):
		category = ERROR_CATEGORIES.NULL_POINTER
		error["suggestion"] = "Check if the object is initialized before use"
	elif "index" in message and ("out of" in message or "bounds" in message):
		category = ERROR_CATEGORIES.INDEX_OUT_OF_BOUNDS
		error["suggestion"] = "Ensure array bounds are checked before access"
	elif "invalid cast" in message or "cast" in message and "failed" in message:
		category = ERROR_CATEGORIES.INVALID_CAST
		error["suggestion"] = "Verify the object type before casting"
	elif "stack overflow" in message:
		category = ERROR_CATEGORIES.STACK_OVERFLOW
		error["suggestion"] = "Check for infinite recursion"
	elif "syntax" in message:
		category = ERROR_CATEGORIES.SYNTAX
		error["suggestion"] = "Review the script syntax"
	elif "type" in message and "mismatch" in message:
		category = ERROR_CATEGORIES.TYPE
		error["suggestion"] = "Ensure variable types are compatible"
	elif "reference" in message and ("null" in message or "not found" in message):
		category = ERROR_CATEGORIES.REFERENCE
		error["suggestion"] = "Check if the resource or node exists"
	elif "permission" in message or "access" in message:
		category = ERROR_CATEGORIES.PERMISSION
		error["suggestion"] = "Check file/resource permissions"
	elif "resource" in message and ("not found" in message or "load" in message):
		category = ERROR_CATEGORIES.RESOURCE
		error["suggestion"] = "Verify the resource path and ensure it exists"
	elif "division by zero" in message:
		category = ERROR_CATEGORIES.MATH
		error["suggestion"] = "Add a check for zero before division"
	
	error["category"] = category


func _log_error(error: Dictionary) -> void:
	"""
	Logs an error to the history.
	"""
	_error_history.append(error)
	
	# Trim history if too large
	if _error_history.size() > MAX_ERROR_HISTORY:
		_error_history = _error_history.slice(-MAX_ERROR_HISTORY)
	
	error_logged.emit(error)
	
	print("[Error Handler] Error logged: %s at %s:%d" % [
		error.get("message", "Unknown"),
		error.get("file", "unknown"),
		error.get("line", 0)
	])


func _add_correction_hints(response: Dictionary) -> void:
	"""
	Adds hints for correcting errors.
	"""
	var error_type: String = response.get("type", "")
	var message: String = response.get("message", "").to_lower()
	
	var hints: Array = []
	
	match error_type:
		"compile":
			hints = _get_compile_error_hints(message)
		"runtime":
			hints = _get_runtime_error_hints(message)
		"script":
			hints = _get_script_error_hints(message)
	
	if hints.size() > 0:
		response["correction_hints"] = hints


func _get_compile_error_hints(message: String) -> Array:
	"""
	Returns hints errors.
	"""
	var hints: Array for compile = []
	
	if "unexpected token" in message:
		hints.append("Check for missing or extra punctuation")
		hints.append("Verify all brackets and parentheses are balanced")
	elif "expected" in message:
		hints.append("Review the expected syntax in Godot documentation")
		hints.append("Check for typos in keywords")
	elif "unresolved identifier" in message:
		hints.append("Verify the variable or function is defined")
		hints.append("Check for scope issues")
		hints.append("Ensure scripts are properly loaded")
	elif "function" in message and "not found" in message:
		hints.append("Verify the function exists in the class")
		hints.append("Check for typos in function name")
		hints.append("Ensure base class methods are accessible")
	elif "class" in message and "not found" in message:
		hints.append("Verify the class name is correct")
		hints.append("Check if the script file exists")
		hints.append("Ensure the script is properly named")
	
	return hints


func _get_runtime_error_hints(message: String) -> Array:
	"""
	Returns hints for runtime errors.
	"""
	var hints: Array = []
	
	if "null" in message:
		hints.append("Check if nodes are properly initialized in _ready()")
		hints.append("Use @onready annotations for node references")
		hints.append("Verify scenes are loaded before accessing their nodes")
	elif "index" in message and "out of" in message:
		hints.append("Add bounds checking before accessing arrays")
		hints.append("Use array.size() to check valid indices")
	elif "division by zero" in message:
		hints.append("Add a check for zero before division")
		hints.append("Use if divisor != 0: before dividing"
	else:
		hints.append("Review the call stack to identify the source")
		hints.append("Add debug prints to trace the error")
	
	return hints


func _get_script_error_hints(message: String) -> Array:
	"""
	Returns hints for script errors.
	"""
	var hints: Array = []
	
	if "signal" in message:
		hints.append("Verify signal connection syntax")
		hints.append("Check if the signal exists in the emitting class")
	elif "export" in message:
		hints.append("Check @export annotation syntax")
		hints.append("Verify exported variable types")
	elif "typed" in message:
		hints.append("Review variable type declarations")
		hints.append("Ensure type annotations are valid Godot types")
	
	return hints


## Error Recovery
## ============

func mark_error_resolved(error: Dictionary) -> void:
	"""
	Marks an error as resolved.
	"""
	error["resolved"] = true
	error["resolved_at"] = Time.get_unix_time_from_system()
	
	error_resolved.emit(error)
	
	print("[Error Handler] Error resolved: %s" % error.get("message", "Unknown"))


func get_error_statistics() -> Dictionary:
	"""
	Returns error statistics.
	"""
	var stats: Dictionary = {
		"total_errors": _error_history.size(),
		"by_type": {},
		"by_category": {},
		"recent_count": 0
	}
	
	var recent_threshold: float = Time.get_unix_time_from_system() - 300  # Last 5 minutes
	
	for error: Dictionary in _error_history:
		var error_type: String = error.get("type", "unknown")
		var category: String = error.get("category", "unknown")
		
		# Count by type
		if not stats["by_type"].has(error_type):
			stats["by_type"][error_type] = 0
		stats["by_type"][error_type] += 1
		
		# Count by category
		if not stats["by_category"].has(category):
			stats["by_category"][category] = 0
		stats["by_category"][category] += 1
		
		# Count recent errors
		if error.get("timestamp", 0) > recent_threshold:
			stats["recent_count"] += 1
	
	return stats
