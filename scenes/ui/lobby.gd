extends Control

signal start_game_pressed
signal back_pressed

@onready var host_panel: VBoxContainer = $VB/HostPanel
@onready var client_panel: VBoxContainer = $VB/ClientPanel
@onready var status_label: Label = $VB/StatusLabel
@onready var ip_input: LineEdit = $VB/ClientPanel/IPInput
@onready var start_button: TextureButton = $VB/HostPanel/StartButton
@onready var connect_button: TextureButton = $VB/ClientPanel/ConnectButton
@onready var back_button: TextureButton = $VB/BackButton

var mode: String = ""

func _ready() -> void:
	host_panel.visible = false
	client_panel.visible = false
	status_label.text = ""
	start_button.pressed.connect(_on_start_pressed)
	connect_button.pressed.connect(_on_connect_pressed)
	back_button.pressed.connect(_on_back_pressed)
	NetworkManager.player_connected.connect(_on_player_connected)
	NetworkManager.server_disconnected.connect(_on_server_disconnected)


func setup(mode: String) -> void:
	self.mode = mode
	match mode:
		"host":
			host_panel.visible = true
			client_panel.visible = false
			status_label.text = "Creating server..."
			var err: Error = NetworkManager.create_server()
			if err != OK:
				status_label.text = "Failed to create server (error: %d)" % err
				return
			var ip: String = _get_local_ip()
			status_label.text = "Waiting for player...\nIP: %s\nPort: %d" % [ip, NetworkManager.DEFAULT_PORT]
		"join":
			host_panel.visible = false
			client_panel.visible = true
			status_label.text = "Enter IP and connect"
			ip_input.text = "127.0.0.1"


func _on_start_pressed() -> void:
	if NetworkManager.player_count < 2:
		status_label.text = "Waiting for player to connect..."
		return
	start_game_pressed.emit()


func _on_connect_pressed() -> void:
	var ip: String = ip_input.text.strip_edges()
	if ip.is_empty():
		status_label.text = "Please enter an IP address"
		return
	status_label.text = "Connecting to %s:%d..." % [ip, NetworkManager.DEFAULT_PORT]
	connect_button.disabled = true
	var err: Error = NetworkManager.join_server(ip)
	if err != OK:
		status_label.text = "Connection failed (error: %d)" % err
		connect_button.disabled = false


func _on_player_connected(_peer_id: int) -> void:
	if mode == "host":
		status_label.text = "Player connected!\nIP: %s\nPort: %d\nReady to start!" % [_get_local_ip(), NetworkManager.DEFAULT_PORT]
	elif mode == "join":
		status_label.text = "Connected! Starting game..."
		await get_tree().create_timer(0.5).timeout
		start_game_pressed.emit()


func _on_server_disconnected() -> void:
	status_label.text = "Server disconnected"
	connect_button.disabled = false


func _on_back_pressed() -> void:
	NetworkManager.disconnect_from_server()
	back_pressed.emit()


func _get_local_ip() -> String:
	var ip: String = "127.0.0.1"
	for addr: String in IP.get_local_addresses():
		if addr.begins_with("192.168.") or addr.begins_with("10.") or addr.begins_with("172."):
			ip = addr
			break
	return ip
