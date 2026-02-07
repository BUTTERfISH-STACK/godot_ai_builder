/**
 * Godot AI Builder - Main Application
 */

class GodotAIBuilder {
    constructor() {
        this.wsClient = null;
        this.commandHistory = [];
        this.currentTab = 'command';
        this.parameterConfigs = this._getParameterConfigs();
        this.templates = this._getTemplates();
        this.init();
    }

    init() {
        this._bindElements();
        this._bindEvents();
        this._updateUI();
    }

    _bindElements() {
        this.serverUrlInput = document.getElementById('serverUrl');
        this.connectBtn = document.getElementById('connectBtn');
        this.disconnectBtn = document.getElementById('disconnectBtn');
        this.connectionStatus = document.getElementById('connectionStatus');
        this.tabs = document.querySelectorAll('.tab');
        this.tabContents = document.querySelectorAll('.tab-content');
        this.actionSelect = document.getElementById('actionSelect');
        this.parametersContainer = document.getElementById('parametersContainer');
        this.autoRunCheckbox = document.getElementById('autoRun');
        this.sendCommandBtn = document.getElementById('sendCommandBtn');
        this.gameDescription = document.getElementById('gameDescription');
        this.buildGameBtn = document.getElementById('buildGameBtn');
        this.builderProgress = document.getElementById('builderProgress');
        this.progressFill = document.getElementById('progressFill');
        this.progressText = document.getElementById('progressText');
        this.outputLog = document.getElementById('outputLog');
        this.clearOutputBtn = document.getElementById('clearOutput');
        this.fpsValue = document.getElementById('fpsValue');
        this.drawCallsValue = document.getElementById('drawCallsValue');
        this.nodesValue = document.getElementById('nodesValue');
        this.memoryValue = document.getElementById('memoryValue');
        this.refreshMetricsBtn = document.getElementById('refreshMetrics');
        this.commandHistoryEl = document.getElementById('commandHistory');
        this.quickActionBtns = document.querySelectorAll('[data-action]');
        this.templateBtns = document.querySelectorAll('[data-template]');
    }

    _bindEvents() {
        this.connectBtn.addEventListener('click', () => this._connect());
        this.disconnectBtn.addEventListener('click', () => this._disconnect());
        this.tabs.forEach(tab => { tab.addEventListener('click', () => this._switchTab(tab.dataset.tab)); });
        this.actionSelect.addEventListener('change', () => this._updateParameters());
        this.sendCommandBtn.addEventListener('click', () => this._sendCommand());
        this.clearOutputBtn.addEventListener('click', () => this._clearOutput());
        this.buildGameBtn.addEventListener('click', () => this._buildGame());
        this.refreshMetricsBtn.addEventListener('click', () => this._refreshMetrics());
        this.quickActionBtns.forEach(btn => { btn.addEventListener('click', () => this._executeQuickAction(btn.dataset.action)); });
        this.templateBtns.forEach(btn => { btn.addEventListener('click', () => this._applyTemplate(btn.dataset.template)); });
    }

    async _connect() {
        const url = this.serverUrlInput.value.trim();
        this._setConnectionStatus('connecting');
        try {
            this.wsClient = new WebSocketClient(url);
            this.wsClient.on('open', () => { this._setConnectionStatus('connected'); this._log('Connected to Godot AI Builder server', 'success'); });
            this.wsClient.on('close', () => { this._setConnectionStatus('disconnected'); this._log('Disconnected from server', 'warning'); });
            this.wsClient.on('error', (error) => { this._log('Connection error: ' + error.message, 'error'); });
            this.wsClient.on('message', (data) => { this._handleMessage(data); });
            await this.wsClient.connect();
        } catch (error) {
            this._setConnectionStatus('disconnected');
            this._log('Failed to connect: ' + error.message, 'error');
        }
    }

    _disconnect() {
        if (this.wsClient) { this.wsClient.disconnect(); this.wsClient = null; }
        this._setConnectionStatus('disconnected');
    }

    _setConnectionStatus(status) {
        const statusDot = this.connectionStatus.querySelector('.status-dot');
        const statusText = this.connectionStatus.querySelector('.status-text');
        statusDot.className = 'status-dot';
        if (status === 'connected') { statusDot.classList.add('connected'); statusText.textContent = 'Connected'; }
        else if (status === 'connecting') { statusDot.classList.add('connecting'); statusText.textContent = 'Connecting...'; }
        else { statusText.textContent = 'Disconnected'; }
        this._updateUI();
    }

