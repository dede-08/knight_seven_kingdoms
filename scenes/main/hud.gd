extends Control

func _ready() -> void:
	update_level_indicator()

func update_hp_bar(new_value: int) -> void:
	%HitpointsBar.value = new_value

func update_level_indicator() -> void:
	%CurrentLevel.set_text(str(PlayerData.level))
