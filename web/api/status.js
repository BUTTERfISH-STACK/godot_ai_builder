// Vercel API endpoint - GET /api/status

export default function handler(req, res) {
    res.status(200).json({
        status: 'success',
        service: 'Godot AI Builder',
        version: '1.0.0',
        endpoints: {
            websocket: 'ws://localhost:8765 (local Godot Editor)',
            rest: '/api/commands'
        },
        note: 'This is a static frontend. For full functionality, run the Godot Editor with the AI Builder addon and the local Python server.'
    });
}