    _switchTab(tabName) {
        this.currentTab = tabName;
        this.tabs.forEach(tab => { tab.classList.toggle('active', tab.dataset.tab === tabName); });
        this.tabContents.forEach(content => { content.classList.toggle('active', content.id === `${tabName}-tab`); });
    }

    _updateParameters() {
        const action = this.actionSelect.value;
        const config = this.parameterConfigs[action] || [];
        this.parametersContainer.innerHTML = '';
        config.forEach(param => {
            const field = document.createElement('div');
            field.className = 'parameter-field';
            const label = document.createElement('label');
            label.textContent = param.label;
            let input;
            if (param.type === 'select') {
                input = document.createElement('select');
                param.options.forEach(opt => { const option = document.createElement('option'); option.value = opt.value; option.textContent = opt.label; input.appendChild(option); });
            } else if (param.type === 'textarea') {
                input = document.createElement('textarea'); input.rows = 4;
            } else if (param.type === 'checkbox') {
                input = document.createElement('input'); input.type = 'checkbox'; label = document.createElement('label'); label.appendChild(input); label.appendChild(document.createTextNode(param.label));
            } else {
                input = document.createElement('input'); input.type = param.type || 'text'; input.placeholder = param.placeholder || '';
            }
            if (param.type !== 'checkbox') field.appendChild(label);
            field.appendChild(input);
            input.className = 'param-input';
            input.dataset.param = param.name;
            if (param.default !== undefined) input.value = param.default;
            this.parametersContainer.appendChild(field);
        });
    }

    async _sendCommand() {
        if (!this.wsClient || !this.wsClient.isConnected) { this._log('Not connected to server', 'error'); return; }
        const action = this.actionSelect.value;
        const command = { action: action, auto_run: this.autoRunCheckbox.checked };
        const paramInputs = this.parametersContainer.querySelectorAll('.param-input');
        paramInputs.forEach(input => {
            const paramName = input.dataset.param;
            let value = input.value;
            if (value.startsWith('[') || value.startsWith('{')) {
                try { value = JSON.parse(value); } catch (e) {}
            } else if (!isNaN(value) && value !== '') { value = parseFloat(value); }
            if (input.type === 'checkbox') value = input.checked;
            if (value !== '' && value !== null) command[paramName] = value;
        });
        this._log(`Sending command: ${action}`, 'info');
        this._addToHistory(command);
        try {
            const response = await this.wsClient.sendCommand(command);
            this._handleResponse(action, response);
        } catch (error) {
            this._log(`Command failed: ${error.message}`, 'error');
        }
    }

    async _executeQuickAction(action) {
        if (!this.wsClient || !this.wsClient.isConnected) { this._log('Not connected to server', 'error'); return; }
        const command = { action: action };
        this._log(`Quick action: ${action}`, 'info');
        try {
            const response = await this.wsClient.sendCommand(command);
            this._handleResponse(action, response);
        } catch (error) {
            this._log(`Action failed: ${error.message}`, 'error');
        }
    }

    _applyTemplate(templateName) {
        const template = this.templates[templateName];
        if (!template) return;
        this.actionSelect.value = template.action;
        this._updateParameters();
        setTimeout(() => {
            const inputs = this.parametersContainer.querySelectorAll('.param-input');
            inputs.forEach(input => {
                const paramName = input.dataset.param;
                if (template[paramName] !== undefined) {
                    input.value = typeof template[paramName] === 'object' ? JSON.stringify(template[paramName], null, 2) : template[paramName];
                }
            });
        }, 0);
    }

