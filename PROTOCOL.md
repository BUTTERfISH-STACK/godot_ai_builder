# Godot AI Builder - Structured JSON Command Protocol
## ==================================================

This document describes the structured JSON command protocol used for communication between the AI Control Server and the Godot Editor Plugin.

---

## Connection

**WebSocket Endpoint**: `ws://localhost:8765/ai_builder`

**Protocol Version**: 1.0.0

---

## Command Structure

All commands must be valid JSON objects with the following structure:

```json
{
    "action": "action_name",
    "auto_run": false,
    "request_id": "optional_request_id",
    // Action-specific parameters
}
```

### Common Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `action` | String | Yes | The action to perform |
| `auto_run` | Boolean | No | Whether to automatically run the scene after modification |
| `request_id` | String | No | Unique request identifier for tracking |

---

## Supported Actions

### 1. create_scene

Creates a new scene with a specified root node.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | String | Yes | Name of the scene |
| `parent_path` | String | Yes | Path to parent node |
| `scene_type` | String | No | Type of root node (default: "Node3D") |
| `save_path` | String | No | Path to save the scene |

**Example**:
```json
{
    "action": "create_scene",
    "name": "MainScene",
    "parent_path": "res://",
    "scene_type": "Node3D",
    "save_path": "res://scenes/main.tscn"
}
```

**Response**:
```json
{
    "status": "success",
    "scene_path": "res://scenes/main.tscn",
    "root_node_type": "Node3D",
    "root_node_name": "MainScene"
}
```

---

### 2. add_node

Adds a new node to an existing scene.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `node_type` | String | Yes | Type of node to create |
| `parent_path` | String | Yes | Path to parent node |
| `name` | String | Yes | Name for the new node |
| `position` | Array | No | [x, y, z] position |
| `rotation` | Array | No | [x, y, z] rotation in degrees |
| `scale` | Array | No | [x, y, z] scale factors |
| `properties` | Object | No | Properties to set |

**Example**:
```json
{
    "action": "add_node",
    "node_type": "CharacterBody3D",
    "parent_path": "/root/MainScene",
    "name": "Player",
    "position": [0, 1, 0]
}
```

---

### 3. set_property

Sets a property on an existing node.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `node_path` | String | Yes | Path to target node |
| `property_name` | String | Yes | Name of property to set |
| `value` | Variant | Yes | Value to set |

**Example**:
```json
{
    "action": "set_property",
    "node_path": "/root/MainScene/Player",
    "property_name": "speed",
    "value": 5.0
}
```

---

### 4. attach_script

Attaches a script to an existing node.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `node_path` | String | Yes | Path to target node |
| `script_path` | String | Yes | Path to script file |
| `create_if_missing` | Boolean | No | Create script if not exists |

**Example**:
```json
{
    "action": "attach_script",
    "node_path": "/root/MainScene/Player",
    "script_path": "res://scripts/player.gd"
}
```

---

### 5. create_script

Creates a new GDScript file.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | String | Yes | Path for the new script |
| `name` | String | Yes | Script class name |
| `code` | String | No | Full script code |
| `base_class` | String | No | Class to extend (default: "Node") |
| `template` | String | No | Template code to use |

**Example**:
```json
{
    "action": "create_script",
    "path": "res://scripts/inventory.gd",
    "name": "Inventory",
    "base_class": "Node",
    "code": "extends Node\\n\\nvar items = []"
}
```

---

### 6. modify_script

Modifies an existing script.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `path` | String | Yes | Path to the script |
| `modifications` | Object | Yes | Modifications to apply |
| `replace_all` | Boolean | No | Replace entire code vs patch |
| `code` | String | No | Complete replacement code |

**Modifications Object**:

| Field | Type | Description |
|-------|------|-------------|
| `extends` | String | Change base class |
| `add_methods` | Array | Add new methods |
| `modify_method` | Object | Modify existing method |
| `add_variables` | Array | Add member variables |
| `add_constants` | Array | Add constants |
| `add_signals` | Array | Add signal declarations |

**Example**:
```json
{
    "action": "modify_script",
    "path": "res://scripts/player.gd",
    "modifications": {
        "add_methods": [
            {
                "name": "jump",
                "return_type": "void",
                "body": "print(\\\"Jumping!\\\")"
            }
        ]
    }
}
```

---

### 7. delete_node

Deletes a node from a scene.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `node_path` | String | Yes | Path to node to delete |
| `recursive` | Boolean | No | Delete children recursively (default: true) |

**Example**:
```json
{
    "action": "delete_node",
    "node_path": "/root/MainScene/TempNode",
    "recursive": true
}
```

---

