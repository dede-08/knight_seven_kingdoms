extends CharacterBody2D

signal game_over(victorious: bool)
signal update_hp_bar(hp_bar_value: int)

enum State{
	IDLE,
	RUN,
	ATTACK,
	DEAD
}

@export_category("Stats")
@export var speed: int = 400
@export var attack_damage: int = 60
@export var hitpoints: int = 150

var state: State = State.IDLE
var move_direction: Vector2 = Vector2(0,0)
var attack_speed: float
var hitpoints_max: int

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_playback: AnimationNodeStateMachinePlayback = $AnimationTree["parameters/playback"]
@onready var sfx_attack: AudioStreamPlayer2D = $SfxAttack
@onready var sfx_hurt: AudioStreamPlayer2D = $SfxHurt
@onready var sfx_footstep: AudioStreamPlayer2D = $SfxFootstep

var _footstep_timer: float = 0.0
const FOOTSTEP_INTERVAL: float = 0.250
var _debug_frame: int = 0
var _logged_first_frame: bool = false
var _spawn_grace_frames: int = 5
const SPAWN_GRACE_TOTAL: int = 5

func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	hitpoints_max = hitpoints
	animation_tree.set_active(true)
	collision_mask = 0
	calculate_stats()
	DebugLog.log_msg("[READY] name=%s pos=%s auth=%s is_auth=%s group=%s" % [name, global_position, get_multiplayer_authority(), is_multiplayer_authority(), get_groups()])

func _unhandled_input(event: InputEvent) -> void:
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		attack()

func _physics_process(delta: float) -> void:
	if not _logged_first_frame:
		_logged_first_frame = true
		DebugLog.log_msg("[PHYS_FIRST] name=%s auth=%s is_auth=%s has_peer=%s pos=%s" % [name, get_multiplayer_authority(), is_multiplayer_authority(), multiplayer.has_multiplayer_peer(), global_position])
	if _spawn_grace_frames > 0:
		_spawn_grace_frames -= 1
		if _spawn_grace_frames == 0:
			collision_mask = 1
	if multiplayer.has_multiplayer_peer() and not is_multiplayer_authority():
		return
	_debug_frame += 1
	if _debug_frame % 30 == 1:
		DebugLog.log_msg("[PHYS] name=%s frame=%d pos=%s vel=%s move_dir=%s state=%s is_auth=%s" % [name, _debug_frame, global_position, velocity, move_direction, State.keys()[state], is_multiplayer_authority()])
	if not state == State.ATTACK:
		movement_loop()
	_update_footstep(delta)
	if multiplayer.has_multiplayer_peer():
		_sync_position.rpc(global_position, velocity, $Sprite2D.flip_h, _get_current_anim())

func _update_footstep(delta: float) -> void:
	if state == State.RUN:
		_footstep_timer += delta
		if _footstep_timer >= FOOTSTEP_INTERVAL:
			_footstep_timer = 0.0
			sfx_footstep.play()
	else:
		_footstep_timer = 0.0

func calculate_stats() -> void:
	attack_speed = Equations.calculate_attack_speed()
	var time_factor: float = Equations.BASE_ATTACK_SPEED / attack_speed
	animation_tree.set("parameters/attack/TimeScale/scale", time_factor)


func movement_loop() -> void:
	move_direction.x = int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left"))
	move_direction.y = int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	var motion: Vector2 = move_direction.normalized() * speed
	if _spawn_grace_frames > 0:
		return
	set_velocity(motion)
	if motion != Vector2.ZERO:
		move_and_slide()
	
	#sprite flipping just for the idle and run mode
	if state == State.IDLE or state == State.RUN:
		if move_direction.x < -0.01:
			$Sprite2D.flip_h = true
		elif move_direction.x > 0.01:
			$Sprite2D.flip_h = false
	
	if motion != Vector2.ZERO and state == State.IDLE:
		state = State.RUN
		update_animation()
	elif motion == Vector2.ZERO and state == State.RUN:
		state = State.IDLE
		update_animation()
	
	
func update_animation() -> void:
	match state:
		State.IDLE:
			animation_playback.travel("idle")
		State.RUN:
			animation_playback.travel("run")
		State.ATTACK:
			animation_playback.travel("attack")
			
			
func attack() -> void:
	if state == State.ATTACK:
		return
	state = State.ATTACK
	sfx_attack.play()
	
	#find the attack direction and push to animationtree blendspace2d
	var mouse_pos: Vector2 = get_global_mouse_position()
	var attack_dir: Vector2 = (mouse_pos - global_position).normalized()
	$Sprite2D.flip_h = attack_dir.x < 0 and abs(attack_dir.x) >= abs(attack_dir.y)
	animation_tree.set("parameters/attack/BlendSpace2D/blend_position", attack_dir)
	update_animation()
	
	# In multiplayer, send attack to server for processing
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_server_attack.rpc_id(1)
	
	#return the player state after attack has finished
	await get_tree().create_timer(attack_speed).timeout
	state = State.IDLE

func take_damage(damage_taken: int) -> void:
	hitpoints -= damage_taken
	update_hp_bar.emit((hitpoints * 100) / hitpoints_max)
	sfx_hurt.play()
	if hitpoints <= 0:
		death()

func death() -> void:
	game_over.emit(false)
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		_rpc_player_died.rpc_id(1)

func _on_hit_box_area_entered(area: Area2D) -> void:
	# In multiplayer, only server processes direct hit collisions
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	area.owner.take_damage(attack_damage)

func _get_current_anim() -> String:
	match state:
		State.IDLE:
			return "idle"
		State.RUN:
			return "run"
		State.ATTACK:
			return "attack"
		_:
			return "idle"

@rpc("authority", "call_remote", "reliable")
func _sync_position(pos: Vector2, vel: Vector2, flip: bool, anim_name: String) -> void:
	DebugLog.log_msg("[PLAYER_SYNC_RECV] name=%s pos=%s anim=%s" % [name, pos, anim_name])
	global_position = pos
	velocity = vel
	$Sprite2D.flip_h = flip
	match anim_name:
		"idle":
			if state != State.IDLE:
				state = State.IDLE
				update_animation()
		"run":
			if state != State.RUN:
				state = State.RUN
				update_animation()
		"attack":
			if state != State.ATTACK:
				state = State.ATTACK
				update_animation()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_server_attack() -> void:
	if not multiplayer.is_server():
		return
	var enemies: Array = get_tree().get_nodes_in_group("enemies")
	var nearest: CharacterBody2D = null
	var nearest_dist: float = 100.0
	for e: CharacterBody2D in enemies:
		if is_instance_valid(e):
			var dist: float = global_position.distance_to(e.global_position)
			if dist < nearest_dist:
				nearest_dist = dist
				nearest = e
	if nearest != null:
		nearest.take_damage(attack_damage)

@rpc("any_peer", "call_remote", "reliable")
func rpc_take_damage(damage: int) -> void:
	take_damage(damage)

@rpc("any_peer", "call_remote", "reliable")
func _rpc_player_died() -> void:
	if multiplayer.is_server():
		game_over.emit(false)