    async _buildGame() {
        const description = this.gameDescription.value.trim();
        if (!description) { this._log('Please enter a game description', 'error'); return; }
        if (!this.wsClient || !this.wsClient.isConnected) { this._log('Not connected to server', 'error'); return; }
        this.builderProgress.classList.remove('hidden');
        this.buildGameBtn.disabled = true;
        this.progressFill.style.width = '0%';
        this.progressText.textContent = 'Parsing game description...';
        const command = { action: 'create_scene', name: 'GameScene', scene_type: 'Node3D', description: description, auto_run: true };
        try {
            this.progressText.textContent = 'Creating scene...';
            this.progressFill.style.width = '30%';
            const response = await this.wsClient.sendCommand(command);
            if (response.status === 'success') {
                this.progressFill.style.width = '100%';
                this.progressText.textContent = 'Game created successfully!';
                this._handleResponse('create_scene', response);
            } else { this._log('Failed to create game: ' + response.error, 'error'); }
        } catch (error) {
            this._log(`Game build failed: ${error.message}`, 'error');
        } finally {
            setTimeout(() => { this.builderProgress.classList.add('hidden'); this.buildGameBtn.disabled = false; }, 2000);
        }
    }

    async _refreshMetrics() {
        if (!this.wsClient || !this.wsClient.isConnected) { this._log('Not connected to server', 'error'); return; }
        try {
            const response = await this.wsClient.sendCommand({ action: 'get_performance' });
            if (response.status === 'success') {
                this.fpsValue.textContent = response.fps?.toFixed(1) || '--';
                this.drawCallsValue.textContent = response.draw_calls || '--';
                this.nodesValue.textContent = response.node_count || '--';
                this.memoryValue.textContent = (response.memory_usage_mb || 0).toFixed(1);
            }
        } catch (error) {
            this._log('Failed to get metrics: ' + error.message, 'error');
        }
    }

    _handleMessage(data) {
        if (data.raw) { this._log('Received: ' + data.raw); return; }
        this._log(`Response for ${data.action || 'unknown'}: ${data.status}`, data.status);
    }

    _handleResponse(action, response) {
        if (response.status === 'success') {
            this._log(`✓ ${action} completed successfully`, 'success');
            if (response.fps !== undefined) {
                this.fpsValue.textContent = response.fps.toFixed(1);
                this.drawCallsValue.textContent = response.draw_calls;
                this.nodesValue.textContent = response.node_count;
                this.memoryValue.textContent = response.memory_usage_mb?.toFixed(1) || '--';
            }
        } else {
            this._log(`✗ ${action} failed: ${response.error || response.message}`, 'error');
            if (response.error_details) console.error('Error details:', response.error_details);
        }
    }

    _addToHistory(command) {
        this.commandHistory.unshift(command);
        if (this.commandHistory.length > 20) this.commandHistory.pop();
        this._updateHistoryUI();
    }

    _updateHistoryUI() {
        if (this.commandHistory.length === 0) {
            this.commandHistoryEl.innerHTML = '<p class="empty-state">No commands sent yet</p>';
            return;
        }
        this.commandHistoryEl.innerHTML = this.commandHistory.map(cmd => `<div class="history-item"><span class="history-action">${cmd.action}</span></div>`).join('');
    }

    _log(message, type = 'info') {
        const entry = document.createElement('div');
        entry.className = `log-entry ${type}`;
        const timestamp = new Date().toLocaleTimeString();
        entry.innerHTML = `<span class="log-timestamp">[${timestamp}]</span><span class="log-action">${message}</span>`;
        this.outputLog.appendChild(entry);
        this.outputLog.scrollTop = this.outputLog.scrollHeight;
    }

    _clearOutput() { this.outputLog.innerHTML = ''; }

    _updateUI() {
        const connected = this.wsClient && this.wsClient.isConnected;
        this.connectBtn.disabled = connected;
        this.disconnectBtn.disabled = !connected;
        this.sendCommandBtn.disabled = !connected;
        this.buildGameBtn.disabled = !connected;
        this.refreshMetricsBtn.disabled = !connected;
        this.quickActionBtns.forEach(btn => { btn.disabled = !connected; });
        this.templateBtns.forEach(btn => { btn.disabled = !connected; });
    }

