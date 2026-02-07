/**
 * WebSocket Client for Godot AI Builder
 * Handles bidirectional communication with the AI server
 */

class WebSocketClient {
    constructor(url) {
        this.url = url;
        this.ws = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 2000;
        this.messageQueue = [];
        this.handlers = {
            open: [],
            close: [],
            error: [],
            message: []
        };
        this.isConnected = false;
    }

    /**
     * Connect to the WebSocket server
     */
    connect() {
        return new Promise((resolve, reject) => {
            try {
                this.ws = new WebSocket(this.url);

                this.ws.onopen = (event) => {
                    this.isConnected = true;
                    this.reconnectAttempts = 0;
                    this._dispatch('open', event);
                    this._flushMessageQueue();
                    resolve(event);
                };

                this.ws.onclose = (event) => {
                    this.isConnected = false;
                    this._dispatch('close', event);
                    this._handleReconnect();
                };

                this.ws.onerror = (event) => {
                    this._dispatch('error', event);
                    reject(new Error('WebSocket error'));
                };

                this.ws.onmessage = (event) => {
                    try {
                        const data = JSON.parse(event.data);
                        this._dispatch('message', data);
                    } catch (e) {
                        console.warn('Failed to parse message:', event.data);
                        this._dispatch('message', { raw: event.data });
                    }
                };
            } catch (error) {
                reject(error);
            }
        });
    }

    /**
     * Disconnect from the WebSocket server
     */
    disconnect() {
        if (this.ws) {
            this.ws.close();
            this.ws = null;
            this.isConnected = false;
        }
    }

    /**
     * Send a message to the server
     * @param {Object} message - Message object to send
     */
    send(message) {
        if (this.isConnected && this.ws) {
            this.ws.send(JSON.stringify(message));
        } else {
            this.messageQueue.push(message);
        }
    }

    /**
     * Send a command and wait for response
     * @param {Object} command - Command object
     * @param {number} timeout - Timeout in milliseconds
     */
    sendCommand(command, timeout = 30000) {
        return new Promise((resolve, reject) => {
            const requestId = command.request_id || this._generateRequestId();
            command.request_id = requestId;

            const timeoutId = setTimeout(() => {
                this.off('message', handler);
                reject(new Error('Command timeout'));
            }, timeout);

            const handler = (data) => {
                if (data.request_id === requestId || !data.request_id) {
                    clearTimeout(timeoutId);
                    this.off('message', handler);
                    resolve(data);
                }
            };

            this.on('message', handler);
            this.send(command);
        });
    }

    /**
     * Register an event handler
     */
    on(event, handler) {
        if (this.handlers[event]) {
            this.handlers[event].push(handler);
        }
    }

    /**
     * Remove an event handler
     */
    off(event, handler) {
        if (this.handlers[event]) {
            const index = this.handlers[event].indexOf(handler);
            if (index > -1) {
                this.handlers[event].splice(index, 1);
            }
        }
    }

    /**
     * Dispatch an event to all handlers
     */
    _dispatch(event, data) {
        if (this.handlers[event]) {
            this.handlers[event].forEach(handler => {
                try {
                    handler(data);
                } catch (e) {
                    console.error(`Error in ${event} handler:`, e);
                }
            });
        }
    }

    /**
     * Flush queued messages
     */
    _flushMessageQueue() {
        while (this.messageQueue.length > 0) {
            const message = this.messageQueue.shift();
            this.send(message);
        }
    }

    /**
     * Handle reconnection logic
     */
    _handleReconnect() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            console.log(`Attempting to reconnect (${this.reconnectAttempts}/${this.maxReconnectAttempts})...`);
            
            setTimeout(() => {
                this.connect().catch(() => {});
            }, this.reconnectDelay);
        }
    }

    /**
     * Generate a unique request ID
     */
    _generateRequestId() {
        return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    /**
     * Get connection status
     */
    getStatus() {
        return {
            connected: this.isConnected,
            url: this.url,
            reconnectAttempts: this.reconnectAttempts
        };
    }
}

// Export for use in other modules
window.WebSocketClient = WebSocketClient;
