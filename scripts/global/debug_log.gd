extends Node

var _file: FileAccess
var _role: String = "unknown"

func _ready() -> void:
	_file = FileAccess.open("user://debug_log.txt", FileAccess.WRITE)
	log_msg("=== Game started ===")


func set_role(role: String) -> void:
	_role = role
	if _file and _file.is_open():
		_file.close()
	_file = FileAccess.open("user://debug_%s.txt" % role, FileAccess.WRITE)
	log_msg("=== %s started ===" % role)


func log_msg(msg: String) -> void:
	if _file and _file.is_open():
		_file.store_line(msg)
		_file.flush()
