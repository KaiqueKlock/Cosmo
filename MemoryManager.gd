extends Node
# MemoryManager.gd

const SAVE_PATH = "user://memory.json"
var current_memory = {}

func _ready():
	load_memory()

func load_memory():
	if not FileAccess.file_exists(SAVE_PATH):
		# Memória inicial padrão se for a primeira vez jogando
		current_memory = {
			"player_name": "Humano",
			"interaction_count": 0,
			"intent_history": [],
			"preferred_topics": {}
		}
		save_memory()
		return
		
	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	if json.parse(json_string) == OK:
		current_memory = json.get_data()

func save_memory():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	var json_string = JSON.stringify(current_memory, "\t")
	file.store_string(json_string)
	file.close()

func increment_interaction(intent: String):
	current_memory["interaction_count"] += 1
	current_memory["intent_history"].append(intent)
	
	# Limita histórico aos últimos 20 inputs para não inflar o arquivo
	if current_memory["intent_history"].size() > 20:
		current_memory["intent_history"].pop_front()
		
	save_memory()
