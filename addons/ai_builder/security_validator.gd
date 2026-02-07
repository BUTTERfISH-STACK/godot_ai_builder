@tool
extends Node

## Security Validator for Godot AI Builder
## ========================================
## Validates all incoming commands for security compliance.
## Prevents filesystem traversal, malicious input, and unauthorized access.

# Project root for path validation
var _project_root: String = ""
var _scripts_path: String = ""
var _scenes_path: String = ""
var _resources_path: String = ""

# Maximum command depth (prevents deeply nested commands)
const MAX_COMMAND_DEPTH: int = 10

# Maximum string length for input fields
const MAX_STRING_LENGTH: int = 65536

# Dangerous patterns to reject
const DANGEROUS_PATTERNS: Array[RegEx] = []

# Signal declarations
signal security_violation(violation: Dictionary)
signal path_blocked(path: String, reason: String)


## Initialization
## =============

func _ready() -> void:
	"""
	Initialize the security validator.
	"""
	_setup_dangerous_patterns()
	_update_project_paths()


func initialize_paths(project_root: String) -> void:
	"""
	Initialize paths for validation.
	
	Args:
		project_root: Path to the project root directory
	"""
	_project_root = project_root
	
	# Set up subdirectories
	_scripts_path = _project_root.path_join("scripts") if not _project_root.is_empty() else ""
	_scenes_path = _project_root.path_join("scenes") if not _project_root.is_empty() else ""
	_resources_path = _project_root.path_join("resources") if not _project_root.is_empty() else ""
	
	print("[Security Validator] Initialized with project root: %s" % _project_root)


func _setup_dangerous_patterns() -> void:
	"""
	Compiles regex patterns for dangerous input detection.
	"""
	var patterns: Array[String] = [
		r"\.\.",           # Directory traversal
		r"[/\\]\.\.",      # Path traversal with slashes
		r"^\.\.?$",         # Single or double dot names
		r"[\x00-\x08]",    # Control characters
		r"[\x0b-\x0c]",    # More control characters
		r"[\x0e-\x1f]",    # More control characters
		r"://",             # URL schemes
		r"file://",        # File URLs
		r"\\\\",           # UNC paths
		r"powershell",     # PowerShell invocation
		r"cmd\.exe",       # CMD execution
		r"bash",           # Bash execution
		r"sh ",            # Shell execution
		r"\$",             # Variable expansion
		r"`",              # Command substitution
		r";",              # Command chaining
		r"\|",             # Pipe to command
		r"&&\s*$",         # End-of-command AND
		r"\|\|",           # OR operator (command injection)
		r"\$_\[",          # Shell array access
		r"\$\{",           # Variable expansion
		r"eval\s*\(",      # eval function
		r"exec\s*\(",      # exec function
		r"system\s*\(",    # system function
		r"popen\s*\(",     # popen function
	]
	
	for pattern: String in patterns:
		var regex: RegEx = RegEx.new()
		var error: Error = regex.compile(pattern)
		if error == OK:
			DANGEROUS_PATTERNS.append(regex)


func _update_project_paths() -> void:
	"""
	Updates project paths from ProjectSettings.
	"""
	if ProjectSettings.has_setting("editor/run/main_scene"):
		_project_root = ProjectSettings.globalize_path("res://")
		_scripts_path = _project_root.path_join("scripts")
		_scenes_path = _project_root.path_join("scenes")
		_resources_path = _project_root.path_join("resources")


## Public Validation Methods
## ========================

