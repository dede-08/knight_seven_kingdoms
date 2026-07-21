extends Node

@export var main_menu_packed: PackedScene
@export var game_scene_packed: PackedScene
@export var lobby_packed: PackedScene

func _ready() -> void:
	load_main_menu("game_start")

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func load_main_menu(origin: String) -> void:
	NetworkManager.disconnect_from_server()
	if origin == "end_game_screen":
		get_node("GameScene").queue_free()
	if has_node("Lobby"):
		get_node("Lobby").queue_free()
	var main_menu: Control = main_menu_packed.instantiate()
	main_menu.new_game_pressed.connect(new_game)
	main_menu.host_game_pressed.connect(host_game)
	main_menu.join_game_pressed.connect(join_game)
	main_menu.settings_pressed.connect(settings_open)
	main_menu.about_pressed.connect(about_open)
	main_menu.exit_pressed.connect(exit_game)
	add_child(main_menu)


func new_game(origin: String) -> void:
	if origin == "main_menu":
		get_node("MainMenu").queue_free()
	if origin == "end_game_screen":
		get_node("GameScene").queue_free()
		await get_tree().process_frame
	var game_scene: Node2D = game_scene_packed.instantiate()
	add_child(game_scene)


func host_game(origin: String) -> void:
	if origin == "main_menu":
		get_node("MainMenu").queue_free()
	var lobby: Control = lobby_packed.instantiate()
	lobby.start_game_pressed.connect(_lobby_start_game)
	lobby.back_pressed.connect(load_main_menu.bind("lobby"))
	add_child(lobby)
	lobby.setup("host")


func join_game(origin: String) -> void:
	if origin == "main_menu":
		get_node("MainMenu").queue_free()
	var lobby: Control = lobby_packed.instantiate()
	lobby.start_game_pressed.connect(_lobby_start_game)
	lobby.back_pressed.connect(load_main_menu.bind("lobby"))
	add_child(lobby)
	lobby.setup("join")


func _lobby_start_game() -> void:
	get_node("Lobby").queue_free()
	await get_tree().process_frame
	var game_scene: Node2D = game_scene_packed.instantiate()
	add_child(game_scene)


func settings_open(_origin: String) -> void:
	pass


func about_open(_origin: String) -> void:
	pass


func exit_game(_origin: String) -> void:
	get_tree().quit()
