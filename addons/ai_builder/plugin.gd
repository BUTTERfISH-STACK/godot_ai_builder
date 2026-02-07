@tool
extends EditorPlugin

## Godot 4 Autonomous AI Builder - Main Plugin Script
## =====================================================
## This plugin enables AI-driven game development through:
## - WebSocket-based communication with local AI server
## - Structured JSON command protocol
## - Automated scene creation and modification
## - Self-correcting error handling
## - Performance monitoring and optimization

# Version information
const PLUGIN_VERSION: String = "1.0.0"
const PROTOCOL_VERSION: String = "1.0.0"

# Connection settings
const DEFAULT_WEBSOCKET_PORT: int = 8765
const WEBSOCKET_PATH: String = "/ai_builder"

# Component references
var _websocket_server: Node
var _command_parser: Node
var _scene_engine: Node
var _script_engine: Node
var _error_handler: Node
var _runtime_monitor: Node
var _auto_runner: Node
var _performance_monitor: Node
var _snapshot_system: Node
var _security_validator: Node

# State management
var _is_server_running: bool = false
var _retry_count: int = 0
const MAX_RETRIES: int = 5
var _current_retry_action: Dictionary = {}

# Performance metrics
var _performance_data: Dictionary = {}

# Error tracking
var _last_error: Dictionary = {}
var _error_history: Array[Dictionary] = []

# Project context
var _project_path: String = ""
var _scene_tree_snapshot: Array = []
var _scripts_snapshot: Dictionary = {}

# Signal declarations for external communication
signal command_received(command: Dictionary)
signal command_executed(response: Dictionary)
signal error_occurred(error: Dictionary)
signal performance_report(report: Dictionary)
signal snapshot_updated(snapshot: Dictionary)
signal server_status_changed(is_running: bool)


## Lifecycle Methods
## =================

func _enter_tree() -> void:
	"""
	Called when the plugin is loaded by the Godot Editor.
	Initializes all components and starts the WebSocket server.
	"""
	_project_path = ProjectSettings.globalize_path("res://")
	
	_setup_components()
	_connect_signals()
	_validate_environment()
	
	print("[Godot AI Builder v%s] Plugin initializing..." % PLUGIN_VERSION)
	print("[Godot AI Builder] Project path: %s" % _project_path)
	
	# Delay server start to ensure editor is fully ready
	await get_tree().process_frame
	_start_server()


func _exit_tree() -> void:
	"""
	Called when the plugin is unloaded.
	Properly shuts down all components and closes connections.
	"""
	print("[Godot AI Builder] Shutting down...")
	_stop_server()
	_cleanup_components()
	print("[Godot AI Builder] Plugin unloaded.")


func _process(_delta: float) -> void:
	"""
	Main plugin update loop.
	Handles periodic tasks like performance monitoring and snapshots.
	"""
	if not _is_server_running:
		return
	
	_update_performance_metrics()
	
	# Periodic snapshot update (every 5 seconds)
	if Engine.get_frames_drawn() % (60 * 5) == 0:
		_update_snapshot()


## Component Setup
## ==============

func _setup_components() -> void:
	"""
	Initializes all plugin components as child nodes.
	Each component handles a specific aspect of AI-driven development.
	"""
	# Security validator - validates all incoming commands
	_security_validator = preload("res://addons/ai_builder/security_validator.gd").new()
	add_child(_security_validator)
	
	# Command parser - validates and routes JSON commands
	_command_parser = preload("res://addons/ai_builder/command_parser.gd").new()
	add_child(_command_parser)
	
	# Scene engine - handles scene modifications
	_scene_engine = preload("res://addons/ai_builder/scene_engine.gd").new()
	add_child(_scene_engine)
	
	# Script engine - manages script creation and modification
	_script_engine = preload("res://addons/ai_builder/script_engine.gd").new()
	add_child(_script_engine)
	
	# Error handler - captures and processes errors
	_error_handler = preload("res://addons/ai_builder/error_handler.gd").new()
	add_child(_error_handler)
	
	# Runtime monitor - monitors game execution
	_runtime_monitor = preload("res://addons/ai_builder/runtime_monitor.gd").new()
	add_child(_runtime_monitor)
	
	# Auto runner - automatically runs scenes after modifications
	_auto_runner = preload("res://addons/ai_builder/auto_runner.gd").new()
	add_child(_auto_runner)
	
	# Performance monitor - tracks and reports performance metrics
	_performance_monitor = preload("res://addons/ai_builder/performance_monitor.gd").new()
	add_child(_performance_monitor)
	
	# Snapshot system - provides project context to AI
	_snapshot_system = preload("res://addons/ai_builder/snapshot_system.gd").new()
	add_child(_snapshot_system)
	
	# WebSocket server - communication endpoint
	_websocket_server = preload("res://addons/ai_builder/websocket_server.gd").new()
	add_child(_websocket_server)


