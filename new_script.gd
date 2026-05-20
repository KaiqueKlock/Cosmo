extends Node
# RelationshipManager.gd

var affinity_score: int = 0
var current_state: String = "neutral" # cold, neutral, friendly, attached

func _ready():
	# Sincroniza com a memória salva anteriormente se existir
	affinity_score = MemoryManager.current_memory.get("affinity_score", 0)
	update_state()

func add_affinity(amount: int):
	affinity_score += amount
	MemoryManager.current_memory["affinity_score"] = affinity_score
	MemoryManager.save_memory()
	update_state()

func update_state():
	if affinity_score <= -10:
		current_state = "cold"
	elif affinity_score < 15:
		current_state = "neutral"
	elif affinity_score < 40:
		current_state = "friendly"
	else:
		current_state = "attached"
