extends Node2D

signal levelup

@export var end_game_screen_packed: PackedScene
@export var player_packed: PackedScene
@export var enemy_packed: PackedScene
@export var enemy_death_packed: PackedScene

const ENEMY_ROUNDS: Array[int] = [3, 5, 7]

var total_enemies: int
var killed_enemies: int = 0
var local_player: CharacterBody2D
var _game_ended: bool = false
var _camera: Camera2D
var _wave_mode: bool = false
var _current_round: int = 0
var _enemies_alive_in_round: int = 0
var _enemy_spawn_points: Array[Vector2] = []

@onready var HUD: Control = $UI/HUD
@onready var sfx_level_up: AudioStreamPlayer = $SfxLevelUp

func _ready() -> void:
	_camera = Camera2D.new()
	_camera.name = "GameCamera"
	add_child(_camera)
	_camera.make_current()
	_spawn_players()
	_setup_enemies()
	_setup_hud()

var _cam_log_timer: float = 0.0

func _process(delta: float) -> void:
	if local_player and is_instance_valid(local_player):
		_camera.global_position = local_player.global_position
		_cam_log_timer += delta
		if _cam_log_timer >= 1.0:
			_cam_log_timer = 0.0
			DebugLog.log_msg("[CAM] local_player=%s lpos=%s cam_pos=%s" % [local_player.name, local_player.global_position, _camera.global_position])

func _spawn_players() -> void:
	var is_multiplayer_game: bool = multiplayer.has_multiplayer_peer()
	
	if is_multiplayer_game:
		DebugLog.set_role("server" if multiplayer.is_server() else "client")
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
		DebugLog.log_msg("[SPAWN] is_server=%s my_id=%d local_player=%s" % [multiplayer.is_server(), multiplayer.get_unique_id(), local_player.name if local_player else "NULL"])
		for child: Node in $TestMap.get_children():
			if child is CharacterBody2D:
				DebugLog.log_msg("[SPAWN] player=%s pos=%s auth=%s is_auth=%s" % [child.name, child.global_position, child.get_multiplayer_authority(), child.is_multiplayer_authority()])
	else:
		_spawn_local_player(0)

func _spawn_player_for_peer(peer_id: int, index: int) -> void:
	var player_scene: CharacterBody2D = player_packed.instantiate()
	player_scene.name = "Player_%d" % peer_id
	player_scene.set_multiplayer_authority(peer_id)
	$TestMap.add_child(player_scene, true)
	var spawn_pos: Vector2 = NetworkManager.get_player_spawn_position(index)
	player_scene.position = spawn_pos
	_connect_player_signals(player_scene)

func _spawn_local_player(index: int) -> void:
	var player_scene: CharacterBody2D = player_packed.instantiate()
	player_scene.name = "LocalPlayer"
	$TestMap.add_child(player_scene, true)
	var spawn_pos: Vector2 = NetworkManager.get_player_spawn_position(index)
	player_scene.position = spawn_pos
	local_player = player_scene
	_connect_player_signals(player_scene)

func _connect_player_signals(player: CharacterBody2D) -> void:
	levelup.connect(player.calculate_stats)
	player.game_over.connect(display_end_game_screen)
	player.update_hp_bar.connect(HUD.update_hp_bar)

func _setup_enemies() -> void:
	var enemy_array: Array = get_tree().get_nodes_in_group("enemies")
	if multiplayer.has_multiplayer_peer():
		total_enemies = enemy_array.size()
		for i in enemy_array:
			i.died.connect(enemy_died)
		return

	_wave_mode = true
	for e: CharacterBody2D in enemy_array:
		_enemy_spawn_points.append(e.global_position)
		e.free()
	total_enemies = 0
	for round_count in ENEMY_ROUNDS:
		total_enemies += round_count
	_start_round()

func _start_round() -> void:
	var count: int = ENEMY_ROUNDS[_current_round]
	_enemies_alive_in_round = count
	for i in range(count):
		var spawn_pos: Vector2 = _enemy_spawn_points[i % _enemy_spawn_points.size()]
		var extra_lap: int = i / _enemy_spawn_points.size()
		if extra_lap > 0:
			spawn_pos += Vector2(50, 50) * extra_lap
		_spawn_enemy(spawn_pos)

func _spawn_enemy(spawn_pos: Vector2) -> void:
	var enemy: CharacterBody2D = enemy_packed.instantiate()
	enemy.death_packed = enemy_death_packed
	enemy.died.connect(enemy_died)
	$TestMap/Enemies.add_child(enemy)
	enemy.global_position = spawn_pos
	enemy.spawn_point = spawn_pos

func _setup_hud() -> void:
	HUD.update_level_indicator()

func enemy_died(exp_reward: int) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	killed_enemies += 1
	experience_gained(exp_reward)
	if _wave_mode:
		_enemies_alive_in_round -= 1
		if _enemies_alive_in_round <= 0:
			_current_round += 1
			if _current_round < ENEMY_ROUNDS.size():
				_start_round()
			else:
				display_end_game_screen(true)
	elif killed_enemies == total_enemies:
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
