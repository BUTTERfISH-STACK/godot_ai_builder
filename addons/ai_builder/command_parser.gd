@tool
extends Node

## Command Parser for Godot AI Builder
## ====================================
## Parses and validates JSON commands from the AI server.
## Ensures all commands conform to the structured command protocol.

# Protocol version
const PROTOCOL_VERSION: String = "1.0.0"

# Maximum message size (1MB)
const MAX_MESSAGE_SIZE: int = 1048576

# Supported actions (must match plugin.gd)
const SUPPORTED_ACTIONS: Array[String] = [
	"create_scene",
	"add_node",
	"set_property",
	"attach_script",
	"create_script",
	"modify_script",
	"delete_node",
	"run_scene",
	"save_scene",
	"get_snapshot",
	"get_performance",
	"retry",
	"get_status",
	"get_protocol"
]

# Required fields per action
const ACTION_REQUIREMENTS: Dictionary = {
	"create_scene": ["name", "parent_path"],
	"add_node": ["node_type", "parent_path", "name"],
	"set_property": ["node_path", "property_name", "value"],
	"attach_script": ["node_path", "script_path"],
	"create_script": ["path", "name", "code"],
	"modify_script": ["path", "modifications"],
	"delete_node": ["node_path"],
	"run_scene": ["scene_path"],
	"save_scene": ["scene_path"],
	"get_snapshot": [],
	"get_performance": [],
	"retry": ["original_command"],
	"get_status": [],
	"get_protocol": []
}

# Optional fields that can be present
const OPTIONAL_FIELDS: Array[String] = [
	"auto_run",
	"description",
	"position",
	"rotation",
	"scale",
	"metadata",
	"settings",
	"retry_count"
]

# Signal declarations
signal parse_error(error: String, details: Dictionary)
signal command_validated(command: Dictionary)


## Public Methods
## =============

func parse(message: String) -> Dictionary:
	"""
	Parses a JSON message and validates it against the command protocol.
	
	Args:
		message: Raw JSON string from the AI server
	
	Returns:
		Dictionary with keys:
			- success: bool
			- command: Dictionary (if successful)
			- error: String (if failed)
	"""
	var result: Dictionary = {
		"success": false,
		"command": {},
		"error": ""
	}
	
	# Check for empty message
	if message.is_empty():
		result["error"] = "Empty message received"
		parse_error.emit(result["error"], {})
		return result
	
	# Check message size
	if message.length() > MAX_MESSAGE_SIZE:
		result["error"] = "Message exceeds maximum size of %d bytes" % MAX_MESSAGE_SIZE
		parse_error.emit(result["error"], {"size": message.length()})
		return result
	
	# Parse JSON
	var parse_error_result: Error = JSON.parse_string(message)
	
	if parse_error_result == null:
		result["error"] = "Invalid JSON format"
		parse_error.emit(result["error"], {"raw": message.substr(0, 200)})
		return result
	
	# Validate the command structure
	var validation_result: Dictionary = _validate_command(parse_error_result)
	
	if not validation_result.get("valid", false):
		result["error"] = validation_result.get("reason", "Validation failed")
		parse_error.emit(result["error"], validation_result.get("details", {}))
		return result
	
	result["success"] = true
	result["command"] = validation_result.get("command", {})
	
	command_validated.emit(result["command"])
	return result


func validate_command_structure(command: Dictionary) -> Dictionary:
	"""
	Validates a command dictionary structure.
	Used for pre-validation before execution.
	
	Args:
		command: Dictionary representing the command
	
	Returns:
		Dictionary with validation results
	"""
	return _validate_command(command)


## Internal Methods
## ==============

