/**
 * WebSocket Client for Godot AI Builder
 */

class WebSocketClient {
    constructor(url) {
        this.url = url;
        this.ws = null;
        this.reconnectAttempts = 0;
        this.maxReconnectAttempts = 5;
        this.reconnectDelay = 2000;
        this.messageQueue = [];
        this.handlers = { open: [], close: [], error: [], message: [] };
        this.isConnected = false;
    }

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
                        this._dispatch('message', { raw: event.data });
                    }
                };
            } catch (error) {
                reject(error);
            }
        });
    }

    disconnect() {
        if (this.ws) {
            this.ws.close();
            this.ws = null;
            this.isConnected = false;
        }
    }

    send(message) {
        if (this.isConnected && this.ws) {
            this.ws.send(JSON.stringify(message));
        } else {
            this.messageQueue.push(message);
        }
    }

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

    on(event, handler) {
        if (this.handlers[event]) this.handlers[event].push(handler);
    }

    off(event, handler) {
        if (this.handlers[event]) {
            const index = this.handlers[event].indexOf(handler);
            if (index > -1) this.handlers[event].splice(index, 1);
        }
    }

    _dispatch(event, data) {
        if (this.handlers[event]) {
            this.handlers[event].forEach(handler => {
                try { handler(data); } catch (e) { console.error(`Error in ${event} handler:`, e); }
            });
        }
    }

    _flushMessageQueue() {
        while (this.messageQueue.length > 0) {
            const message = this.messageQueue.shift();
            this.send(message);
        }
    }

    _handleReconnect() {
        if (this.reconnectAttempts < this.maxReconnectAttempts) {
            this.reconnectAttempts++;
            setTimeout(() => { this.connect().catch(() => {}); }, this.reconnectDelay);
        }
    }

    _generateRequestId() {
        return `req_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    }

    getStatus() {
        return { connected: this.isConnected, url: this.url, reconnectAttempts: this.reconnectAttempts };
    }
}

window.WebSocketClient = WebSocketClient;
