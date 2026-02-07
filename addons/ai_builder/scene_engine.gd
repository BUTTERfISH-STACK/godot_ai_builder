@tool
extends Node

## Scene Engine for Godot AI Builder
## ==================================
## Handles all scene modification operations including node creation,
## property modification, script attachment, and scene management.

# Signal declarations
signal scene_modified(scene_path: String)
signal node_added(node_path: String, node_data: Dictionary)
signal node_deleted(node_path: String)
signal property_changed(node_path: String, property_name: String, value: Variant)
signal script_attached(node_path: String, script_path: String)
signal scene_saved(scene_path: String)
signal scene_error(error: Dictionary)

# Node type mappings for validation
const VALID_NODE_TYPES: Dictionary = {
	"root": ["Node3D", "Node2D", "Control", "Node"],
	"3d": ["Node3D", "StaticBody3D", "RigidBody3D", "CharacterBody3D", "Area3D",
		   "Camera3D", "DirectionalLight3D", "OmniLight3D", "SpotLight3D",
		   "MeshInstance3D", "CollisionShape3D", "NavigationRegion3D",
		   "GPUParticles3D", "CPUParticles3D", "WorldEnvironment",
		   "RayCast3D", "RemoteTransform3D"],
	"2d": ["Node2D", "StaticBody2D", "RigidBody2D", "CharacterBody2D", "Area2D",
		  "Sprite2D", "AnimatedSprite2D", "Camera2D", "DirectionalLight2D",
		  "PointLight2D", "CollisionShape2D", "Polygon2D", "Line2D",
		  "Path2D", "PathFollow2D", "TileMap", "TileMapLayer", "CanvasLayer",
		  "Control", "Button", "Label", "TextureRect", "Panel", "ProgressBar",
		  "HSlider", "VSlider", "CheckBox", "OptionButton", "LineEdit",
		  "TextEdit", "RichTextLabel", "TabContainer", "ScrollContainer"],
	"ui": ["Control", "Button", "Label", "TextureRect", "Panel", "ProgressBar",
		   "HSlider", "VSlider", "CheckBox", "OptionButton", "LineEdit",
		   "TextEdit", "RichTextLabel", "TabContainer", "ScrollContainer",
		   "Container", "VBoxContainer", "HBoxContainer", "GridContainer",
		   "CenterContainer", "AspectRatioContainer", "FlowContainer",
		   "ColorRect", "ReferenceRect", "Popup", "PopupMenu", "Dialog",
		   "Window", "SubViewportContainer", "SubViewport"],
	"physics": ["StaticBody3D", "RigidBody3D", "CharacterBody3D", "Area3D",
				"StaticBody2D", "RigidBody2D", "CharacterBody2D", "Area2D",
				"Joint3D", "Joint2D", "PinJoint3D", "PinJoint2D",
				"HingeJoint3D", "HingeJoint2D", "SliderJoint3D", "Generic6DOFJoint3D"],
	"audio": ["AudioStreamPlayer", "AudioStreamPlayer2D", "AudioStreamPlayer3D",
			 "AudioStreamPlayback", "AudioBusLayout"],
	"particles": ["GPUParticles3D", "CPUParticles3D", "GPUParticlesAttractor3D",
				 "GPUParticlesCollision3D", "GPUParticlesCollisionBox3D",
				 "GPUParticlesCollisionSphere3D", "GPUParticlesCollisionSDF3D"],
	"networking": ["WebSocketPeer", "WebSocketServer", "HTTPRequest",
				  "TCPServer", "StreamPeer", "NetworkedMultiplayerPeer"]
}

# Scene file extension
const SCENE_EXTENSION: String = ".tscn"

# Default parent paths
const DEFAULT_PARENTS: Dictionary = {
	"3d": "res://",
	"2d": "res://",
	"ui": "res://"
}

# Maximum scene depth
const MAX_SCENE_DEPTH: int = 100


## Public Methods
## =============