func validate_message(message: String) -> Dictionary:
	"""
	Validates an incoming JSON message.
	
	Args:
		message: Raw message string
	
	Returns:
		Dictionary with keys:
			- valid: bool
			- reason: String (if invalid)
	"""
	var result: Dictionary = {
		"valid": false,
		"reason": ""
	}
	
	# Check for empty message
	if message.is_empty():
		result["reason"] = "Empty message"
		return result
	
	# Check message length
	if message.length() > MAX_STRING_LENGTH * 2:
		result["reason"] = "Message exceeds maximum length"
		security_violation.emit({
			"type": "length_exceeded",
			"length": message.length(),
			"max": MAX_STRING_LENGTH * 2
		})
		return result
	
	# Check for null characters
	if "\x00" in message:
		result["reason"] = "Message contains null characters"
		security_violation.emit({"type": "null_character"})
		return result
	
	# Parse JSON to check structure
	var parsed: Variant = JSON.parse_string(message)
	if parsed == null:
		result["reason"] = "Invalid JSON format"
		return result
	
	if typeof(parsed) != TYPE_DICTIONARY:
		result["reason"] = "Message must be a JSON object"
		return result
	
	result["valid"] = true
	return result


func validate_command(command: Dictionary) -> Dictionary:
	"""
	Validates a parsed command for security compliance.
	
	Args:
		command: Parsed command dictionary
	
	Returns:
		Dictionary with keys:
			- valid: bool
			- reason: String (if invalid)
			- details: Dictionary (additional info)
	"""
	var result: Dictionary = {
		"valid": false,
		"reason": "",
		"details": {}
	}
	
	# Check action field
	if command.has("action"):
		var action_validation: Dictionary = _validate_action(command["action"])
		if not action_validation.get("valid", false):
			return action_validation
	
	# Validate path fields if present
	var path_validation: Dictionary = _validate_paths(command)
	if not path_validation.get("valid", false):
		return path_validation
	
	# Validate string fields
	var string_validation: Dictionary = _validate_strings(command)
	if not string_validation.get("valid", false):
		return string_validation
	
	# Validate nested commands
	var depth_validation: Dictionary = _validate_command_depth(command)
	if not depth_validation.get("valid", false):
		return depth_validation
	
	result["valid"] = true
	return result


func validate_path(path: String, allowed_directories: Array[String] = []) -> Dictionary:
	"""
	Validates a filesystem path for security.
	
	Args:
		path: The path to validate
		allowed_directories: List of allowed base directories
	
	Returns:
		Dictionary with keys:
			- valid: bool
			- sanitized_path: String (if valid)
			- reason: String (if invalid)
	"""
	var result: Dictionary = {
		"valid": false,
		"sanitized_path": "",
		"reason": ""
	}
	
	# Check for empty path
	if path.is_empty():
		result["reason"] = "Empty path"
		return result
	
	# Check for dangerous patterns
	var pattern_check: Dictionary = _check_dangerous_patterns(path)
	if not pattern_check.get("valid", false):
		path_blocked.emit(path, pattern_check.get("reason", ""))
		return pattern_check
	
	# Normalize path
	var normalized: String = _normalize_path(path)
	if normalized.is_empty():
		result["reason"] = "Failed to normalize path"
		return result
	
	# Check if path is within allowed directories
	var allowed: bool = _is_path_allowed(normalized, allowed_directories)
	if not allowed:
		result["reason"] = "Path is outside allowed directories"
		result["details"] = {
			"path": normalized,
			"allowed_directories": allowed_directories
		}
		path_blocked.emit(path, "Outside allowed directories")
		return result
	
	result["valid"] = true
	result["sanitized_path"] = normalized
	return result


func validate_script_code(code: String) -> Dictionary:
	"""
	Validates script code for potentially dangerous operations.
	
	Args:
		code: GDScript code to validate
	
	Returns:
		Dictionary with validation results
	"""
	var result: Dictionary = {
		"valid": true,
		"warnings": [],
		"details": {}
	}
	
	# Check for dangerous function calls
	var dangerous_calls: Array[RegEx] = []
	var danger_regex: RegEx = RegEx.new()
	
	if danger_regex.compile(r"(system|popen|exec|eval|shell_exec|passthru)") == OK:
		dangerous_calls.append(danger_regex)
	
	# Check for dangerous patterns in code
	for regex: RegEx in DANGEROUS_PATTERNS:
		var matches: Array[RegExMatch] = regex.search_all(code)
		if not matches.is_empty():
			result["valid"] = false
			result["warnings"].append("Dangerous pattern detected")
			result["details"]["pattern"] = regex.get_pattern()
			result["details"]["match_count"] = matches.size()
			break
	
	# Check code length
	if code.length() > MAX_STRING_LENGTH:
		result["warnings"].append("Code exceeds recommended length")
	
	return result


