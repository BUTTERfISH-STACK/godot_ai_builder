/**
 * API Integration for Godot AI Builder
 * Provides REST API endpoints for Vercel deployment
 */

class API {
    constructor(baseUrl = '') {
        this.baseUrl = baseUrl;
        this.timeout = 30000;
    }

    /**
     * Make an API request
     */
    async request(endpoint, options = {}) {
        const url = `${this.baseUrl}${endpoint}`;
        
        const config = {
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            timeout: this.timeout,
            ...options
        };
        
        try {
            const response = await fetch(url, config);
            
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            return await response.json();
            
        } catch (error) {
            console.error(`API request failed: ${endpoint}`, error);
            throw error;
        }
    }

    /**
     * Get server status
     */
    async getStatus() {
        return this.request('/api/status');
    }

    /**
     * Get protocol documentation
     */
    async getProtocol() {
        return this.request('/api/protocol');
    }

    /**
     * Create a new scene
     */
    async createScene(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'create_scene',
                ...params
            })
        });
    }

    /**
     * Add a node to a scene
     */
    async addNode(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'add_node',
                ...params
            })
        });
    }

    /**
     * Set a property on a node
     */
    async setProperty(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'set_property',
                ...params
            })
        });
    }

    /**
     * Create a script
     */
    async createScript(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'create_script',
                ...params
            })
        });
    }

    /**
     * Modify an existing script
     */
    async modifyScript(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'modify_script',
                ...params
            })
        });
    }

    /**
     * Attach a script to a node
     */
    async attachScript(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'attach_script',
                ...params
            })
        });
    }

    /**
     * Delete a node
     */
    async deleteNode(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'delete_node',
                ...params
            })
        });
    }

    /**
     * Run a scene
     */
    async runScene(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'run_scene',
                ...params
            })
        });
    }

    /**
     * Save a scene
     */
    async saveScene(params) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'save_scene',
                ...params
            })
        });
    }

    /**
     * Get a snapshot of the current project
     */
    async getSnapshot(params = {}) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'get_snapshot',
                ...params
            })
        });
    }

    /**
     * Get performance metrics
     */
    async getPerformance() {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'get_performance'
            })
        });
    }

    /**
     * Get command status
     */
    async getStatusCommand() {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'get_status'
            })
        });
    }

    /**
     * Get protocol info
     */
    async getProtocolCommand() {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify({
                action: 'get_protocol'
            })
        });
    }

    /**
     * Send a raw command
     */
    async sendCommand(command) {
        return this.request('/api/commands', {
            method: 'POST',
            body: JSON.stringify(command)
        });
    }
}

// Export for use in other modules
window.API = API;
