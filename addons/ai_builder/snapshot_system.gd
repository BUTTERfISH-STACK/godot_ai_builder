@tool
extends Node

## Snapshot System for Godot AI Builder
## =====================================
## Provides project context to the AI by collecting and reporting
## scene tree, scripts, input map, and autoload information.

# Signal declarations
signal snapshot_updated(snapshot: Dictionary)
signal snapshot_requested(data: Dictionary)

# Snapshot data
var _last_snapshot: Dictionary = {}
var _snapshot_version: int = 0
var _is_dirty: bool = true


## Lifecycle
## ========

func _ready() -> void:
	"""
	Initialize the snapshot system.
	"""
	print("[Snapshot System] Initialized")


## Public Methods
## =============

func get_snapshot(command: Dictionary = {}) -> Dictionary:
	"""
	Generates and returns a comprehensive project snapshot.
	
	Args:
		command: Optional parameters:
			- include_scenes: bool - Include scene tree
			- include_scripts: bool - Include script list
			- include_input: bool - Include input map
			- include_autoloads: bool - Include autoloads
			- include_settings: bool - Include project settings
			- depth: int - Node traversal depth
	
	Returns:
		Dictionary containing:
			- version: int - Snapshot version
			- timestamp: float - Unix timestamp
			- scene_tree: Array - Scene hierarchy
			- scripts: Dictionary - Script information
			- input_map: Dictionary - Input map configuration
			- autoloads: Array - Autoload singletons
			- project_info: Dictionary - Project metadata
	"""
	var include_scenes: bool = command.get("include_scenes", true)
	var include_scripts: bool = command.get("include_scripts", true)
	var include_input: bool = command.get("include_input", true)
	var include_autoloads: bool = command.get("include_autoloads", true)
	var include_settings: bool = command.get("include_settings", false)
	var depth: int = command.get("depth", 50)
	
	var snapshot: Dictionary = {
		"version": _snapshot_version,
		"timestamp": Time.get_unix_time_from_system(),
		"scene_tree": [],
		"scripts": {},
		"input_map": {},
		"autoloads": [],
		"project_info": {}
	}
	
	# Collect scene tree
	if include_scenes:
		snapshot["scene_tree"] = _collect_scene_tree(depth)
	
	# Collect scripts
	if include_scripts:
		snapshot["scripts"] = _collect_scripts()
	
	# Collect input map
	if include_input:
		snapshot["input_map"] = _collect_input_map()
	
	# Collect autoloads
	if include_autoloads:
		snapshot["autoloads"] = _collect_autoloads()
	
	# Collect project info
	if include_settings:
		snapshot["project_info"] = _collect_project_info()
	
	# Cache the snapshot
	_last_snapshot = snapshot.duplicate(true)
	_snapshot_version += 1
	_is_dirty = false
	
	snapshot_updated.emit(snapshot)
	
	return snapshot


func get_scene_tree_snapshot(depth: int = 50) -> Array:
	"""
	Returns only the scene tree.
	
	Args:
		depth: Maximum node traversal depth
	
	Returns:
		Array of node descriptions
	"""
	return _collect_scene_tree(depth)


func get_scripts_snapshot() -> Dictionary:
	"""
	Returns script information.
	
	Returns:
		Dictionary mapping script paths to information
	"""
	return _collect_scripts()


func get_input_map_snapshot() -> Dictionary:
	"""
	Returns input map configuration.
	
	Returns:
		Dictionary with input map data
	"""
	return _collect_input_map()


func get_autoloads_snapshot() -> Array:
	"""
	Returns autoload singletons.
	
	Returns:
		Array of autoload definitions
	"""
	return _collect_autoloads()


func mark_dirty() -> void:
	"""
	Marks the snapshot as stale.
	"""
	_is_dirty = true


func get_last_snapshot() -> Dictionary:
	"""
	Returns the last captured snapshot.
	"""
	return _last_snapshot.duplicate(true)


## Internal Methods
## ==============

func _collect_scene_tree(depth: int) -> Array:
	"""
	Collects the current scene tree.
	
	Args:
		depth: Maximum traversal depth
	
	Returns:
		Array of node dictionaries
	"""
	var tree: Array = []
	var root: Node = get_tree().edited_scene_root
	
	if root == null:
		return []
	
	_recursive_collect_nodes(root, "", tree, 0, depth)
	
	return tree