func _connect_signals() -> void:
	"""
	Establishes signal connections between components for event-driven architecture.
	"""
	# WebSocket server signals
	if _websocket_server.has_signal("message_received"):
		_websocket_server.message_received.connect(_on_websocket_message_received)
	if _websocket_server.has_signal("client_connected"):
		_websocket_server.client_connected.connect(_on_client_connected)
	if _websocket_server.has_signal("client_disconnected"):
		_websocket_server.client_disconnected.connect(_on_client_disconnected)
	
	# Error handler signals
	if _error_handler.has_signal("compile_error"):
		_error_handler.compile_error.connect(_on_compile_error)
	if _error_handler.has_signal("runtime_error"):
		_error_handler.runtime_error.connect(_on_runtime_error)
	
	# Performance monitor signals
	if _performance_monitor.has_signal("performance_report"):
		_performance_monitor.performance_report.connect(_on_performance_report)
	
	# Auto runner signals
	if _auto_runner.has_signal("scene_ready"):
		_auto_runner.scene_ready.connect(_on_scene_ready)
	if _auto_runner.has_signal("execution_failed"):
		_auto_runner.execution_failed.connect(_on_execution_failed)


func _validate_environment() -> void:
	"""
	Validates that the Godot Editor environment is suitable for the plugin.
	Checks for required features and dependencies.
	"""
	var godot_version: String = Engine.get_version_info().get("string", "unknown")
	print("[Godot AI Builder] Running on Godot %s" % godot_version)
	
	# Verify WebSocket support is available
	if not WebSocketPeer:
		push_error("[Godot AI Builder] ERROR: WebSocketPeer not available!")
		return
	
	# Verify project is properly configured
	if not DirAccess.dir_exists_absolute(_project_path):
		push_error("[Godot AI Builder] ERROR: Project path not accessible!")
		return
	
	print("[Godot AI Builder] Environment validation passed.")


func _cleanup_components() -> void:
	"""
	Properly disposes of all components and frees resources.
	"""
	_auto_runner.set_deferred("enabled", false)
	_runtime_monitor.set_deferred("enabled", false)
	_performance_monitor.set_deferred("enabled", false)
	
	if is_instance_valid(_websocket_server):
		_websocket_server.queue_free()
	if is_instance_valid(_command_parser):
		_command_parser.queue_free()
	if is_instance_valid(_scene_engine):
		_scene_engine.queue_free()
	if is_instance_valid(_script_engine):
		_script_engine.queue_free()
	if is_instance_valid(_error_handler):
		_error_handler.queue_free()
	if is_instance_valid(_runtime_monitor):
		_runtime_monitor.queue_free()
	if is_instance_valid(_auto_runner):
		_auto_runner.queue_free()
	if is_instance_valid(_performance_monitor):
		_performance_monitor.queue_free()
	if is_instance_valid(_snapshot_system):
		_snapshot_system.queue_free()
	if is_instance_valid(_security_validator):
		_security_validator.queue_free()


## WebSocket Server Management
## ===========================

