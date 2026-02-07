// Vercel API endpoint - POST /api/commands

export default async function handler(req, res) {
    if (req.method !== 'POST') {
        return res.status(405).json({
            status: 'error',
            error: 'Method not allowed',
            message: 'Use POST method to send commands'
        });
    }

    const command = req.body;

    if (!command || !command.action) {
        return res.status(400).json({
            status: 'error',
            error: 'Invalid command',
            message: 'Command must include an "action" field'
        });
    }

    try {
        const simulatedResponse = simulateCommand(command);
        res.status(200).json(simulatedResponse);
    } catch (error) {
        console.error('Command execution error:', error);
        res.status(500).json({
            status: 'error',
            error: 'Command execution failed',
            message: error.message
        });
    }
}

function simulateCommand(command) {
    const action = command.action;
    const timestamp = Date.now() / 1000;
    
    switch (action) {
        case 'get_status':
            return {
                status: 'success',
                plugin_version: '1.0.0',
                protocol_version: '1.0.0',
                server_running: false,
                note: 'Connect to local Godot Editor for full functionality'
            };
            
        case 'get_snapshot':
            return {
                status: 'success',
                version: 1,
                timestamp: timestamp,
                scene_tree: { '/root': { type: 'Node', children: [] } },
                scripts: {},
                note: 'Demo mode - connect Godot Editor for real data'
            };
            
        case 'get_performance':
            return {
                status: 'success',
                fps: 60.0,
                draw_calls: 1500,
                node_count: 250,
                memory_usage_mb: 128.5,
                physics_time_ms: 8.5,
                note: 'Demo mode - connect Godot Editor for real data'
            };
            
        case 'create_scene':
            return {
                status: 'success',
                action: 'create_scene',
                scene_path: command.save_path || 'res://scenes/' + (command.name || 'scene').toLowerCase() + '.tscn',
                root_node_type: command.scene_type || 'Node3D',
                root_node_name: command.name,
                note: 'Demo mode - scene not actually created'
            };
            
        case 'add_node':
            return {
                status: 'success',
                action: 'add_node',
                node_type: command.node_type,
                node_path: (command.parent_path || '/root') + '/' + (command.name || 'Node'),
                note: 'Demo mode - node not actually added'
            };
            
        case 'create_script':
            return {
                status: 'success',
                action: 'create_script',
                path: command.path,
                class_name: command.name,
                base_class: command.base_class || 'Node',
                note: 'Demo mode - script not actually created'
            };
            
        default:
            return {
                status: 'success',
                action: action,
                note: 'Demo mode - command not executed on actual Godot Editor'
            };
    }
}