func _validate_command(data: Variant) -> Dictionary:
	"""
	Validates a command against the protocol specification.
	
	Args:
		data: Parsed JSON data (Dictionary expected)
	
	Returns:
		Dictionary with keys:
			- valid: bool
			- command: Dictionary (normalized command)
			- reason: String (if invalid)
			- details: Dictionary (additional error info)
	"""
	var result: Dictionary = {
		"valid": false,
		"command": {},
		"reason": "",
		"details": {}
	}
	
	# Must be a dictionary
	if typeof(data) != TYPE_DICTIONARY:
		result["reason"] = "Command must be a JSON object"
		result["details"]["type"] = typeof(data)
		return result
	
	var command: Dictionary = data
	
	# Check for action field
	if not command.has("action"):
		result["reason"] = "Missing required 'action' field"
		result["details"]["required_fields"] = ["action"]
		return result
	
	var action: String = command["action"]
	
	# Validate action is a string
	if typeof(action) != TYPE_STRING:
		result["reason"] = "Action field must be a string"
		result["details"]["action_type"] = typeof(action)
		return result
	
	# Check action is supported
	if not action in SUPPORTED_ACTIONS:
		result["reason"] = "Unsupported action: %s" % action
		result["details"]["action"] = action
		result["details"]["supported_actions"] = SUPPORTED_ACTIONS
		return result
	
	# Validate required fields for this action
	var required_fields: Array = ACTION_REQUIREMENTS.get(action, [])
	var missing_fields: Array = []
	var extra_fields: Array = []
	
	for field: String in required_fields:
		if not command.has(field):
			missing_fields.append(field)
	
	# Check for extra unknown fields
	var known_fields: Array = required_fields.duplicate()
	known_fields.append("action")
	
	for key: Variant in command:
		if typeof(key) == TYPE_STRING and not key in known_fields and not key in OPTIONAL_FIELDS:
			extra_fields.append(key)
	
	if not missing_fields.is_empty():
		result["reason"] = "Missing required fields for action '%s'" % action
		result["details"]["missing_fields"] = missing_fields
		result["details"]["action"] = action
		return result
	
	# Normalize and validate the command
	var normalized_command: Dictionary = _normalize_command(command)
	
	result["valid"] = true
	result["command"] = normalized_command
	
	return result


func _normalize_command(command: Dictionary) -> Dictionary:
	"""
	Normalizes a validated command for consistent processing.
	
	Args:
		command: Raw validated command dictionary
	
	Returns:
		Normalized command dictionary
	"""
	var normalized: Dictionary = {
		"action": command["action"]
	}
	
	# Copy all fields from the original command
	for key: Variant in command:
		if typeof(key) == TYPE_STRING:
			normalized[key] = command[key]
	
	# Add timestamp if not present
	if not normalized.has("timestamp"):
		normalized["timestamp"] = Time.get_unix_time_from_system()
	
	# Add request ID if not present
	if not normalized.has("request_id"):
		normalized["request_id"] = _generate_request_id()
	
	return normalized


func _generate_request_id() -> String:
	"""
	Generates a unique request ID for tracking.
	
	Returns:
		String request ID
	"""
	return "req_%d_%d" % [Time.get_ticks_msec(), randi() % 10000]


## Schema Validation
## ===============

func get_action_schema(action: String) -> Dictionary:
	"""
	Returns the JSON schema for a specific action.
	
	Args:
		action: The action name
	
	Returns:
		Dictionary representing the schema
	"""
	if not action in ACTION_REQUIREMENTS:
		return {}
	
	var schema: Dictionary = {
		"type": "object",
		"properties": {},
		"required": ACTION_REQUIREMENTS[action].duplicate()
	}
	
	# Add field schemas based on action type
	match action:
		"create_scene":
			schema["properties"] = {
				"name": {"type": "string"},
				"parent_path": {"type": "string"},
				"scene_type": {"type": "string", "enum": ["Node3D", "Node2D", "Control"]}
			}
		
		"add_node":
			schema["properties"] = {
				"node_type": {"type": "string"},
				"parent_path": {"type": "string"},
				"name": {"type": "string"},
				"position": {"type": "array", "items": {"type": "number"}},
				"rotation": {"type": "array", "items": {"type": "number"}},
				"scale": {"type": "array", "items": {"type": "number"}}
			}
		
		"set_property":
			schema["properties"] = {
				"node_path": {"type": "string"},
				"property_name": {"type": "string"},
				"value": {"type": "variant"}
			}
		
		"create_script":
			schema["properties"] = {
				"path": {"type": "string"},
				"name": {"type": "string"},
				"code": {"type": "string"},
				"class_name": {"type": "string"}
			}
		
		"modify_script":
			schema["properties"] = {
				"path": {"type": "string"},
				"modifications": {"type": "object"}
			}
		
		"run_scene":
			schema["properties"] = {
				"scene_path": {"type": "string"},
				"auto_run": {"type": "boolean"}
			}
		
		"retry":
			schema["properties"] = {
				"original_command": {"type": "object"}
			}
	
	# Add common optional fields
	for field: String in OPTIONAL_FIELDS:
		if not field in schema["properties"]:
			schema["properties"][field] = {"type": "variant", "optional": true}
	
	return schema