func _start_server() -> void:
	"""
	Starts the WebSocket server on the configured port.
	Implements automatic port finding if default is unavailable.
	"""
	var port: int = DEFAULT_WEBSOCKET_PORT
	var max_attempts: int = 10
	var attempt: int = 0
	
	while attempt < max_attempts:
		var result: Error = _websocket_server.start_server(port, WEBSOCKET_PATH)
		if result == OK:
			_is_server_running = true
			print("[Godot AI Builder] WebSocket server started on port %d" % port)
			emit_signal("server_status_changed", true)
			return
		
		# Try next port if current is in use
		port += 1
		attempt += 1
		print("[Godot AI Builder] Port %d in use, trying %d..." % (port - 1, port))
	
	push_error("[Godot AI Builder] Failed to start WebSocket server after %d attempts" % max_attempts)


func _stop_server() -> void:
	"""
	Gracefully shuts down the WebSocket server.
	"""
	if _is_server_running:
		_websocket_server.stop_server()
		_is_server_running = false
		emit_signal("server_status_changed", false)
		print("[Godot AI Builder] WebSocket server stopped.")


## Message Handling
## ================

func _on_websocket_message_received(message: String) -> void:
	"""
	Handles incoming WebSocket messages from the AI server.
	Routes commands through the parsing and execution pipeline.
	"""
	print("[Godot AI Builder] Received message: %s" % message.substr(0, 200))
	
	# Security validation
	var validation_result: Dictionary = _security_validator.validate_message(message)
	if not validation_result.get("valid", false):
		var error_response: Dictionary = {
			"status": "error",
			"type": "security",
			"message": validation_result.get("reason", "Validation failed"),
			"timestamp": Time.get_unix_time_from_system()
		}
		_send_response(error_response)
		return
	
	# Parse command
	var parse_result: Dictionary = _command_parser.parse(message)
	if not parse_result.get("success", false):
		var error_response: Dictionary = {
			"status": "error",
			"type": "parse",
			"message": parse_result.get("error", "Parse failed"),
			"timestamp": Time.get_unix_time_from_system()
		}
		_send_response(error_response)
		return
	
	var command: Dictionary = parse_result.get("command", {})
	command_received.emit(command)
	
	# Execute command
	_execute_command(command)


func _execute_command(command: Dictionary) -> void:
	"""
	Executes a validated command and handles the response.
	Implements the self-correcting loop for errors.
	"""
	var action: String = command.get("action", "")
	var response: Dictionary
	
	match action:
		"create_scene":
			response = _scene_engine.create_scene(command)
		"add_node":
			response = _scene_engine.add_node(command)
		"set_property":
			response = _scene_engine.set_property(command)
		"attach_script":
			response = _scene_engine.attach_script(command)
		"create_script":
			response = _script_engine.create_script(command)
		"modify_script":
			response = _script_engine.modify_script(command)
		"delete_node":
			response = _scene_engine.delete_node(command)
		"run_scene":
			response = _auto_runner.run_scene(command)
		"save_scene":
			response = _scene_engine.save_scene(command)
		"get_snapshot":
			response = _snapshot_system.get_snapshot(command)
		"get_performance":
			response = _performance_monitor.get_report()
		"retry":
			response = _handle_retry(command)
		"get_status":
			response = _get_status()
		"get_protocol":
			response = _get_protocol_info()
		_:
			response = {
				"status": "error",
				"type": "unknown_action",
				"message": "Unknown action: %s" % action,
				"timestamp": Time.get_unix_time_from_system()
			}
	
	response["action"] = action
	response["timestamp"] = Time.get_unix_time_from_system()
	
	command_executed.emit(response)
	_send_response(response)
	
	# Check if auto-run is needed
	if command.get("auto_run", false) and response.get("status") == "success":
		_auto_runner.queue_auto_run(command)


func _send_response(response: Dictionary) -> void:
	"""
	Sends a JSON response back to the AI server via WebSocket.
	"""
	var json_string: String = JSON.stringify(response)
	_websocket_server.broadcast_message(json_string)


## Client Connection Management
## ===========================