### 8. run_scene

Runs a scene.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `scene_path` | String | Yes | Path to scene |
| `wait_for_completion` | Boolean | No | Wait for execution |
| `timeout` | Number | No | Execution timeout in seconds |

**Example**:
```json
{
    "action": "run_scene",
    "scene_path": "res://scenes/main.tscn",
    "timeout": 300
}
```

---

### 9. save_scene

Saves a scene to a file.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `scene_path` | String | Yes | Path to save the scene |
| `node_path` | String | No | Specific node to save |

**Example**:
```json
{
    "action": "save_scene",
    "scene_path": "res://scenes/main.tscn"
}
```

---

### 10. get_snapshot

Gets the current project snapshot.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `include_scenes` | Boolean | No | Include scene tree |
| `include_scripts` | Boolean | No | Include script list |
| `include_input` | Boolean | No | Include input map |
| `include_autoloads` | Boolean | No | Include autoloads |
| `depth` | Number | No | Node traversal depth |

**Example**:
```json
{
    "action": "get_snapshot",
    "include_scenes": true,
    "include_scripts": true
}
```

**Response**:
```json
{
    "status": "success",
    "version": 1,
    "timestamp": 1234567890.0,
    "scene_tree": [...],
    "scripts": {...},
    "input_map": {...},
    "autoloads": [...]
}
```

---

### 11. get_performance

Gets performance metrics.

**Example**:
```json
{
    "action": "get_performance"
}
```

**Response**:
```json
{
    "status": "success",
    "fps": 60.0,
    "draw_calls": 1500,
    "node_count": 250,
    "memory_usage_mb": 128.5,
    "physics_time_ms": 8.5
}
```

---

### 12. retry

Retries a failed command.

**Parameters**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `original_command` | Object | Yes | Original command to retry |

**Example**:
```json
{
    "action": "retry",
    "original_command": {
        "action": "create_script",
        "path": "res://scripts/test.gd",
        "name": "Test"
    }
}
```

---

### 13. get_status

Gets plugin status.

**Example**:
```json
{
    "action": "get_status"
}
```

**Response**:
```json
{
    "status": "success",
    "plugin_version": "1.0.0",
    "protocol_version": "1.0.0",
    "server_running": true,
    "project_path": "res://",
    "retry_count": 0,
    "error_count": 5
}
```

---

### 14. get_protocol

Gets protocol documentation.

**Example**:
```json
{
    "action": "get_protocol"
}
```

---

## Error Response Format

All errors return the following structure:

```json
{
    "status": "error",
    "type": "compile | runtime | parse | security | execution",
    "message": "Human-readable error message",
    "file": "path/to/file",
    "line": 123,
    "column": 45,
    "stack": "Stack trace if available",
    "correction_hints": ["Hint 1", "Hint 2"],
    "timestamp": 1234567890.0
}
```

### Error Types

| Type | Description |
|------|-------------|
| `compile` | Script compilation error |
| `runtime` | Runtime execution error |
| `parse` | JSON parsing error |
| `security` | Security validation failure |
| `execution` | Scene execution error |
| `unknown_action` | Unsupported action |

---

## Performance Thresholds

The system monitors the following performance metrics:

| Metric | Warning | Critical |
|--------|---------|----------|
| FPS | < 45 | < 30 |
| Draw Calls | > 3000 | > 5000 |
| Node Count | > 1500 | > 2000 |
| Memory (MB) | N/A | > 512 |

---

## Self-Correcting Loop

When an error occurs:

1. The error is captured and logged
2. The error details are sent to the AI
3. The AI generates a correction
4. The command is retried (up to 5 times)
5. If still failing, the process is aborted

---

## Usage Example

```python
import asyncio
import json
import websockets

async def main():
    async with websockets.connect("ws://localhost:8765/ai_builder") as ws:
        # Create a scene
        await ws.send(json.dumps({
            "action": "create_scene",
            "name": "TestScene",
            "scene_type": "Node3D"
        }))
        
        response = json.loads(await ws.recv())
        print(response)
        
        # Add a player
        await ws.send(json.dumps({
            "action": "add_node",
            "node_type": "CharacterBody3D",
            "parent_path": "/root/TestScene",
            "name": "Player",
            "position": [0, 1, 0]
        }))
        
        response = json.loads(await ws.recv())
        print(response)

asyncio.run(main())
```

---

## Security

- All commands are validated for path traversal attacks
- JSON schema validation ensures command structure integrity
- Filesystem operations are restricted to project directory
- Dangerous patterns are rejected (shell commands, URL schemes, etc.)

---

## Protocol Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-01 | Initial protocol specification |