func _recursive_collect_nodes(node: Node, prefix: String, tree: Array, current_depth: int, max_depth: int) -> void:
	"""
	Recursively collects node information.
	"""
	if current_depth >= max_depth:
		return
	
	var node_path: String
	if prefix.is_empty():
		node_path = node.name
	else:
		node_path = prefix + "/" + node.name
	
	var node_info: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"path": node_path,
		"depth": current_depth
	}
	
	# Add script information
	var script: Script = node.get_script()
	if script != null:
		node_info["script"] = script.resource_path if script.resource_path else ""
	
	# Add transform information
	if node is Node3D:
		var node_3d: Node3D = node as Node3D
		node_info["position"] = [node_3d.position.x, node_3d.position.y, node_3d.position.z]
		node_info["rotation"] = [node_3d.rotation_degrees.x, node_3d.rotation_degrees.y, node_3d.rotation_degrees.z]
		node_info["scale"] = [node_3d.scale.x, node_3d.scale.y, node_3d.scale.z]
	elif node is Node2D:
		var node_2d: Node2D = node as Node2D
		node_info["position"] = [node_2d.position.x, node_2d.position.y]
		node_info["rotation"] = [node_2d.rotation_degrees]
		node_info["scale"] = [node_2d.scale.x, node_2d.scale.y]
	
	# Add children count
	node_info["child_count"] = node.get_child_count()
	
	# Add groups
	var groups: Array = node.get_groups()
	if not groups.is_empty():
		node_info["groups"] = groups
	
	tree.append(node_info)
	
	# Process children
	for child: Node in node.get_children():
		_recursive_collect_nodes(child, node_path, tree, current_depth + 1, max_depth)


func _collect_scripts() -> Dictionary:
	"""
	Collects script information from the project.
	
	Returns:
		Dictionary mapping script paths to information
	"""
	var scripts: Dictionary = {}
	
	# Find script files in the project
	var search_paths: Array[String] = [
		"res://",
		"res://scripts",
		"res://addons"
	]
	
	for search_path: String in search_paths:
		if DirAccess.dir_exists_absolute(search_path):
			_recursive_find_scripts(search_path, scripts)
	
	return scripts


func _recursive_find_scripts(dir_path: String, scripts: Dictionary) -> void:
	"""
	Recursively finds .gd files in a directory.
	
	Args:
		dir_path: Directory to search
		scripts: Dictionary to populate
	"""
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return
	
	dir.list_dir_begin()
	
	var file_name: String = dir.get_next()
	while file_name != "":
		var full_path: String = dir_path.path_join(file_name)
		
		if dir.current_is_dir():
			if not file_name.begins_with(".") and file_name != "node_modules":
				_recursive_find_scripts(full_path, scripts)
		elif file_name.ends_with(".gd"):
			var script_info: Dictionary = _analyze_script(full_path)
			scripts[full_path] = script_info
		
		file_name = dir.get_next()
	
	dir.list_dir_end()


func _analyze_script(script_path: String) -> Dictionary:
	"""
	Analyzes a script file.
	
	Args:
		script_path: Path to the script
	
	Returns:
		Dictionary with script information
	"""
	var info: Dictionary = {
		"path": script_path,
		"name": script_path.get_file().get_basename(),
		"size": 0,
		"lines": 0,
		"class_name": "",
		"base_class": "",
		"methods": [],
		"signals": [],
		"variables": []
	}
	
	if not FileAccess.file_exists(script_path):
		return info
	
	var file: FileAccess = FileAccess.open(script_path, FileAccess.READ)
	if file == null:
		return info
	
	var code: String = file.get_as_text()
	file.close()
	
	info["size"] = code.length()
	info["lines"] = code.split("\n").size()
	
	# Extract class name
	var class_regex: RegEx = RegEx.new()
	if class_regex.compile(r"class_name\\s+(\\w+)") == OK:
		var matches: Array[RegExMatch] = class_regex.search_all(code)
		if not matches.is_empty():
			info["class_name"] = matches[0].get_string(1)
	
	# Extract base class
	var extends_regex: RegEx = RegEx.new()
	if extends_regex.compile(r"extends\\s+(\\w+)") == OK:
		var matches: Array[RegExMatch] = extends_regex.search_all(code)
		if not matches.is_empty():
			info["base_class"] = matches[0].get_string(1)
	
	# Extract methods
	var method_regex: RegEx = RegEx.new()
	if method_regex.compile(r"func\\s+(\\w+)") == OK:
		var matches: Array[RegExMatch] = method_regex.search_all(code)
		for match: RegExMatch in matches:
			info["methods"].append(match.get_string(1))
	
	# Extract signals
	var signal_regex: RegEx = RegEx.new()
	if signal_regex.compile(r"signal\\s+(\\w+)") == OK:
		var matches: Array[RegExMatch] = signal_regex.search_all(code)
		for match: RegExMatch in matches:
			info["signals"].append(match.get_string(1))
	
	# Extract variables
	var var_regex: RegEx = RegEx.new()
	if var_regex.compile(r"var\\s+(\\w+)") == OK:
		var matches: Array[RegExMatch] = var_regex.search_all(code)
		for match: RegExMatch in matches:
			info["variables"].append(match.get_string(1))
	
	return info