func validate_against_schema(data: Dictionary, schema: Dictionary) -> Dictionary:
	"""
	Validates data against a JSON schema.
	
	Args:
		data: Data to validate
		schema: JSON schema dictionary
	
	Returns:
		Dictionary with validation results
	"""
	var result: Dictionary = {
		"valid": true,
		"errors": []
	}
	
	if not schema.has("type"):
		return result
	
	match schema["type"]:
		"object":
			# Check required fields
			if schema.has("required"):
				for required_field: String in schema["required"]:
					if not data.has(required_field):
						result["valid"] = false
						result["errors"].append("Missing required field: %s" % required_field)
			
			# Check property types
			if schema.has("properties"):
				for prop: Variant in schema["properties"]:
					if typeof(prop) == TYPE_STRING and data.has(prop):
						var prop_schema: Dictionary = schema["properties"][prop]
						var type_result: Dictionary = _validate_type(data[prop], prop_schema.get("type", "variant"))
						if not type_result.get("valid", false):
							result["valid"] = false
							result["errors"].append("Field '%s': %s" % [prop, type_result.get("reason", "Invalid type")])
		
		"array":
			if typeof(data) != TYPE_ARRAY:
				result["valid"] = false
				result["errors"].append("Expected array type")
	
	return result


func _validate_type(value: Variant, expected_type: String) -> Dictionary:
	"""
	Validates a value against an expected type.
	
	Args:
		value: The value to validate
		expected_type: String name of expected type
	
	Returns:
		Dictionary with validation result
	"""
	var result: Dictionary = {"valid": true}
	
	match expected_type:
		"string":
			if typeof(value) != TYPE_STRING:
				result["valid"] = false
				result["reason"] = "Expected string, got %s" % typeof(value)
		
		"number":
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				result["valid"] = false
				result["reason"] = "Expected number, got %s" % typeof(value)
		
		"boolean":
			if typeof(value) != TYPE_BOOL:
				result["valid"] = false
				result["reason"] = "Expected boolean, got %s" % typeof(value)
		
		"object":
			if typeof(value) != TYPE_DICTIONARY:
				result["valid"] = false
				result["reason"] = "Expected object, got %s" % typeof(value)
		
		"array":
			if typeof(value) != TYPE_ARRAY:
				result["valid"] = false
				result["reason"] = "Expected array, got %s" % typeof(value)
		
		"variant":
			# No validation needed
			pass
	
	return result


## Utility Methods
## ==============

func get_supported_actions() -> Array[String]:
	"""
	Returns the list of supported actions.
	"""
	return SUPPORTED_ACTIONS.duplicate()


func get_protocol_info() -> Dictionary:
	"""
	Returns protocol version and capabilities.
	"""
	return {
		"version": PROTOCOL_VERSION,
		"supported_actions": SUPPORTED_ACTIONS,
		"max_message_size": MAX_MESSAGE_SIZE,
		"action_requirements": ACTION_REQUIREMENTS
	}


func sanitize_string(value: String) -> String:
	"""
	Sanitizes a string value for safe use.
	
	Args:
		value: Raw string value
	
	Returns:
		Sanitized string
	"""
	# Remove null characters
	var sanitized: String = value.replace("\x00", "")
	
	# Remove control characters except common whitespace
	var result: String = ""
	for i: int in range(sanitized.length()):
		var char_code: int = sanitized.ord_at(i)
		if char_code >= 32 or char_code == 9 or char_code == 10 or char_code == 13:
			result += sanitized[i]
	
	# Limit length
	if result.length() > MAX_MESSAGE_SIZE:
		result = result.substr(0, MAX_MESSAGE_SIZE)
	
	return result
