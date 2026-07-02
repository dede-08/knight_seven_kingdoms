extends AudioStreamPlayer

func _ready() -> void:
	stream = preload("res://assets/audio/sfx/medieval-music-cobblestone-village-0-hrzoi.wav")
	finished.connect(play)
	play()