func create_scene(command: Dictionary) -> Dictionary:
	"""
	Creates a new scene with the specified configuration.
	
	Args:
		command: Dictionary containing:
			- name: String (required) - Name of the scene
			- parent_path: String (required) - Path to parent node
			- scene_type: String (optional) - Type of root node
			- save_path: String (optional) - Where to save the scene
			- metadata: Dictionary (optional) - Additional metadata
	
	Returns:
		Dictionary with keys:
			- status: "success" | "error"
			- scene_path: String (on success)
			- error: String (on error)
	"""
	var result: Dictionary = {
		"status": "error",
		"error": "",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Extract parameters
	var name: String = command.get("name", "")
	var parent_path: String = command.get("parent_path", "res://")
	var scene_type: String = command.get("scene_type", "Node3D")
	var save_path: String = command.get("save_path", "")
	var metadata: Dictionary = command.get("metadata", {})
	
	# Validate required fields
	if name.is_empty():
		result["error"] = "Scene name is required"
		scene_error.emit(result)
		return result
	
	# Validate node type
	if not _is_valid_node_type(scene_type):
		result["error"] = "Invalid scene type: %s" % scene_type
		scene_error.emit(result)
		return result
	
	# Create the root node
	var root_node: Node = _create_node_instance(scene_type, name)
	if root_node == null:
		result["error"] = "Failed to create node instance of type: %s" % scene_type
		scene_error.emit(result)
		return result
	
	# Set metadata if provided
	if not metadata.is_empty():
		_set_node_metadata(root_node, metadata)
	
	# Create scene from root node
	var scene: PackedScene = PackedScene.new()
	scene.pack(root_node)
	
	# Determine save path
	if save_path.is_empty():
		save_path = _generate_scene_path(name, parent_path)
	
	# Ensure directory exists
	var dir: DirAccess = DirAccess.open(save_path.get_base_dir())
	if dir == null:
		result["error"] = "Failed to access directory: %s" % save_path.get_base_dir()
		scene_error.emit(result)
		root_node.queue_free()
		return result
	
	# Save the scene
	var error: Error = ResourceSaver.save(scene, save_path)
	if error != OK:
		result["error"] = "Failed to save scene: %s (error code: %d)" % [save_path, error]
		scene_error.emit(result)
		root_node.queue_free()
		return result
	
	var scene_path: String = save_path
	
	print("[Scene Engine] Created scene: %s" % scene_path)
	
	# Emit signal
	scene_modified.emit(scene_path)
	
	result["status"] = "success"
	result["scene_path"] = scene_path
	result["root_node_type"] = scene_type
	result["root_node_name"] = name
	
	root_node.queue_free()
	return result


func add_node(command: Dictionary) -> Dictionary:
	"""
	Adds a new node to an existing scene.
	
	Args:
		command: Dictionary containing:
			- node_type: String (required) - Type of node to create
			- parent_path: String (required) - Path to parent node
			- name: String (required) - Name for the new node
			- position: Array (optional) - [x, y, z] position
			- rotation: Array (optional) - [x, y, z] rotation in degrees
			- scale: Array (optional) - [x, y, z] scale factors
			- properties: Dictionary (optional) - Properties to set
			- metadata: Dictionary (optional) - Additional metadata
	
	Returns:
		Dictionary with keys:
			- status: "success" | "error"
			- node_path: String (on success)
			- error: String (on error)
	"""
	var result: Dictionary = {
		"status": "error",
		"error": "",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Extract parameters
	var node_type: String = command.get("node_type", "")
	var parent_path: String = command.get("parent_path", "")
	var name: String = command.get("name", "")
	var position: Array = command.get("position", [])
	var rotation: Array = command.get("rotation", [])
	var scale: Array = command.get("scale", [])
	var properties: Dictionary = command.get("properties", {})
	var metadata: Dictionary = command.get("metadata", {})
	
	# Validate required fields
	if node_type.is_empty():
		result["error"] = "Node type is required"
		scene_error.emit(result)
		return result
	
	if parent_path.is_empty():
		result["error"] = "Parent path is required"
		scene_error.emit(result)
		return result
	
	if name.is_empty():
		result["error"] = "Node name is required"
		scene_error.emit(result)
		return result
	
	# Validate node type
	if not _is_valid_node_type(node_type):
		result["error"] = "Invalid node type: %s" % node_type
		scene_error.emit(result)
		return result
	
	# Get parent node
	var parent_node: Node = _get_node_by_path(parent_path)
	if parent_node == null:
		result["error"] = "Parent node not found: %s" % parent_path
		scene_error.emit(result)
		return result
	
	# Create the node
	var new_node: Node = _create_node_instance(node_type, name)
	if new_node == null:
		result["error"] = "Failed to create node instance: %s" % node_type
		scene_error.emit(result)
		return result
	
	# Set transform properties
	_set_node_transform(new_node, position, rotation, scale)
	
	# Set properties
	if not properties.is_empty():
		for prop_name: String in properties:
			var prop_result: Dictionary = _set_node_property(new_node, prop_name, properties[prop_name])
			if not prop_result.get("success", false):
				result["error"] = "Failed to set property '%s': %s" % [prop_name, prop_result.get("error", "")]
				scene_error.emit(result)
				new_node.queue_free()
				return result
	
	# Set metadata if provided
	if not metadata.is_empty():
		_set_node_metadata(new_node, metadata)
	
	# Add to parent
	parent_node.add_child(new_node)
	new_node.set_owner(parent_node.get_tree().edited_scene_root)
	
	# Generate node path
	var node_path: String = _generate_node_path(new_node, parent_path)
	
	print("[Scene Engine] Added node: %s (type: %s)" % [node_path, node_type])
	
	# Emit signal
	var node_data: Dictionary = {
		"type": node_type,
		"name": name,
		"parent_path": parent_path,
		"position": position,
		"rotation": rotation,
		"scale": scale,
		"properties": properties
	}
	node_added.emit(node_path, node_data)
	
	result["status"] = "success"
	result["node_path"] = node_path
	result["node_type"] = node_type
	
	return result


func set_property(command: Dictionary) -> Dictionary:
	"""
	Sets a property on an existing node.
	
	Args:
		command: Dictionary containing:
			- node_path: String (required) - Path to target node
			- property_name: String (required) - Name of property to set
			- value: Variant (required) - Value to set
			- property_type: String (optional) - Expected type of value
	
	Returns:
		Dictionary with keys:
			- status: "success" | "error"
			- node_path: String
			- property_name: String
			- error: String (on error)
	"""
	var result: Dictionary = {
		"status": "error",
		"error": "",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Extract parameters
	var node_path: String = command.get("node_path", "")
	var property_name: String = command.get("property_name", "")
	var value: Variant = command.get("value", null)
	
	# Validate required fields
	if node_path.is_empty():
		result["error"] = "Node path is required"
		scene_error.emit(result)
		return result
	
	if property_name.is_empty():
		result["error"] = "Property name is required"
		scene_error.emit(result)
		return result
	
	# Get target node
	var target_node: Node = _get_node_by_path(node_path)
	if target_node == null:
		result["error"] = "Node not found: %s" % node_path
		scene_error.emit(result)
		return result
	
	# Set the property
	var prop_result: Dictionary = _set_node_property(target_node, property_name, value)
	if not prop_result.get("success", false):
		result["error"] = "Failed to set property: %s" % prop_result.get("error", "")
		scene_error.emit(result)
		return result
	
	print("[Scene Engine] Set property '%s' on node: %s" % [property_name, node_path])
	
	property_changed.emit(node_path, property_name, value)
	
	result["status"] = "success"
	result["node_path"] = node_path
	result["property_name"] = property_name
	result["value"] = value
	
	return result


func attach_script(command: Dictionary) -> Dictionary:
	"""
	Attaches a script to an existing node.
	
	Args:
		command: Dictionary containing:
			- node_path: String (required) - Path to target node
			- script_path: String (required) - Path to script file
			- create_if_missing: bool (optional) - Create script if not exists
	
	Returns:
		Dictionary with keys:
			- status: "success" | "error"
			- node_path: String
			- script_path: String
			- error: String (on error)
	"""
	var result: Dictionary = {
		"status": "error",
		"error": "",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Extract parameters
	var node_path: String = command.get("node_path", "")
	var script_path: String = command.get("script_path", "")
	var create_if_missing: bool = command.get("create_if_missing", false)
	
	# Validate required fields
	if node_path.is_empty():
		result["error"] = "Node path is required"
		scene_error.emit(result)
		return result
	
	if script_path.is_empty():
		result["error"] = "Script path is required"
		scene_error.emit(result)
		return result
	
	# Get target node
	var target_node: Node = _get_node_by_path(node_path)
	if target_node == null:
		result["error"] = "Node not found: %s" % node_path
		scene_error.emit(result)
		return result
	
	# Check if script exists
	var script_exists: bool = ResourceLoader.exists(script_path)
	if not script_exists and create_if_missing:
		# Create an empty script
		var create_result: Dictionary = {
			"path": script_path,
			"name": script_path.get_file().get_basename(),
			"code": ""
		}
		var script_creation: Dictionary = _create_script_file(create_result)
		if script_creation.get("status") != "success":
			result["error"] = "Failed to create script: %s" % script_creation.get("error", "")
			scene_error.emit(result)
			return result
		script_exists = true
	
	if not script_exists:
		result["error"] = "Script not found: %s" % script_path
		scene_error.emit(result)
		return result
	
	# Load and attach the script
	var script: Script = load(script_path)
	if script == null:
		result["error"] = "Failed to load script: %s" % script_path
		scene_error.emit(result)
		return result
	
	target_node.set_script(script)
	
	print("[Scene Engine] Attached script '%s' to node: %s" % [script_path, node_path])
	
	script_attached.emit(node_path, script_path)
	
	result["status"] = "success"
	result["node_path"] = node_path
	result["script_path"] = script_path
	
	return result


func delete_node(command: Dictionary) -> Dictionary:
	"""
	Deletes a node from a scene.
	
	Args:
		command: Dictionary containing:
			- node_path: String (required) - Path to node to delete
			- recursive: bool (optional) - Delete children recursively
	
	Returns:
		Dictionary with keys:
			- status: "success" | "error"
			- deleted_node_path: String
			- error: String (on error)
	"""
	var result: Dictionary = {
		"status": "error",
		"error": "",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Extract parameters
	var node_path: String = command.get("node_path", "")
	var recursive: bool = command.get("recursive", true)
	
	# Validate required fields
	if node_path.is_empty():
		result["error"] = "Node path is required"
		scene_error.emit(result)
		return result
	
	# Get target node
	var target_node: Node = _get_node_by_path(node_path)
	if target_node == null:
		result["error"] = "Node not found: %s" % node_path
		scene_error.emit(result)
		return result
	
	# Store parent path for result
	var deleted_path: String = node_path
	
	# Get parent before deleting
	var parent: Node = target_node.get_parent()
	
	if recursive:
		target_node.queue_free()
	else:
		if target_node.get_child_count() > 0:
			result["error"] = "Cannot delete node with children (use recursive: true)"
			scene_error.emit(result)
			return result
		parent.remove_child(target_node)
		target_node.queue_free()
	
	print("[Scene Engine] Deleted node: %s" % deleted_path)
	
	node_deleted.emit(deleted_path)
	
	result["status"] = "success"
	result["deleted_node_path"] = deleted_path
	
	return result


func save_scene(command: Dictionary) -> Dictionary:
	"""
	Saves a scene to a file.
	
	Args:
		command: Dictionary containing:
			- scene_path: String (required) - Path to save the scene
			- node_path: String (optional) - Specific node to save (defaults to edited scene root)
	
	Returns:
		Dictionary with keys:
			- status: "success" | "error"
			- scene_path: String
			- error: String (on error)
	"""
	var result: Dictionary = {
		"status": "error",
		"error": "",
		"timestamp": Time.get_unix_time_from_system()
	}
	
	# Extract parameters
	var scene_path: String = command.get("scene_path", "")
	var node_path: String = command.get("node_path", "")
	
	# Validate required fields
	if scene_path.is_empty():
		result["error"] = "Scene path is required"
		scene_error.emit(result)
		return result
	
	# Get the node to save
	var node_to_save: Node
	
	if not node_path.is_empty():
		node_to_save = _get_node_by_path(node_path)
		if node_to_save == null:
			result["error"] = "Node not found: %s" % node_path
			scene_error.emit(result)
			return result
	else:
		node_to_save = get_tree().edited_scene_root
		if node_to_save == null:
			result["error"] = "No edited scene root available"
			scene_error.emit(result)
			return result
	
	# Ensure directory exists
	var dir_path: String = scene_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir_path):
		var dir: DirAccess = DirAccess.open(dir_path)
		if dir == null:
			result["error"] = "Failed to create directory: %s" % dir_path
			scene_error.emit(result)
			return result
	
	# Create packed scene
	var scene: PackedScene = PackedScene.new()
	var error: Error = scene.pack(node_to_save)
	if error != OK:
		result["error"] = "Failed to pack scene: %d" % error
		scene_error.emit(result)
		return result
	
	# Save the scene
	error = ResourceSaver.save(scene, scene_path)
	if error != OK:
		result["error"] = "Failed to save scene: %s (error: %d)" % [scene_path, error]
		scene_error.emit(result)
		return result
	
	print("[Scene Engine] Saved scene: %s" % scene_path)
	
	scene_saved.emit(scene_path)
	
	result["status"] = "success"
	result["scene_path"] = scene_path
	
	return result


## Node Query Methods
## =================

func get_scene_tree(command: Dictionary = {}) -> Array:
	"""
	Returns the current scene tree as an array of node descriptions.
	
	Args:
		command: Optional parameters for filtering
	
	Returns:
		Array of dictionaries describing each node
	"""
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return []
	
	var tree: Array = []
	_recursive_build_tree(root, "", tree, 0)
	return tree


func get_node_info(node_path: String) -> Dictionary:
	"""
	Returns information about a specific node.
	
	Args:
		node_path: Path to the node
	
	Returns:
		Dictionary containing node information
	"""
	var node: Node = _get_node_by_path(node_path)
	if node == null:
		return {}
	
	return _build_node_info(node)


## Internal Helper Methods
## ======================

func _is_valid_node_type(node_type: String) -> bool:
	"""
	Checks if a node type is valid and instantiable.
	"""
	if VALID_NODE_TYPES.is_empty():
		return true  # Skip validation if not set up
	
	for category: String in VALID_NODE_TYPES:
		if node_type in VALID_NODE_TYPES[category]:
			return true
	
	# Allow any built-in Godot type that's instantiable
	if node_type.begins_with("Node"):
		return true
	
	return false


func _create_node_instance(node_type: String, name: String) -> Node:
	"""
	Creates an instance of a node type.
	"""
	var node: Node
	
	# Try using Godot's class loading
	var class_id: StringName = node_type
	if ClassDB.can_instantiate(class_id):
		node = ClassDB.instantiate(class_id)
		if node != null:
			node.name = name
			return node
	
	# Try using TypeDB for engine classes
	var type_db: TypedArray = TypeDB.get_instance_list(node_type)
	if not type_db.is_empty():
		# Fallback: try to create using the constructor
		pass
	
	# Try using built-in types directly
	match node_type:
		"Node3D":
			node = Node3D.new()
		"Node2D":
			node = Node2D.new()
		"Control":
			node = Control.new()
		"Node":
			node = Node.new()
		"StaticBody3D":
			node = StaticBody3D.new()
		"RigidBody3D":
			node = RigidBody3D.new()
		"CharacterBody3D":
			node = CharacterBody3D.new()
		"Area3D":
			node = Area3D.new()
		"Camera3D":
			node = Camera3D.new()
		"DirectionalLight3D":
			node = DirectionalLight3D.new()
		"MeshInstance3D":
			node = MeshInstance3D.new()
		"CollisionShape3D":
			node = CollisionShape3D.new()
		"Sprite2D":
			node = Sprite2D.new()
		"AnimatedSprite2D":
			node = AnimatedSprite2D.new()
		"Camera2D":
			node = Camera2D.new()
		"StaticBody2D":
			node = StaticBody2D.new()
		"RigidBody2D":
			node = RigidBody2D.new()
		_:
			# Try using script class
			var script_class: Script = load(node_type + ".gd") as Script
			if script_class != null:
				node = script_class.new()
	
	if node != null:
		node.name = name
	
	return node


func _get_node_by_path(path: String) -> Node:
	"""
	Gets a node by its path string.
	"""
	if path.is_empty() or path == "res://":
		return get_tree().edited_scene_root
	
	# Try using get_node with the path
	var root: Node = get_tree().edited_scene_root
	if root == null:
		return null
	
	# Handle special paths
	if path == ".":
		return root
	
	# Convert Godot path notation to actual path
	var node_path: NodePath = NodePath(path)
	var node: Node = root.get_node(node_path)
	return node


func _generate_node_path(node: Node, parent_path: String) -> String:
	"""
	Generates a unique path string for a node.
	"""
	var path: String = parent_path
	
	if not parent_path.ends_with("/"):
		path += "/"
	
	path += node.name
	
	return path


func _generate_scene_path(name: String, parent_path: String) -> String:
	"""
	Generates a path for saving a new scene.
	"""
	var base_path: String = parent_path
	if base_path.is_empty() or base_path == "res://":
		base_path = "res://scenes"
	
	if not base_path.ends_with("/"):
		base_path += "/"
	
	var sanitized_name: String = name.replace(" ", "_").replace("/", "_")
	return base_path + sanitized_name + SCENE_EXTENSION


func _set_node_transform(node: Node, position: Array, rotation: Array, scale: Array) -> void:
	"""
	Sets transform properties on a node.
	"""
	match typeof(node):
		TYPE_NODE_PATH:
			pass  # Skip
		
		_:
			if position.size() >= 3 and node.has_method("set_position"):
				node.set_position(Vector3(position[0], position[1], position[2]))
			
			if rotation.size() >= 3 and node.has_method("set_rotation_degrees"):
				node.set_rotation_degrees(Vector3(rotation[0], rotation[1], rotation[2]))
			
			if scale.size() >= 3 and node.has_method("set_scale"):
				node.set_scale(Vector3(scale[0], scale[1], scale[2]))


func _set_node_property(node: Node, property_name: String, value: Variant) -> Dictionary:
	"""
	Sets a property on a node.
	"""
	var result: Dictionary = {
		"success": false,
		"error": ""
	}
	
	if node == null:
		result["error"] = "Node is null"
		return result
	
	# Check if property exists
	if not node.has_property(property_name):
		result["error"] = "Property '%s' not found on node type: %s" % [property_name, node.get_class()]
		return result
	
	# Try to set the property
	if node.get(property_name) != null or value != null:
		# Check if value type is compatible
		var current_type: int = typeof(node.get(property_name))
		var new_type: int = typeof(value)
		
		if current_type != new_type and current_type != TYPE_NIL and new_type != TYPE_NIL:
			# Try type conversion
			value = _convert_value(value, current_type)
	
	node.set(property_name, value)
	
	result["success"] = true
	return result


func _convert_value(value: Variant, target_type: int) -> Variant:
	"""
	Attempts to convert a value to a target type.
	"""
	match target_type:
		TYPE_FLOAT:
			return float(value)
		TYPE_INT:
			return int(value)
		TYPE_STRING:
			return str(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_VECTOR2:
			if typeof(value) == TYPE_ARRAY and value.size() >= 2:
				return Vector2(float(value[0]), float(value[1]))
		TYPE_VECTOR3:
			if typeof(value) == TYPE_ARRAY and value.size() >= 3:
				return Vector3(float(value[0]), float(value[1]), float(value[2]))
		TYPE_COLOR:
			if typeof(value) == TYPE_ARRAY and value.size() >= 4:
				return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
	
	return value


func _set_node_metadata(node: Node, metadata: Dictionary) -> void:
	"""
	Sets metadata on a node.
	"""
	if not node.has_meta("ai_builder_metadata"):
		node.set_meta("ai_builder_metadata", {})
	
	var existing_meta: Dictionary = node.get_meta("ai_builder_metadata")
	for key: Variant in metadata:
		if typeof(key) == TYPE_STRING:
			existing_meta[key] = metadata[key]
	
	node.set_meta("ai_builder_metadata", existing_meta)


func _recursive_build_tree(node: Node, prefix: String, tree: Array, depth: int) -> void:
	"""
	Recursively builds the scene tree representation.
	"""
	if depth >= MAX_SCENE_DEPTH:
		return  # Prevent infinite recursion
	
	var node_path: String
	if prefix.is_empty():
		node_path = node.name
	else:
		node_path = prefix + "/" + node.name
	
	var node_info: Dictionary = _build_node_info(node)
	node_info["path"] = node_path
	node_info["depth"] = depth
	tree.append(node_info)
	
	for child: Node in node.get_children():
		_recursive_build_tree(child, node_path, tree, depth + 1)


func _build_node_info(node: Node) -> Dictionary:
	"""
	Builds a dictionary with information about a node.
	"""
	var info: Dictionary = {
		"name": node.name,
		"type": node.get_class(),
		"script": "",
		"children": node.get_child_count()
	}
	
	# Get script if attached
	var script: Script = node.get_script()
	if script != null:
		info["script"] = script.resource_path if script.resource_path else ""
	
	# Add transform info if applicable
	if node is Node3D:
		info["position"] = [node.position.x, node.position.y, node.position.z]
		info["rotation"] = [node.rotation_degrees.x, node.rotation_degrees.y, node.rotation_degrees.z]
		info["scale"] = [node.scale.x, node.scale.y, node.scale.z]
	elif node is Node2D:
		info["position"] = [node.position.x, node.position.y]
		info["rotation"] = [node.rotation_degrees]
		info["scale"] = [node.scale.x, node.scale.y]
	
	return info
