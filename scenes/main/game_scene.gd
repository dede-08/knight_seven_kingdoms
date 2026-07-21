extends Node2D

signal levelup

@export var end_game_screen_packed: PackedScene
@export var player_packed: PackedScene

var total_enemies: int
var killed_enemies: int = 0
var local_player: CharacterBody2D
var _game_ended: bool = false

@onready var HUD: Control = $UI/HUD
@onready var sfx_level_up: AudioStreamPlayer = $SfxLevelUp

func _ready() -> void:
	_spawn_players()
	_setup_enemies()
	_setup_hud()

func _spawn_players() -> void:
	var is_multiplayer_game: bool = multiplayer.has_multiplayer_peer()
	
	if is_multiplayer_game:
		var server_id: int = 1
		if multiplayer.is_server():
			var peer_ids: Array = multiplayer.get_peers()
			var client_peer_id: int = peer_ids[0] if peer_ids.size() > 0 else -1
			_spawn_player_for_peer(server_id, 0)
			if client_peer_id != -1:
				_spawn_player_for_peer(client_peer_id, 1)
			local_player = $TestMap.get_node("Player_%d" % server_id)
		else:
			var my_id: int = multiplayer.get_unique_id()
			_spawn_player_for_peer(server_id, 0)
			_spawn_player_for_peer(my_id, 1)
			local_player = $TestMap.get_node("Player_%d" % my_id)
	else:
		_spawn_local_player(0)
	
	_ensure_local_camera()

func _spawn_player_for_peer(peer_id: int, index: int) -> void:
	var player_scene: CharacterBody2D = player_packed.instantiate()
	player_scene.name = "Player_%d" % peer_id
	player_scene.set_multiplayer_authority(peer_id)
	player_scene.get_node("Camera2D").enabled = false
	$TestMap.add_child(player_scene, true)
	var spawn_pos: Vector2 = NetworkManager.get_player_spawn_position(index)
	player_scene.position = spawn_pos
	_connect_player_signals(player_scene)

func _spawn_local_player(index: int) -> void:
	var player_scene: CharacterBody2D = player_packed.instantiate()
	player_scene.name = "LocalPlayer"
	player_scene.get_node("Camera2D").enabled = false
	$TestMap.add_child(player_scene, true)
	var spawn_pos: Vector2 = NetworkManager.get_player_spawn_position(index)
	player_scene.position = spawn_pos
	local_player = player_scene
	_connect_player_signals(player_scene)

func _connect_player_signals(player: CharacterBody2D) -> void:
	levelup.connect(player.calculate_stats)
	player.game_over.connect(display_end_game_screen)
	player.update_hp_bar.connect(HUD.update_hp_bar)

func _ensure_local_camera() -> void:
	_disable_all_cameras()
	if local_player and local_player.has_node("Camera2D"):
		var cam: Camera2D = local_player.get_node("Camera2D")
		cam.enabled = true
		cam.make_current()

func _disable_all_cameras() -> void:
	var cameras: Array[Node] = []
	_find_cameras(self, cameras)
	for cam: Camera2D in cameras:
		cam.enabled = false

func _find_cameras(node: Node, result: Array[Node]) -> void:
	for child in node.get_children():
		if child is Camera2D:
			result.append(child)
		_find_cameras(child, result)

func _setup_enemies() -> void:
	var enemy_array: Array = get_tree().get_nodes_in_group("enemies")
	total_enemies = enemy_array.size()
	for i in enemy_array:
		i.died.connect(enemy_died)

func _setup_hud() -> void:
	HUD.update_level_indicator()

func enemy_died(exp_reward: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	killed_enemies += 1
	experience_gained(exp_reward)
	if killed_enemies == total_enemies:
		display_end_game_screen(true)

func experience_gained(exp_gain: int) -> void:
	if PlayerData.level == LevelData.MAX_LEVEL:
		return
	var new_experience: int = PlayerData.experience + exp_gain
	if new_experience >= LevelData.LEVEL_THRESHOLDS[PlayerData.level -1]:
		level_up(new_experience)
	else:
		PlayerData.experience = new_experience

func level_up(new_experience: int) -> void:
	print("tengo mas poder")
	new_experience -= LevelData.LEVEL_THRESHOLDS[PlayerData.level - 1]
	PlayerData.level += 1
	PlayerData.experience = new_experience
	sfx_level_up.play()
	levelup.emit()
	HUD.update_level_indicator()

func display_end_game_screen(victorious: bool) -> void:
	if _game_ended:
		return
	_game_ended = true
	_show_end_game_screen(victorious)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_show_end_game_screen.rpc(victorious)

@rpc("authority", "call_remote", "reliable")
func _rpc_show_end_game_screen(victorious: bool) -> void:
	_show_end_game_screen(victorious)

func _show_end_game_screen(victorious: bool) -> void:
	if $UI.has_node("EndGameScreen"):
		return
	var end_game_screen_scene: Control = end_game_screen_packed.instantiate()
	end_game_screen_scene.victorious = victorious
	
	var scene_handler: Node = get_node("/root/SceneHandler")
	end_game_screen_scene.repeat_level.connect(scene_handler.new_game)
	end_game_screen_scene.main_menu.connect(scene_handler.load_main_menu)
	$UI.add_child(end_game_screen_scene)
	
	await get_tree().create_timer(0.4).timeout
	if local_player and is_instance_valid(local_player):
		local_player.set_process_mode(PROCESS_MODE_DISABLED)
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	for i: CharacterBody2D in enemies:
		i.set_process_mode(PROCESS_MODE_DISABLED)