func _collect_input_map() -> Dictionary:
	"""
	Collects input map configuration.
	
	Returns:
		Dictionary with input actions
	"""
	var input_map: Dictionary = {
		"actions": [],
		"deadzones": {},
		"joypad": {}
	}
	
	# Get input map actions
	var actions: Array = InputMap.get_actions()
	
	for action: String in actions:
		var action_info: Dictionary = {
			"name": action,
			"events": []
		}
		
		var events: Array = InputMap.get_action_list(action)
		for event: InputEvent in events:
			var event_str: String = _input_event_to_string(event)
			action_info["events"].append(event_str)
		
		input_map["actions"].append(action_info)
	
	# Get deadzone settings
	input_map["deadzones"]["analog_l_stick"] = InputMap.deadzone_setting("analog_l_stick", 0.5)
	input_map["deadzones"]["analog_r_stick"] = InputMap.deadzone_setting("analog_r_stick", 0.5)
	
	return input_map


func _input_event_to_string(event: InputEvent) -> String:
	"""
	Converts an InputEvent to a string representation.
	"""
	if event is InputEventKey:
		return "key/%s" % event.as_text_key_label()
	
	if event is InputEventMouseButton:
		return "mouse_button/%s" % event.button_index
	
	if event is InputEventJoypadButton:
		return "joy_button/%d" % event.button_index
	
	if event is InputEventJoypadMotion:
		return "joy_motion/%d/%s" % [event.axis, "+" if event.axis_value > 0 else "-"]
	
	if event is InputEventAction:
		return "action/%s" % event.action
	
	return "unknown"


func _collect_autoloads() -> Array:
	"""
	Collects autoload singletons.
	
	Returns:
		Array of autoload definitions
	"""
	var autoloads: Array = []
	
	if ProjectSettings.has_setting("autoload"):
		var autoload_settings: Dictionary = ProjectSettings.get_setting("autoload")
		
		for property: String in autoload_settings:
			var path: String = autoload_settings[property]
			var name: String = property
			
			# Extract name from path
			if "/" in path:
				name = path.get_file().get_basename()
			
			var autoload_info: Dictionary = {
				"name": name,
				"path": path,
				"enabled": true
			}
			
			autoloads.append(autoload_info)
	
	return autoloads


func _collect_project_info() -> Dictionary:
	"""
	Collects project information.
	
	Returns:
		Dictionary with project metadata
	"""
	var info: Dictionary = {
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"version": ProjectSettings.get_setting("application/config/version", ""),
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"orientation": ProjectSettings.get_setting("display/window/size/orientation", "landscape"),
		"width": ProjectSettings.get_setting("display/window/size/viewport_width", 1024),
		"height": ProjectSettings.get_setting("display/window/size/viewport_height", 600)
	}
	
	return info


## Utility Methods
## ==============

func get_snapshot_version() -> int:
	"""
	Returns the current snapshot version.
	"""
	return _snapshot_version


func is_dirty() -> bool:
	"""
	Returns whether the snapshot needs refreshing.
	"""
	return _is_dirty


func request_snapshot(data: Dictionary = {}) -> Dictionary:
	"""
	Requests a new snapshot with optional filters.
	
	Args:
		data: Request parameters
	
	Returns:
		Snapshot dictionary
	"""
	snapshot_requested.emit(data)
	return get_snapshot(data)