func _on_client_connected(client_id: int) -> void:
	"""
	Handles new client connections.
	Sends protocol information and current project snapshot.
	"""
	print("[Godot AI Builder] Client %d connected" % client_id)
	
	# Send welcome message with protocol info
	var welcome: Dictionary = {
		"status": "success",
		"type": "connection",
		"message": "Connected to Godot AI Builder v%s" % PLUGIN_VERSION,
		"protocol_version": PROTOCOL_VERSION,
		"godot_version": Engine.get_version_info().get("string", "unknown"),
		"project_path": _project_path,
		"timestamp": Time.get_unix_time_from_system()
	}
	_websocket_server.send_to_client(client_id, JSON.stringify(welcome))
	
	# Send initial snapshot
	var snapshot: Dictionary = _snapshot_system.get_snapshot({})
	_websocket_server.send_to_client(client_id, JSON.stringify(snapshot))


func _on_client_disconnected(client_id: int) -> void:
	"""
	Handles client disconnections.
	"""
	print("[Godot AI Builder] Client %d disconnected" % client_id)


## Error Handling
## ==============

func _on_compile_error(error: Dictionary) -> void:
	"""
	Handles compile errors from the error handler.
	Implements the self-correction loop.
	"""
	print("[Godot AI Builder] Compile error: %s" % error.get("message", "Unknown"))
	
	error_occurred.emit(error)
	_error_history.append(error)
	_last_error = error
	
	# Check retry limit
	if _retry_count >= MAX_RETRIES:
		var abort_response: Dictionary = {
			"status": "error",
			"type": "compile",
			"message": "Max retries (%d) exceeded. Aborting." % MAX_RETRIES,
			"error": error,
			"timestamp": Time.get_unix_time_from_system()
		}
		_send_response(abort_response)
		_retry_count = 0
		return
	
	# Request correction from AI
	var correction_request: Dictionary = {
		"status": "error",
		"type": "compile_error_correction",
		"error": error,
		"retry_count": _retry_count + 1,
		"max_retries": MAX_RETRIES,
		"timestamp": Time.get_unix_time_from_system()
	}
	_send_response(correction_request)


func _on_runtime_error(error: Dictionary) -> void:
	"""
	Handles runtime errors from the error handler.
	Implements the self-correction loop.
	"""
	print("[Godot AI Builder] Runtime error: %s at %s" % [error.get("message", "Unknown"), error.get("node_path", "unknown")])
	
	error_occurred.emit(error)
	_error_history.append(error)
	_last_error = error
	
	# Check retry limit
	if _retry_count >= MAX_RETRIES:
		var abort_response: Dictionary = {
			"status": "error",
			"type": "runtime",
			"message": "Max retries (%d) exceeded. Aborting." % MAX_RETRIES,
			"error": error,
			"timestamp": Time.get_unix_time_from_system()
		}
		_send_response(abort_response)
		_retry_count = 0
		return
	
	# Request correction from AI
	var correction_request: Dictionary = {
		"status": "error",
		"type": "runtime_error_correction",
		"error": error,
		"retry_count": _retry_count + 1,
		"max_retries": MAX_RETRIES,
		"timestamp": Time.get_unix_time_from_system()
	}
	_send_response(correction_request)


func _handle_retry(command: Dictionary) -> Dictionary:
	"""
	Handles retry commands for error correction.
	"""
	_retry_count += 1
	var original_command: Dictionary = command.get("original_command", {})
	
	if original_command.is_empty():
		return {
			"status": "error",
			"type": "retry",
			"message": "No original command found for retry",
			"timestamp": Time.get_unix_time_from_system()
		}
	
	# Re-execute the original command
	_current_retry_action = original_command
	return _execute_command(original_command)


## Performance Monitoring
## =====================

func _update_performance_metrics() -> void:
	"""
	Updates performance metrics from the performance monitor.
	"""
	_performance_data = _performance_monitor.get_report()


