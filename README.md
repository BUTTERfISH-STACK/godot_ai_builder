# Godot 4 Autonomous AI Builder

A production-ready autonomous AI game builder for Godot 4 that enables AI-driven game development through structured JSON commands, self-correcting error handling, and automated scene management.

## 🚀 Features

### Core Capabilities
- **AI-Generated Scene Creation** - Create scenes programmatically with any node type
- **AI-Generated Script Creation** - Write and modify GDScript files
- **Automatic Execution** - Scenes run automatically after modifications
- **Live Editor Updates** - Changes reflected immediately in Godot Editor
- **Automatic Test-Run** - Scenes tested after each modification
- **Compile-Time Error Capture** - Immediate feedback on syntax errors
- **Runtime Error Capture** - Catch and report runtime exceptions
- **Structured Error Feedback Loop** - Comprehensive error information for AI correction

### Self-Correcting Engine
- **Automatic Script Rewriting** - AI can rewrite scripts based on errors
- **Retry Control Logic** - Up to 5 retry attempts before aborting
- **Error Categorization** - Types: compile, runtime, parse, security, execution

### Performance Monitoring
- **FPS Monitoring** - Track frame rate performance
- **Draw Call Tracking** - Monitor rendering performance
- **Node Count Analysis** - Detect scene complexity issues
- **Optimization Recommendations** - AI suggestions for improvements

### Security
- **Localhost Only** - No external network access
- **Path Validation** - Prevent filesystem traversal attacks
- **JSON Schema Validation** - Ensure command integrity
- **Dangerous Pattern Detection** - Reject malicious input

---

## 📁 Project Structure

```
godot_ai_builder/
├── plugin.cfg                    # Godot Plugin configuration
├── README.md                     # This file
├── PROTOCOL.md                   # JSON Command Protocol documentation
│
├── addons/ai_builder/
│   ├── plugin.gd                 # Main plugin script
│   ├── websocket_server.gd       # WebSocket communication layer
│   ├── command_parser.gd         # JSON command validation
│   ├── security_validator.gd    # Security validation
│   ├── scene_engine.gd           # Scene modification engine
│   ├── script_engine.gd          # Script creation & modification
│   ├── error_handler.gd          # Error capture & processing
│   ├── runtime_monitor.gd        # Runtime monitoring
│   ├── auto_runner.gd           # Automatic scene execution
│   ├── performance_monitor.gd   # Performance metrics
│   └── snapshot_system.gd        # Project context snapshots
│
└── ai_server/
    ├── godot_ai_server.py        # Local AI Control Server (Python)
    └── requirements.txt          # Python dependencies
```

---

## 🔧 Installation

### 1. Install Godot Plugin

1. Copy the `godot_ai_builder/addons/ai_builder` folder to your Godot project's `addons/` directory
2. The final path should be: `[YourProject]/addons/ai_builder/`
3. Restart Godot or reload the project
4. Enable the plugin: **Project → Project Settings → Plugins → Godot AI Builder**
5. Click "Enable" to activate

### 2. Install Python Server Dependencies

```bash
cd godot_ai_builder/ai_server
pip install -r requirements.txt
```

**Requirements**:
- Python 3.7+
- websockets >= 10.0

---

## 🎮 Usage

### Starting the AI Server

```bash
cd godot_ai_builder/ai_server
python godot_ai_server.py --mode builder
```

### Connecting from Your AI

```python
import asyncio
import json
import websockets

async def main():
    async with websockets.connect("ws://localhost:8765/ai_builder") as ws:
        # Create a scene
        await ws.send(json.dumps({
            "action": "create_scene",
            "name": "MainScene",
            "scene_type": "Node3D",
            "save_path": "res://scenes/main.tscn"
        }))
        
        response = json.loads(await ws.recv())
        print(f"Response: {response}")

asyncio.run(main())
```

### Example: Creating a Third-Person Game

```python
import asyncio
from godot_ai_server import GameBuilder

async def main():
    builder = GameBuilder()
    
    if await builder.connect():
        # Create a third-person survival game
        result = await builder.create_game(
            "Create a third-person survival game with inventory and day/night cycle"
        )
        print(f"Success: {result['success']}")
        
        await builder.disconnect()

asyncio.run(main())
```

---

## 📡 Command Reference

| Command | Description |
|---------|-------------|
| `create_scene` | Create a new scene with specified root node |
| `add_node` | Add a node to an existing scene |
| `set_property` | Set a property on a node |
| `attach_script` | Attach a script to a node |
| `create_script` | Create a new GDScript file |
| `modify_script` | Modify an existing script |
| `delete_node` | Delete a node from a scene |
| `run_scene` | Execute a scene |
| `save_scene` | Save a scene to file |
| `get_snapshot` | Get project context snapshot |
| `get_performance` | Get performance metrics |
| `retry` | Retry a failed command |
| `get_status` | Get plugin status |
| `get_protocol` | Get protocol documentation |

See [PROTOCOL.md](PROTOCOL.md) for detailed command documentation.

---

## 🔄 Self-Correcting Loop

When an error occurs:

1. **Error Capture** - The plugin captures the error with full context
2. **AI Notification** - Error details sent to AI via WebSocket
3. **Correction Generation** - AI generates corrected command
4. **Retry** - Command retried (up to 5 times)
5. **Abort** - If still failing after 5 attempts, process aborted

### Error Response Format

```json
{
    "status": "error",
    "type": "compile",
    "message": "Unexpected token at line 5",
    "file": "res://scripts/player.gd",
    "line": 5,
    "column": 12,
    "correction_hints": [
        "Check for missing semicolon",
        "Verify all brackets are closed"
    ]
}
```

---

## 📊 Performance Monitoring

The system monitors:

| Metric | Warning | Critical |
|--------|---------|----------|
| FPS | < 45 | < 30 |
| Draw Calls | > 3000 | > 5000 |
| Node Count | > 1500 | > 2000 |
| Memory | N/A | > 512 MB |

### Getting Performance Data

```json
{
    "action": "get_performance"
}
```

Response:
```json
{
    "status": "success",
    "fps": 60.0,
    "draw_calls": 1500,
    "node_count": 250,
    "memory_usage_mb": 128.5
}
```

---

## 🛡️ Security Features

- **Path Validation** - Prevents `../` directory traversal
- **JSON Schema Validation** - Ensures command structure
- **Dangerous Pattern Detection** - Rejects shell commands, URLs
- **Localhost Only** - No external network connections
- **Project Directory Restriction** - All file operations within project

---

## 📋 Requirements

- **Godot 4.0+**
- **Python 3.7+** (for AI server)
- **Windows 10/11** (tested on Windows)

---

## 🚧 Current Limitations

- Single-user only (local execution)
- No cloud integration
- Limited to Godot 4.x
- Windows only tested

---

## 📝 License

This project is for personal internal use only.

---

## 🤝 Contributing

This is a personal/internal project. For issues or questions, contact the project maintainer.

---

## 📞 Support

- Check [PROTOCOL.md](PROTOCOL.md) for command documentation
- Review error responses for correction hints
- Enable debug logging in Godot console
