@tool
extends Node

## WebSocket Server for Godot AI Builder
## =======================================
## Handles bidirectional communication between the Godot Editor
## and the local AI control server using WebSocket protocol.

# Signal declarations
signal message_received(message: String)
signal client_connected(client_id: int)
signal client_disconnected(client_id: int)
signal server_error(error: Dictionary)

# Server configuration
const DEFAULT_PORT: int = 8765
const MAX_CLIENTS: int = 5
const PING_INTERVAL: float = 5.0
const CONNECTION_TIMEOUT: float = 30.0

# Internal state
var _server: WebSocketPeer = WebSocketPeer.new()
var _tcp_server: TCPServer = TCPServer.new()
var _clients: Dictionary = {}  # client_id -> WebSocketPeer
var _client_counter: int = 0
var _is_listening: bool = false
var _current_port: int = DEFAULT_PORT
var _websocket_path: String = "/ai_builder"
var _last_activity: Dictionary = {}  # client_id -> timestamp

# Connection state
enum ConnectionState {
	DISCONNECTED,
	LISTENING,
	HANDSHAKING,
	CONNECTED,
	ERROR
}
var _state: ConnectionState = ConnectionState.DISCONNECTED

# Message queue for reliable delivery
var _message_queue: Array[String] = []
var _processing_message: bool = false


## Lifecycle Methods
## =================

func _ready() -> void:
	"""
	Initialize the WebSocket server component.
	"""
	_client_counter = 0
	_clients.clear()
	_last_activity.clear()
	_message_queue.clear()


func _process(_delta: float) -> void:
	"""
	Process incoming data and maintain connections.
	"""
	if not _is_listening:
		return
	
	_poll_server()
	_process_pending_messages()
	_check_timeouts()


## Server Management
## ================

func start_server(port: int = DEFAULT_PORT, path: String = "/ai_builder") -> Error:
	"""
	Starts the WebSocket server on the specified port.
	
	Args:
		port: TCP port to listen on (default: 8765)
		path: WebSocket path to accept (default: "/ai_builder")
	
	Returns:
		Error code (OK on success)
	"""
	_current_port = port
	_websocket_path = path
	
	# Close existing connections
	_stop_all_clients()
	
	# Reset server state
	_server = WebSocketPeer.new()
	_tcp_server = TCPServer.new()
	
	# Attempt to bind to the port
	var error: Error = _tcp_server.listen(port, null)
	if error != OK:
		_handle_server_error("Failed to bind to port %d" % port, error)
		return error
	
	_is_listening = true
	_state = ConnectionState.LISTENING
	
	print("[WebSocket Server] Listening on port %d (path: %s)" % [port, path])
	return OK


func stop_server() -> void:
	"""
	Stops the WebSocket server and closes all client connections.
	"""
	if not _is_listening:
		return
	
	print("[WebSocket Server] Stopping server...")
	
	_stop_all_clients()
	
	if _tcp_server.is_listening():
		_tcp_server.stop()
	
	_is_listening = false
	_state = ConnectionState.DISCONNECTED
	print("[WebSocket Server] Server stopped.")


## Client Communication
## ===================

func send_to_client(client_id: int, message: String) -> Error:
	"""
	Sends a message to a specific client.
	
	Args:
		client_id: The ID of the target client
		message: JSON string to send
	
	Returns:
		Error code (OK on success, ERR_BUSY if client is busy)
	"""
	if not _clients.has(client_id):
		push_error("[WebSocket Server] Client %d not found" % client_id)
		return ERR_DOES_NOT_EXIST
	
	var peer: WebSocketPeer = _clients[client_id]
	
	# Check if client is still connected
	if peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_disconnect_client(client_id)
		return ERR_CONNECTION_ERROR
	
	# Send the message
	var error: Error = peer.send_text(message)
	if error != OK:
		push_error("[WebSocket Server] Failed to send to client %d: %s" % [client_id, error])
		_disconnect_client(client_id)
		return error
	
	_last_activity[client_id] = Time.get_unix_time_from_system()
	return OK


func broadcast_message(message: String) -> Array:
	"""
	Broadcasts a message to all connected clients.
	
	Args:
		message: JSON string to broadcast
	
	Returns:
		Array of failed client IDs
	"""
	var failed: Array = []
	
	for client_id: int in _clients:
		var error: Error = send_to_client(client_id, message)
		if error != OK:
			failed.append(client_id)
	
	return failed


func send_broadcast_except(sender_id: int, message: String) -> void:
	"""
	Sends a message to all clients except the sender.
	
	Args:
		sender_id: Client ID to exclude
		message: JSON string to send
	"""
	for client_id: int in _clients:
		if client_id != sender_id:
			send_to_client(client_id, message)


## Server Operations
## ================

func get_client_count() -> int:
	"""
	Returns the number of connected clients.
	"""
	return _clients.size()


func get_client_ids() -> Array[int]:
	"""
	Returns an array of all connected client IDs.
	"""
	return _clients.keys()