    _getParameterConfigs() {
        return {
            create_scene: [
                { name: 'name', label: 'Scene Name', type: 'text', placeholder: 'MainScene' },
                { name: 'parent_path', label: 'Parent Path', type: 'text', placeholder: 'res://', default: 'res://' },
                { name: 'scene_type', label: 'Scene Type', type: 'select', options: [{ value: 'Node3D', label: 'Node3D' }, { value: 'Node2D', label: 'Node2D' }, { value: 'Control', label: 'Control' }], default: 'Node3D' },
                { name: 'save_path', label: 'Save Path', type: 'text', placeholder: 'res://scenes/main.tscn' }
            ],
            add_node: [
                { name: 'node_type', label: 'Node Type', type: 'text', placeholder: 'CharacterBody3D' },
                { name: 'parent_path', label: 'Parent Path', type: 'text', placeholder: '/root/MainScene' },
                { name: 'name', label: 'Node Name', type: 'text', placeholder: 'Player' },
                { name: 'position', label: 'Position [x, y, z]', type: 'text', placeholder: '[0, 1, 0]' },
                { name: 'rotation', label: 'Rotation [x, y, z]', type: 'text', placeholder: '[0, 0, 0]' },
                { name: 'scale', label: 'Scale [x, y, z]', type: 'text', placeholder: '[1, 1, 1]' }
            ],
            set_property: [
                { name: 'node_path', label: 'Node Path', type: 'text', placeholder: '/root/MainScene/Player' },
                { name: 'property_name', label: 'Property Name', type: 'text', placeholder: 'speed' },
                { name: 'value', label: 'Value', type: 'text', placeholder: '5.0' }
            ],
            attach_script: [
                { name: 'node_path', label: 'Node Path', type: 'text', placeholder: '/root/MainScene/Player' },
                { name: 'script_path', label: 'Script Path', type: 'text', placeholder: 'res://scripts/player.gd' },
                { name: 'create_if_missing', label: 'Create if Missing', type: 'checkbox', default: false }
            ],
            create_script: [
                { name: 'path', label: 'Script Path', type: 'text', placeholder: 'res://scripts/inventory.gd' },
                { name: 'name', label: 'Class Name', type: 'text', placeholder: 'Inventory' },
                { name: 'base_class', label: 'Base Class', type: 'select', options: [{ value: 'Node', label: 'Node' }, { value: 'Node2D', label: 'Node2D' }, { value: 'Node3D', label: 'Node3D' }, { value: 'CharacterBody3D', label: 'CharacterBody3D' }, { value: 'Area3D', label: 'Area3D' }, { value: 'Control', label: 'Control' }], default: 'Node' },
                { name: 'code', label: 'Script Code', type: 'textarea', placeholder: 'extends Node\n\n# Your code here' }
            ],
            modify_script: [
                { name: 'path', label: 'Script Path', type: 'text', placeholder: 'res://scripts/player.gd' },
                { name: 'modifications', label: 'Modifications (JSON)', type: 'textarea', placeholder: '{"add_methods": [{"name": "jump", "body": "print(\"Jump!\")}]}' }
            ],
            delete_node: [
                { name: 'node_path', label: 'Node Path', type: 'text', placeholder: '/root/MainScene/TempNode' },
                { name: 'recursive', label: 'Recursive Delete', type: 'checkbox', default: true }
            ],
            run_scene: [
                { name: 'scene_path', label: 'Scene Path', type: 'text', placeholder: 'res://scenes/main.tscn' },
                { name: 'wait_for_completion', label: 'Wait for Completion', type: 'checkbox', default: false },
                { name: 'timeout', label: 'Timeout (seconds)', type: 'number', placeholder: '300' }
            ],
            save_scene: [
                { name: 'scene_path', label: 'Scene Path', type: 'text', placeholder: 'res://scenes/main.tscn' },
                { name: 'node_path', label: 'Node Path (optional)', type: 'text', placeholder: '/root/MainScene' }
            ]
        };
    }

    _getTemplates() {
        return {
            player: { action: 'add_node', node_type: 'CharacterBody3D', parent_path: '/root', name: 'Player', position: [0, 1, 0] },
            camera: { action: 'add_node', node_type: 'Camera3D', parent_path: '/root/Player', name: 'Camera3D', position: [0, 2, 3] },
            light: { action: 'add_node', node_type: 'DirectionalLight3D', parent_path: '/root', name: 'DirectionalLight3D', rotation: [-45, 45, 0] },
            script: { action: 'create_script', path: 'res://scripts/new_script.gd', name: 'NewScript', base_class: 'Node', code: 'extends Node\n\n# New script\n\nfunc _ready():\n    pass\n' }
        };
    }
}

document.addEventListener('DOMContentLoaded', () => { window.app = new GodotAIBuilder(); });