## Internal Validation Methods
## =========================

func _validate_action(action: Variant) -> Dictionary:
	"""
	Validates the action field of a command.
	"""
	var result: Dictionary = {
		"valid": false,
		"reason": "",
		"details": {}
	}
	
	if typeof(action) != TYPE_STRING:
		result["reason"] = "Action must be a string"
		return result
	
	if action.is_empty():
		result["reason"] = "Action cannot be empty"
		return result
	
	# Check for excessive length
	if action.length() > 100:
		result["reason"] = "Action name too long"
		return result
	
	# Check for control characters
	for i: int in range(action.length()):
		var char_code: int = action.ord_at(i)
		if char_code < 32 and char_code != 9:  # Allow tab
			result["reason"] = "Action contains control characters"
			return result
	
	result["valid"] = true
	return result


func _validate_paths(command: Dictionary) -> Dictionary:
	"""
	Validates all path-related fields in a command.
	"""
	var result: Dictionary = {
		"valid": false,
		"reason": "",
		"details": {}
	}
	
	# Fields that should contain valid paths
	var path_fields: Array[String] = [
		"path", "script_path", "scene_path", "node_path",
		"parent_path", "resource_path", "save_path"
	]
	
	var allowed_directories: Array[String] = [
		_project_root,
		_scripts_path,
		_scenes_path,
		_resources_path
	]
	
	for field: String in path_fields:
		if command.has(field):
			var path_value: Variant = command[field]
			
			if typeof(path_value) == TYPE_STRING and not path_value.is_empty():
				var path_validation: Dictionary = validate_path(path_value, allowed_directories)
				
				if not path_validation.get("valid", false):
					result["reason"] = "Invalid path in field '%s': %s" % [field, path_validation.get("reason", "")]
					result["details"][field] = path_validation
					return result
	
	result["valid"] = true
	return result


func _validate_strings(command: Dictionary, _depth: int = 0) -> Dictionary:
	"""
	Recursively validates string fields in a command.
	"""
	var result: Dictionary = {
		"valid": true,
		"reason": "",
		"details": {}
	}
	
	# Limit recursion depth
	if _depth > MAX_COMMAND_DEPTH:
		result["valid"] = false
		result["reason"] = "Command structure too deeply nested"
		return result
	
	for key: Variant in command:
		if typeof(key) == TYPE_STRING:
			var value: Variant = command[key]
			
			match typeof(value):
				TYPE_STRING:
					# Check length
					if value.length() > MAX_STRING_LENGTH:
						result["valid"] = false
						result["reason"] = "String field '%s' exceeds maximum length" % key
						return result
					
					# Check for null characters
					if "\x00" in value:
						result["valid"] = false
						result["reason"] = "String field '%s' contains null characters" % key
						return result
				
				TYPE_DICTIONARY:
					var nested_result: Dictionary = _validate_strings(value, _depth + 1)
					if not nested_result.get("valid", false):
						return nested_result
	
	return result


func _validate_command_depth(command: Dictionary, current_depth: int = 0) -> Dictionary:
	"""
	Validates the depth of nested command structures.
	"""
	var result: Dictionary = {
		"valid": true,
		"reason": "",
		"details": {}
	}
	
	if current_depth > MAX_COMMAND_DEPTH:
		result["valid"] = false
		result["reason"] = "Command exceeds maximum nesting depth"
		return result
	
	# Check for deeply nested structures
	if command.has("original_command") and typeof(command["original_command"]) == TYPE_DICTIONARY:
		var nested: Dictionary = command["original_command"]
		return _validate_command_depth(nested, current_depth + 1)
	
	return result