func _on_performance_report(report: Dictionary) -> void:
	"""
	Handles performance reports and checks for optimization needs.
	"""
	print("[Godot AI Builder] Performance report received")
	
	performance_report.emit(report)
	
	# Check for performance issues
	var fps: float = report.get("fps", 60.0)
	var node_count: int = report.get("node_count", 0)
	var draw_calls: int = report.get("draw_calls", 0)
	
	if fps < 60.0 or node_count > 2000 or draw_calls > 10000:
		var optimization_request: Dictionary = {
			"status": "warning",
			"type": "performance_optimization",
			"metrics": report,
			"recommendations": _generate_optimization_recommendations(report),
			"timestamp": Time.get_unix_time_from_system()
		}
		_send_response(optimization_request)


func _generate_optimization_recommendations(report: Dictionary) -> Array:
	"""
	Generates optimization recommendations based on performance data.
	"""
	var recommendations: Array = []
	
	if report.get("fps", 60.0) < 60.0:
		recommendations.append({
			"issue": "Low FPS",
			"solution": "Reduce draw calls, simplify shaders, use LOD for distant objects"
		})
	
	if report.get("node_count", 0) > 2000:
		recommendations.append({
			"issue": "High node count",
			"solution": "Merge static meshes, use MultiMeshInstance for repeated objects"
		})
	
	if report.get("draw_calls", 0) > 10000:
		recommendations.append({
			"issue": "Excessive draw calls",
			"solution": "Enable instancing, bake static lighting, use occlusion culling"
		})
	
	return recommendations


## Auto-Run Handling
## =================

func _on_scene_ready(data: Dictionary) -> void:
	"""
	Handles scene ready events after auto-run.
	"""
	print("[Godot AI Builder] Scene ready: %s" % data.get("scene_path", "unknown"))
	
	# Start performance monitoring
	_performance_monitor.start_monitoring()
	
	# Send success response
	var response: Dictionary = {
		"status": "success",
		"type": "scene_executed",
		"scene_path": data.get("scene_path", ""),
		"timestamp": Time.get_unix_time_from_system()
	}
	_send_response(response)


func _on_execution_failed(error: Dictionary) -> void:
	"""
	Handles scene execution failures.
	"""
	print("[Godot AI Builder] Execution failed: %s" % error.get("message", "Unknown"))
	
	_retry_count += 1
	
	var response: Dictionary = {
		"status": "error",
		"type": "execution",
		"message": error.get("message", "Execution failed"),
		"retry_count": _retry_count,
		"max_retries": MAX_RETRIES,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	if _retry_count >= MAX_RETRIES:
		response["type"] = "execution_aborted"
		response["message"] = "Max retries exceeded"
		_retry_count = 0
	
	_send_response(response)


## Snapshot Management
## ==================

func _update_snapshot() -> void:
	"""
	Updates the project snapshot for AI context.
	"""
	var snapshot: Dictionary = _snapshot_system.get_snapshot({})
	_scene_tree_snapshot = snapshot.get("scene_tree", [])
	_scripts_snapshot = snapshot.get("scripts", {})
	
	snapshot_updated.emit(snapshot)


## Status and Protocol
## ===================

func _get_status() -> Dictionary:
	"""
	Returns current plugin status.
	"""
	return {
		"status": "success",
		 PLUGIN_VERSION,
"plugin_version":		"protocol_version": PROTOCOL_VERSION,
		"server_running": _is_server_running,
		"project_path": _project_path,
		"retry_count": _retry_count,
		"error_count": _error_history.size(),
		"timestamp": Time.get_unix_time_from_system()
	}


func _get_protocol_info() -> Dictionary:
	"""
	Returns protocol documentation for AI clients.
	"""
	return {
		"status": "success",
		"protocol_version": PROTOCOL_VERSION,
		"actions": [
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
		],
		"response_types": {
			"success": "Command executed successfully",
			"error": "Command failed with structured error data"
		},
		"error_format": {
			"status": "error",
			"type": "compile | runtime | parse | security | execution",
			"file": "path/to/file",
			"line": number,
			"message": "error description",
			"stack": "stack trace"
		},
		"timestamp": Time.get_unix_time_from_system()
	}
