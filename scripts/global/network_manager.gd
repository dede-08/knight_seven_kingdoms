extends Node

signal player_connected(peer_id: int)
signal player_disconnected(peer_id: int)
signal server_disconnected

const DEFAULT_PORT: int = 7777
const MAX_PLAYERS: int = 2

var players: Dictionary = {}
var player_count: int = 0

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func create_server(port: int = DEFAULT_PORT) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_register_player(multiplayer.get_unique_id())
	return OK


func join_server(ip: String, port: int = DEFAULT_PORT) -> Error:
	var peer: ENetMultiplayerPeer = ENetMultiplayerPeer.new()
	var err: Error = peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func disconnect_from_server() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	player_count = 0


func get_player_id() -> int:
	return multiplayer.get_unique_id()


func is_server() -> bool:
	return not multiplayer.has_multiplayer_peer() or multiplayer.is_server()


func is_client() -> bool:
	return multiplayer.has_multiplayer_peer() and not multiplayer.is_server()


func is_single_player() -> bool:
	return not multiplayer.has_multiplayer_peer()


func get_local_player_index() -> int:
	if players.has(get_player_id()):
		return players[get_player_id()]
	return 0


func get_player_index(peer_id: int) -> int:
	if players.has(peer_id):
		return players[peer_id]
	return -1


func get_player_spawn_position(index: int) -> Vector2:
	match index:
		0:
			return Vector2(293, 966)
		1:
			return Vector2(357, 966)
		_:
			return Vector2(293, 966)


func _register_player(peer_id: int) -> void:
	if not players.has(peer_id):
		players[peer_id] = player_count
		player_count += 1
		player_connected.emit(peer_id)


func _on_peer_connected(id: int) -> void:
	_register_player(id)


func _on_peer_disconnected(id: int) -> void:
	players.erase(id)
	player_count = players.size()
	player_disconnected.emit(id)


func _on_connected_to_server() -> void:
	_register_player(multiplayer.get_unique_id())


func _on_connection_failed() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	player_count = 0


func _on_server_disconnected() -> void:
	multiplayer.multiplayer_peer = null
	players.clear()
	player_count = 0
	server_disconnected.emit()