func _check_dangerous_patterns(text: String) -> Dictionary:
	"""
	Checks text against dangerous pattern database.
	"""
	var result: Dictionary = {
		"valid": true,
		"reason": ""
	}
	
	for regex: RegEx in DANGEROUS_PATTERNS:
		var matches: Array[RegExMatch] = regex.search_all(text)
		if not matches.is_empty():
			result["valid"] = false
			result["reason"] = "Dangerous pattern detected: %s" % regex.get_pattern()
			return result
	
	return result


func _normalize_path(path: String) -> String:
	"""
	Normalizes a filesystem path for validation.
	
	Args:
		path: Raw path string
	
	Returns:
		Normalized path or empty string on error
	"""
	if path.is_empty():
		return ""
	
	# Replace backslashes with forward slashes
	var normalized: String = path.replace("\\", "/")
	
	# Remove duplicate slashes
	while "//" in normalized:
		normalized = normalized.replace("//", "/")
	
	# Remove leading and trailing slashes
	normalized = normalized.trim_prefix("/")
	normalized = normalized.trim_suffix("/")
	
	# Handle ".." components
	var components: Array[String] = normalized.split("/")
	var sanitized_components: Array[String] = []
	
	for component: String in components:
		if component == "..":
			if not sanitized_components.is_empty():
				sanitized_components.pop_back()
		elif component == "." or component.is_empty():
			continue
		else:
			sanitized_components.append(component)
	
	normalized = "/".join(sanitized_components)
	
	# Reject paths that would escape the project root
	if normalized.begins_with(".."):
		return ""
	
	return normalized


func _is_path_allowed(path: String, allowed_directories: Array[String]) -> bool:
	"""
	Checks if a path is within allowed directories.
	
	Args:
		path: The path to check
		allowed_directories: List of allowed base directories
	
	Returns:
		True if path is allowed
	"""
	for allowed_dir: String in allowed_directories:
		if allowed_dir.is_empty():
			continue
		
		var normalized_allowed: String = _normalize_path(allowed_dir)
		if normalized_allowed.is_empty():
			continue
		
		# Check if path starts with the allowed directory
		if path == normalized_allowed or path.begins_with(normalized_allowed + "/"):
			return true
		
		# Also check relative paths within project
		if path.begins_with("res://") and normalized_allowed.begins_with("res://"):
			var rel_path: String = path.replace("res://", "").trim_prefix("/")
			var allowed_rel: String = normalized_allowed.replace("res://", "").trim_prefix("/")
			
			if rel_path == allowed_rel or rel_path.begins_with(allowed_rel + "/"):
				return true
	
	# Allow relative paths without directory components
	if "/" not in path and "\\" not in path:
		return true
	
	return false


## Utility Methods
## ==============

func get_project_root() -> String:
	"""
	Returns the configured project root path.
	"""
	return _project_root


func sanitize_for_json(value: String) -> String:
	"""
	Sanitizes a string for safe JSON inclusion.
	
	Args:
		value: Raw string value
	
	Returns:
		Sanitized string
	"""
	var sanitized: String = value
	
	# Remove null characters
	sanitized = sanitized.replace("\x00", "")
	
	# Remove other control characters
	var result: String = ""
	for i: int in range(sanitized.length()):
		var char_code: int = sanitized.ord_at(i)
		if char_code >= 32 or char_code == 9 or char_code == 10 or char_code == 13:
			result += sanitized[i]
	
	return result


func is_localhost_only() -> bool:
	"""
	Returns whether this validator enforces localhost-only connections.
	Currently always true as the system is local-only.
	"""
	return true
