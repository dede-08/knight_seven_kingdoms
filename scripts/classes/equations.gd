class_name Equations
extends Node

const BASE_ATTACK_SPEED: float = 0.6

static func calculate_attack_speed() -> float:
	var attack_speed: float = BASE_ATTACK_SPEED * (1 - 0.15 * (PlayerData.level - 1))
	return attack_speed
