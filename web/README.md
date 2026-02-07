# Godot AI Builder - Web Interface

A modern web interface for controlling the Godot AI Builder plugin remotely.

## Features

- 🔗 **WebSocket Connection** - Connect to your local Godot Editor
- 🎮 **Quick Actions** - Common operations at your fingertips
- 📝 **Command Builder** - Build complex commands with ease
- 📊 **Performance Monitoring** - Track FPS, draw calls, and more
- 📜 **Command History** - Keep track of your commands
- 🎨 **Game Builder** - Describe your game in natural language

## Getting Started

### Local Development

1. Open `index.html` in your browser
2. Make sure your Godot Editor is running with the AI Builder addon
3. Click "Connect" to establish a WebSocket connection
4. Start sending commands!

### Vercel Deployment

This project is ready for deployment on Vercel:

1. Push this folder to a GitHub repository
2. Import the project in Vercel
3. Deploy!

The Vercel deployment includes:
- Static frontend files
- Serverless API endpoints (`/api/status`, `/api/commands`)

**Note:** Full functionality requires the Godot Editor to be running locally with the AI Builder addon.

## Project Structure

```
web/
├── index.html          # Main HTML page
├── styles.css          # CSS styles
├── app.js              # Main application logic
├── websocket.js        # WebSocket client
├── api.js             # REST API client
├── vercel.json        # Vercel configuration
├── package.json       # Node.js configuration
├── api/
│   ├── status.js      # GET /api/status
│   └── commands.js    # POST /api/commands
└── README.md          # This file
```

## Usage

### Connecting to Godot

1. Start Godot Editor
2. Enable the AI Builder addon
3. The addon starts a WebSocket server on `ws://localhost:8765`
4. Enter the URL in the web interface and click "Connect"

### Sending Commands

1. Select an action from the dropdown
2. Fill in the required parameters
3. Click "Send Command"

### Quick Actions

Use quick actions for common operations:
- Create Scene
- Get Snapshot
- Performance
- Status

### Templates

Pre-configured templates for:
- Adding a player character
- Adding a camera
- Adding a light
- Creating a script

## API Reference

### WebSocket Protocol

Connect to: `ws://localhost:8765`

Commands are JSON objects:
```json
{
    "action": "create_scene",
    "name": "MainScene",
    "scene_type": "Node3D",
    "auto_run": false
}
```

### Supported Actions

- `create_scene` - Create a new scene
- `add_node` - Add a node to a scene
- `set_property` - Set a property on a node
- `attach_script` - Attach a script to a node
- `create_script` - Create a new script
- `modify_script` - Modify an existing script
- `delete_node` - Delete a node
- `run_scene` - Run a scene
- `save_scene` - Save a scene
- `get_snapshot` - Get project snapshot
- `get_performance` - Get performance metrics
- `get_status` - Get plugin status
- `get_protocol` - Get protocol documentation

## License

MIT