func is_client_connected(client_id: int) -> bool:
	"""
	Checks if a specific client is still connected.
	"""
	if not _clients.has(client_id):
		return false
	
	var peer: WebSocketPeer = _clients[client_id]
	return peer.get_ready_state() == WebSocketPeer.STATE_OPEN


func get_server_state() -> ConnectionState:
	"""
	Returns the current server state.
	"""
	return _state


func get_port() -> int:
	"""
	Returns the current server port.
	"""
	return _current_port


## Internal Methods
## ================

func _poll_server() -> void:
	"""
	Polls the TCP server for new connections.
	"""
	if not _tcp_server.is_listening():
		return
	
	var peer: WebSocketPeer = WebSocketPeer.new()
	var conn: StreamPeer = _tcp_server.take_connection()
	
	if conn:
		peer.accept_stream(conn)
		_add_client(peer)


func _add_client(peer: WebSocketPeer) -> void:
	"""
	Adds a new client connection after successful WebSocket handshake.
	"""
	_client_counter += 1
	var client_id: int = _client_counter
	
	_clients[client_id] = peer
	_last_activity[client_id] = Time.get_unix_time_from_system()
	
	_state = ConnectionState.CONNECTED
	
	print("[WebSocket Server] Client %d connected (total: %d)" % [client_id, _clients.size()])
	client_connected.emit(client_id)
	
	# Start polling this client
	_poll_client(client_id)


func _poll_client(client_id: int) -> void:
	"""
	Polls a specific client for incoming messages.
	"""
	if not _clients.has(client_id):
		return
	
	var peer: WebSocketPeer = _clients[client_id]
	var ready_state: int = peer.get_ready_state()
	
	match ready_state:
		WebSocketPeer.STATE_OPEN:
			# Process incoming data
			var data: PackedByteArray = peer.get_packet()
			if data.size() > 0:
				var message: String = data.get_string_from_utf8()
				if message.is_valid_utf8():
					_last_activity[client_id] = Time.get_unix_time_from_system()
					message_received.emit(message)
				else:
					push_warning("[WebSocket Server] Invalid UTF-8 from client %d" % client_id)
		
		WebSocketPeer.STATE_CLOSED:
			var code: int = peer.get_close_code()
			var reason: String = peer.get_close_reason()
			print("[WebSocket Server] Client %d closed: code=%d, reason=%s" % [client_id, code, reason])
			_disconnect_client(client_id)


func _process_pending_messages() -> void:
	"""
	Processes all pending client messages.
	"""
	for client_id: int in _clients:
		var peer: WebSocketPeer = _clients[client_id]
		if peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			_poll_client(client_id)


func _disconnect_client(client_id: int) -> void:
	"""
	Disconnects and removes a client.
	"""
	if not _clients.has(client_id):
		return
	
	var peer: WebSocketPeer = _clients[client_id]
	peer.close()
	
	_clients.erase(client_id)
	_last_activity.erase(client_id)
	
	print("[WebSocket Server] Client %d disconnected (remaining: %d)" % [client_id, _clients.size()])
	client_disconnected.emit(client_id)
	
	# Check if we have no more clients
	if _clients.is_empty():
		_state = ConnectionState.LISTENING


func _stop_all_clients() -> void:
	"""
	Disconnects all clients gracefully.
	"""
	var client_ids: Array[int] = _clients.keys()
	for client_id: int in client_ids:
		_disconnect_client(client_id)


func _check_timeouts() -> void:
	"""
	Checks for clients that have been inactive too long.
	"""
	var current_time: float = Time.get_unix_time_from_system()
	var timed_out: Array[int] = []
	
	for client_id: int in _clients:
		var last_active: float = _last_activity.get(client_id, 0.0)
		if current_time - last_active > CONNECTION_TIMEOUT:
			timed_out.append(client_id)
	
	for client_id: int in timed_out:
		print("[WebSocket Server] Client %d timed out" % client_id)
		_disconnect_client(client_id)


func _handle_server_error(message: String, error: Error) -> void:
	"""
	Handles server errors and emits appropriate signals.
	"""
	_state = ConnectionState.ERROR
	
	var error_data: Dictionary = {
		"message": message,
		"error_code": error,
		"timestamp": Time.get_unix_time_from_system()
	}
	
	print("[WebSocket Server] ERROR: %s (code: %s)" % [message, error])
	server_error.emit(error_data)


## Utility Methods
## ==============

func get_connection_info(client_id: int) -> Dictionary:
	"""
	Returns connection information for a specific client.
	"""
	if not _clients.has(client_id):
		return {}
	
	var peer: WebSocketPeer = _clients[client_id]
	return {
		"client_id": client_id,
		"ready_state": peer.get_ready_state(),
		"last_activity": _last_activity.get(client_id, 0.0),
		"pending_packets": peer.get_packet_queue_size()
	}


func is_listening() -> bool:
	"""
	Returns whether the server is currently listening.
	"""
	return _is_listening and _tcp_server.is_listening()
