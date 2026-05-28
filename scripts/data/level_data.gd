extends Node

const MAX_LEVEL: int = 5
const LEVEL_THRESHOLDS: Array[int] = [
	500,   #level 1 > 2
	900,   #level 2 > 3
	2500,  #level 3 > 4
	6300   #level 4 > 5
]
