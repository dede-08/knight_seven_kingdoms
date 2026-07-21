extends CharacterBody2D

signal died(exp: int)

enum State{
	IDLE,
	CHASE,
	RETURN,
	ATTACK,
	DEAD
}

@export_category("Stats")
@export var speed: int = 128
@export var attack_damage: int = 10
@export var attack_speed: float = 1.0
@export var hitpoints:int = 180
@export var aggro_range: float = 384.0
@export var attack_range: float = 70.0
@export var exp_reward: int = 600
@export_category("Related Scenes")
@export var death_packed: PackedScene

var state: State = State.IDLE

@onready var spawn_point: Vector2 = global_position
@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_playback: AnimationNodeStateMachinePlayback = $AnimationTree["parameters/playback"]
@onready var nav_agent: NavigationAgent2D = $NavigationAgent2D
@onready var sfx_attack: AudioStreamPlayer2D = $SfxAttack
@onready var sfx_hurt: AudioStreamPlayer2D = $SfxHurt

var _target_player: CharacterBody2D = null
var _enemy_frame: int = 0

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	animation_tree.set_active(true)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		$HitBox.set_deferred("monitoring", false)
		$NavigationAgent2D.set_deferred("process_mode", Node.PROCESS_MODE_DISABLED)

func _physics_process(_delta: float) -> void:
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	if state == State.DEAD:
		return
	_enemy_frame += 1
	if _enemy_frame % 60 == 1:
		var player_count: int = get_tree().get_nodes_in_group("player").size()
		DebugLog.log_msg("[ENEMY] name=%s frame=%d state=%s pos=%s players=%d target=%s" % [name, _enemy_frame, State.keys()[state], global_position, player_count, _target_player.name if _target_player else "null"])
	if state != State.ATTACK:
		_target_player = _find_closest_player()
		if _target_player == null:
			state = State.IDLE
			update_animation()
		elif distance_to_player() <= attack_range:
			state = State.ATTACK
			velocity = Vector2.ZERO
			attack()
		elif distance_to_player() <= aggro_range:
			state = State.CHASE
			move()
		elif global_position.distance_to(spawn_point) > 32:
			state = State.RETURN
			move()
		elif state != State.IDLE:
			state = State.IDLE
			update_animation()
	if multiplayer.has_multiplayer_peer():
		_sync_enemy.rpc(position, _get_current_anim(), $Sprite2D.flip_h)

func _find_closest_player() -> CharacterBody2D:
	var players: Array = get_tree().get_nodes_in_group("player")
	var closest: CharacterBody2D = null
	var closest_dist: float = 99999.0
	for p: CharacterBody2D in players:
		if is_instance_valid(p):
			var dist: float = global_position.distance_to(p.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = p
	return closest

func distance_to_player() -> float:
	if _target_player == null or not is_instance_valid(_target_player):
		return 99999.0
	return global_position.distance_to(_target_player.global_position)

func move() -> void:
	if state == State.CHASE:
		nav_agent.target_position = _target_player.global_position
	elif state == State.RETURN:
		nav_agent.target_position = spawn_point
	var next_path_position: Vector2 = nav_agent.get_next_path_position()
	velocity = global_position.direction_to(next_path_position) * speed
	move_and_slide()

	#sprite flipping only in idle and run
	if state == State.IDLE or state == State.CHASE:
		if velocity.x < -0.01:
			$Sprite2D.flip_h = true
		elif velocity.x > 0.01:
			$Sprite2D.flip_h = false

	#update animation
	update_animation()

func update_animation() -> void:
	match state:
		State.IDLE:
			animation_playback.travel("idle")
		State.CHASE:
			animation_playback.travel("run")
		State.RETURN:
			animation_playback.travel("run")
		State.ATTACK:
			animation_playback.travel("attack")

func attack() -> void:
	sfx_attack.play()
	var player_pos: Vector2 = _target_player.global_position
	var attack_dir: Vector2 = (player_pos - global_position).normalized()
	$Sprite2D.flip_h = attack_dir.x < 0 and abs(attack_dir.x) >= abs(attack_dir.y)
	animation_tree.set("parameters/attack/BlendSpace2D/blend_position", attack_dir)
	update_animation()
	
	await get_tree().create_timer(attack_speed).timeout
	state = State.IDLE

func take_damage(damage_taken: int) -> void:
	hitpoints -= damage_taken
	sfx_hurt.play()
	if hitpoints <= 0:
		death()

func death() -> void:
	state = State.DEAD
	died.emit(exp_reward)
	var death_scene: Node2D = death_packed.instantiate()
	death_scene.global_position = $Sprite2D.global_position + Vector2(-64, -192)
	%Effects.add_child(death_scene)
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		_rpc_enemy_died.rpc()
	queue_free()

@rpc("authority", "call_remote", "reliable")
func _rpc_enemy_died() -> void:
	if not is_instance_valid(self):
		return
	var death_scene: Node2D = death_packed.instantiate()
	death_scene.global_position = $Sprite2D.global_position + Vector2(-64, -192)
	%Effects.add_child(death_scene)
	queue_free()

func _on_hit_box_area_entered(area: Area2D) -> void:
	var target: CharacterBody2D = area.owner
	if not is_instance_valid(target):
		return
	if not multiplayer.has_multiplayer_peer():
		target.take_damage(attack_damage)
	elif target.is_multiplayer_authority():
		target.take_damage(attack_damage)
	else:
		target.rpc_take_damage.rpc_id(target.get_multiplayer_authority(), attack_damage)

func _get_current_anim() -> String:
	match state:
		State.IDLE:
			return "idle"
		State.CHASE, State.RETURN:
			return "run"
		State.ATTACK:
			return "attack"
		_:
			return "idle"

@rpc("authority", "call_remote", "reliable")
func _sync_enemy(pos: Vector2, anim_name: String, flip: bool) -> void:
	DebugLog.log_msg("[ENEMY_SYNC_RECV] name=%s pos=%s anim=%s auth=%s" % [name, pos, anim_name, get_multiplayer_authority()])
	position = pos
	$Sprite2D.flip_h = flip
	match anim_name:
		"idle":
			if state != State.IDLE:
				state = State.IDLE
				update_animation()
		"run":
			if state != State.CHASE and state != State.RETURN:
				state = State.CHASE
				update_animation()
		"attack":
			if state != State.ATTACK:
				state = State.ATTACK
				update_animation()
