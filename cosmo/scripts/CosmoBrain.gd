extends Node

class_name CosmoBrain


# =====================================================
# SIGNALS
# =====================================================

signal response_generated(response_text: String)
signal intent_detected(intent_name: String)


# =====================================================
# REFERENCES
# =====================================================

# AJUSTADO: Mudamos para AnimatedSprite2D e removemos o @onready com caminho fixo.
# O Main.gd injetará essa referência diretamente para evitar erros de nós.
var animation_player: AnimatedSprite2D = null

var mood_manager: MoodManager


# =====================================================
# DATA
# =====================================================
var storyteller_data: Dictionary = {}

var personality_data: Dictionary = {}

var memory_data: Dictionary = {}

var relationship_data: Dictionary = {}

var rng := RandomNumberGenerator.new()


# =====================================================
# INIT
# =====================================================

func _ready():

	rng.randomize()

	load_all_data()
	
	# AJUSTADO: Não chamamos mais o setup_mood_manager aqui, 
	# pois precisamos esperar o Main.gd injetar o nó visual primeiro.


# =====================================================
# LOADERS
# =====================================================

func load_all_data() -> void:
	storyteller_data = _load_json("res://cosmo/data/storyteller.json")

	personality_data = _load_json(
		"res://cosmo/data/personality.json"
	)

	relationship_data = _load_json(
		"res://cosmo/data/relationship.json"
	)

	# AJUSTADO: Carregamento resiliente. Tenta ler a memória salva do usuário primeiro.
	if FileAccess.file_exists("user://memory.json"):
		memory_data = _load_json("user://memory.json")
	else:
		memory_data = _load_json("res://cosmo/data/memory.json")

	

func _load_json(path: String) -> Dictionary:

	if not FileAccess.file_exists(path):
		push_error(
			"Missing file: %s" % path
		)
		return {}

	var file = FileAccess.open(
		path,
		FileAccess.READ
	)

	var content = file.get_as_text()

	var parsed = JSON.parse_string(
		content
	)

	if parsed == null:
		push_error(
			"Failed parsing JSON: %s" % path
		)
		return {}

	return parsed


# =====================================================
# MOOD SYSTEM
# =====================================================

func setup_mood_manager() -> void:

	var mood_json = _load_json(
		"res://cosmo/data/mood_system.json"
	)

	# Se o mood_manager já existia, remove para não duplicar filhos na árvore
	if is_instance_valid(mood_manager):
		mood_manager.queue_free()

	mood_manager = MoodManager.new()

	add_child(
		mood_manager
	)

	# AJUSTADO: Passa o AnimatedSprite2D correto injetado pelo Main
	mood_manager.initialize(
		mood_json,
		animation_player
	)


# =====================================================
# MAIN ENTRY
# =====================================================
func process_player_input(player_text: String) -> Dictionary:
	# 1. Armazena os estados iniciais para o relatório de telemetria
	var old_trust = 0
	if memory_data.has("relationship_context"):
		old_trust = memory_data["relationship_context"].get("trust_score", 0)
		
	var old_mood = "Desconhecido"
	if is_instance_valid(mood_manager):
		old_mood = mood_manager.get_current_mood()

	# 2. Executa o pipeline original do projeto
	var intent = detect_intent(player_text)
	emit_signal("intent_detected", intent)

	update_memory(intent, player_text)
	update_mood(intent)
	update_relationship(intent)

	# Se for o caso de nome, extrai e salva
	if intent == "provide_name":
		extract_and_save_name(player_text)

	var response = build_response(intent)
	save_memory()
	emit_signal("response_generated", response)

	# 3. PEGA OS ESTADOS FINAIS APÓS O PROCESSAMENTO
	var new_trust = 0
	if memory_data.has("relationship_context"):
		new_trust = memory_data["relationship_context"].get("trust_score", 0)
		
	var new_mood = "Desconhecido"
	if is_instance_valid(mood_manager):
		new_mood = mood_manager.get_current_mood()
		
	var identity = memory_data.get("player_identity", {"name": "Nenhum", "name_learned": false})

	# =====================================================
	# 🔥 RELATÓRIO DE TELEMETRIA DO CÉREBRO (DEBUG LOG)
	# =====================================================
	print("\n=== 🧠 COSMO BRAIN DIAGNOSTIC ===")
	print("💬 [Input do Jogador]: ", '"' + player_text + '"')
	print("🎯 [Intenção Detectada]: ", intent.to_upper())
	print("🎭 [Humor]: ", old_mood, " ➔ ", new_mood)
	print("🤝 [Confiança (Trust)]: ", old_trust, " ➔ ", new_trust)
	print("👤 [Dados de Identidade]: Aprendido? ", identity.get("name_learned"), " | Nome Salvo: ", identity.get("name"))
	print("📖 [Fala Escolhida]: ", '"' + response + '"')
	print("===================================\n")

		# 4. Retorno visual padrão do seu sistema (REPARADO)
	var suggested_animation = "talking_animation"
	
	if intent == "challenge" or intent == "laughter":
		suggested_animation = "smirking_animation"
	elif intent == "personal" or intent == "provide_name" or intent == "music" or intent == "start_music_mode":
		suggested_animation = "happy_animation"
	elif intent == "story" or intent == "farewell" or intent == "exit_music_mode":
		suggested_animation = "listening_animation"

	# INJETADO: Agora o dicionário passa a intenção correta de volta para a interface!
	return {
		"text": response,
		"animation": suggested_animation,
		"intent": intent
	} #Corrigindo player que parou de carregar ao passar o "intent" no retorno da função

# =====================================================
# INTENT DETECTION
# MVP VERSION
# =====================================================
func detect_intent(text: String) -> String:
	var lower_text = text.to_lower().strip_edges()

	# 1. PROVIDE_NAME (Mantemos por segurança antes de limpar pontuações, devido ao fatiamento)
	var name_triggers = ["meu nome é", "meu nome e", "me chame de", "sou o ", "sou a ", "my name is", "call me", "i am "]
	for trigger in name_triggers:
		if trigger in lower_text: 
			return "provide_name"

	# 2. LAUGHTER (Risadas - Padrão global)
	if "kkk" in lower_text or "hahaha" in lower_text or "rsrs" in lower_text or "lol" in lower_text:
		return "laughter"

	# -----------------------------------------------------------------
	# 🧼 LIMPEZA DE PONTUAÇÃO PARA EVITAR FALHAS (Ex: "tarde!" vira "tarde")
	# -----------------------------------------------------------------
	var clean_text = lower_text
	for char in [".", ",", "!", "?", ";", ":", "-", "(", ")"]:
		clean_text = clean_text.replace(char, " ")
	clean_text = clean_text.strip_edges()
	
	# Criamos um array de palavras isoladas para buscas exatas e velozes
	var words = clean_text.split(" ", false)

	# -----------------------------------------------------------------
	# REGRAS DO MODO MUSIC PLAYER (REPARADO E BLINDADO)
	# -----------------------------------------------------------------
	var music_tokens = ["música", "musica", "musicas", "music", "som", "tocar", "cantar", "ruido", "ruído", "player"]
	var exit_music_tokens = ["sair", "voltar", "fechar", "parar", "stop", "exit", "desligar", "ocultar"]
	
	# Inicializa a chave de modo na memória caso não exista no carregamento
	if not memory_data.has("conversation_context"):
		memory_data["conversation_context"] = {}
	if not memory_data["conversation_context"].has("current_game_mode"):
		memory_data["conversation_context"]["current_game_mode"] = "normal"
	
	var current_mode = memory_data["conversation_context"]["current_game_mode"]
	
	# REPARADO: Se o jogador usar um token explícito de saída, fecha o player de música
	for token in exit_music_tokens:
		if token in words:
			# Evita falsos positivos se a frase contiver "não fechar" etc.
			if current_mode == "music" or "player" in words or "musica" in words or "música" in words:
				memory_data["conversation_context"]["current_game_mode"] = "normal"
				return "exit_music_mode"
				
	# REPARADO: Se pedir música, retorna a intenção IMEDIATAMENTE, forçando a abertura do painel,
	# mesmo que a memória local esteja dessincronizada ou presa em um estado antigo de uma sessão anterior.
	for token in music_tokens:
		if token in words:
			memory_data["conversation_context"]["current_game_mode"] = "music"
			return "start_music_mode"
				
	# -----------------------------------------------------------------
	# REGRAS DO MODO HISTÓRIAS (OTIMIZADO)
	# -----------------------------------------------------------------


	# STORY_CONTINUE: Detecção de sequência narrativa estrita (Sem saudações misturadas)
	if "depois" in lower_text or "continua" in lower_text or "o que aconteceu" in lower_text or "conte mais" in lower_text:
		return "story"

	# STORY: Pedidos de histórias normais
	var story_tokens = ["história", "historia", "story", "conto", "contar", "conte"]
	for token in story_tokens:
		if token in words: 
			return "story"

	# CHALLENGE: Desafios e disputas
	var challenge_tokens = ["desafio", "challenge", "competir", "duelo", "jogar", "jogo"]
	for token in challenge_tokens:
		if token in words: 
			return "challenge"

	# PERSONAL: Estado, identidade, elogios profundos e concordâncias com o Cosmo
	var personal_tokens = ["você", "voce", "you", "seu", "sua", "te", "contigo", "ti"]
	var personal_qualifiers = [
		"bem", "esta", "status", "nome", "apelido", "fascinante", 
		"gostei", "gosto", "gosta", "ama", "odeia", "curte",
		"legal", "chato", "lindo", "inteligente", "criador",
		"comida", "cor", "hobby", "filme", "favorito", "favorita",
		"demais", "incrível", "incrivel", "foda", "observação", "observacao", "fato"
	]
	
	for p_token in personal_tokens:
		if p_token in words or p_token in clean_text:
			for qualifier in personal_qualifiers:
				if qualifier in words or qualifier in clean_text:
					return "personal"

	# FAREWELL: Despedidas (Varredura na string limpa completa)
	var farewell_tokens = ["tchau", "adeus", "bye", "fui", "saindo", "falou", "falo"]
	for token in farewell_tokens:
		if token in clean_text: 
			return "farewell"
			
	# GREETING: Saudações amplas imunes a prefixos e pontuações coladas
	var greeting_tokens = ["oi", "olá", "ola", "hello", "hi", "eae", "eai", "salve", "dia", "tarde", "noite"]
	for token in greeting_tokens:
		if token in words:
			return "greeting"

	return "unknown"


# =====================================================
# MEMORY
# =====================================================

func update_memory(intent: String, player_text: String) -> void:
	var session = memory_data["session"]
	session["interaction_count_total"] += 1

	var behavior = memory_data["player_behavior"]
	behavior["recent_intents"].append(intent)
	behavior["recent_messages"].append(player_text)

	# Se passar de 20 mensagens, remove a antiga para o JSON não explodir
	if behavior["recent_intents"].size() > 20:
		behavior["recent_intents"].pop_front()
		behavior["recent_messages"].pop_front()

	# Proteção: só incrementa se a chave existir dentro de intent_counters
	if behavior["intent_counters"].has(intent):
		behavior["intent_counters"][intent] += 1

	memory_data["conversation_context"]["last_intent"] = intent
	memory_data["conversation_context"]["last_player_message"] = player_text

	_detect_patterns()



func _detect_patterns():

	var counters = memory_data[
		"player_behavior"
	]["intent_counters"]


	if counters["music"] >= 3:

		memory_data[
			"pattern_detection"
		]["prefers_music"] = true


	if counters["story"] >= 3:

		memory_data[
			"pattern_detection"
		]["prefers_story"] = true


# =====================================================
# MOOD
# =====================================================

func update_mood(
	intent: String
) -> void:

	if not is_instance_valid(mood_manager): return

	match intent:

		"music":
			mood_manager.process_event(
				"music_request"
			)

		"story":
			mood_manager.process_event(
				"story_request"
			)

		"challenge":
			mood_manager.process_event(
				"challenge_request"
			)

		"personal":
			mood_manager.process_event(
				"player_returned"
			)

		_:
			pass


# =====================================================
# RELATIONSHIP
# =====================================================

func update_relationship(intent: String) -> void:
	# Acessa a nova chave de relacionamento do seu JSON v0.2
	if not memory_data.has("relationship_context"):
		return
		
	var rel_context = memory_data["relationship_context"]
	
	# Sistema simples de ganho de confiança baseado na intenção
	var trust_gain = 0
	match intent:
		"greeting": trust_gain = 1
		"music", "story": trust_gain = 2
		"personal": trust_gain = 3
		"challenge": trust_gain = -1 # Ele fica ligeiramente desconfiado
		"unknown": trust_gain = 0
		
	rel_context["trust_score"] += trust_gain
	
	# Impede que o score quebre limites (min -20, max 100)
	rel_context["trust_score"] = clampi(rel_context["trust_score"], -20, 100)



# =====================================================
# RESPONSE
# =====================================================

func build_response(intent: String) -> String:
	print("[Cérebro] Buscando falas para a intenção: ", intent)

	# =====================================================
	# 🔥 NOVO: DESVIO PROCEDURAL PARA MODO HISTÓRIA
	# =====================================================
	if intent == "story":
		var procedural_story = generate_procedural_story()
		# Alimenta o histórico de conversas da memória com a história gerada
		memory_data["conversation_context"]["last_response_used"] = procedural_story
		return procedural_story

	# Verificação padrão do JSON de personalidade (executada para as outras intenções)
	if not personality_data.has("intents") or not personality_data["intents"].has(intent):
		print("[Erro Cérebro] Intenção não encontrada no JSON de personalidade. Caindo no fallback.")
		return "Interessante..."

	var lines = personality_data["intents"][intent]
	var filtered_lines = []
	var last_response = memory_data["conversation_context"]["last_response_used"]

	# =====================================================
	# 🔥 SISTEMA DE REAÇÃO DINÂMICA POR CONFIANÇA (TRUST)
	# =====================================================
	if intent == "personal" and memory_data.has("relationship_context"):
		var trust_score = memory_data["relationship_context"].get("trust_score", 0)
		var temporary_lines = []
		
		if trust_score >= 30:
			# Respostas menos agressivas e mais cúmplices para quem tem alta confiança
			temporary_lines = [
				"Estou operacional. E... admito que suas perguntas estão se tornando toleráveis, [player_name].",
				"Minha integridade está em 98%. Fico feliz que seu hardware biológico se importe com isso.",
				"Como estou? Ocupado calculando dados. Mas abri uma thread de prioridade para te responder."
			]
		else:
			# Respostas sarcásticas e padrão para confiança baixa
			temporary_lines = lines
			
		lines = temporary_lines

	# Filtro anti-repetição padrão do seu projeto
	for line in lines:
		if line != last_response:
			filtered_lines.append(line)

	if filtered_lines.is_empty():
		filtered_lines = lines

	# Uso do seu gerador de números do projeto (rng) para manter a consistência de seeds
	var chosen_line = filtered_lines[rng.randi_range(0, filtered_lines.size() - 1)]
	chosen_line = apply_context(chosen_line)
	memory_data["conversation_context"]["last_response_used"] = chosen_line

	return chosen_line

# =====================================================
# CONTEXTUALIZATION
# =====================================================

func apply_context(line: String) -> String:
	var identity = memory_data["player_identity"]
	
	# 1. Substituição imediata da tag interna de nome
	if "[player_name]" in line:
		var current_name = identity.get("name", "Usuário")
		if current_name == null or current_name.is_empty():
			current_name = "Usuário"
		line = line.replace("[player_name]", current_name)
		return line

	if not memory_data.has("relationship_context"):
		return line
		
	var rel_context = memory_data["relationship_context"]
	var trust_score = rel_context["trust_score"]

	# 2. INJEÇÃO DINÂMICA: Transforma a palavra genérica "usuário" no nome do jogador se houver intimidade
	if identity["name_learned"] and identity["name"] != null and trust_score >= 25:
		if "usuário" in line.to_lower():
			# Substitui "usuário" ou "usuário." mantendo a capitalização correta
			line = line.replace("usuário", identity["name"])
			line = line.replace("usuário", identity["name"])

	# 3. Lógica existente de prefixo para turnos futuros baseados em Trust
	if identity["name_learned"] and identity["name"] != null and trust_score >= 35:
		if identity["times_name_used"] < 3 and not identity["name"] in line:
			line = "%s... %s" % [identity["name"], line]
			identity["times_name_used"] += 1

	return line

# =====================================================
# SAVE
# =====================================================

func delete_memory():
	pass

func save_memory():

	var file = FileAccess.open(
		"user://memory.json",
		FileAccess.WRITE
	)

	if file:

		file.store_string(
			JSON.stringify(
				memory_data,
				"\t"
			)
		)
		

func extract_and_save_name(player_text: String) -> void:
	var lower_text = player_text.to_lower()
	var name_found: String = ""
	
	# Lista de gatilhos comuns para fatiar a String
	var triggers = ["meu nome é", "meu nome e", "me chame de", "my name is", "call me"]
	for trigger in triggers:
		if trigger in lower_text:
			var idx = lower_text.find(trigger) + trigger.length()
			name_found = player_text.substr(idx).strip_edges()
			break
			
	# Gatilhos de verbos curtos (precisam de espaço depois para evitar falsos positivos)
	if name_found.is_empty():
		var short_triggers = ["sou o ", "sou a ", "i am "]
		for trigger in short_triggers:
			if trigger in lower_text:
				var idx = lower_text.find(trigger) + trigger.length()
				name_found = player_text.substr(idx).strip_edges()
				break

	# Se encontrou um candidato a nome, limpa pontuações de fim de frase
	if not name_found.is_empty():
		name_found = name_found.replace(".", "").replace("!", "").replace("?", "")
		# Capitaliza a primeira letra do nome por capricho visual
		name_found = name_found.capitalize()
		
		# Garante que a chave exista na memória antes de salvar
		if not memory_data.has("player_identity"):
			memory_data["player_identity"] = {
				"name": null,
				"name_learned": false,
				"times_name_used": 0
			}
			
		var identity = memory_data["player_identity"]
		identity["name"] = name_found
		identity["name_learned"] = true
		print("[Cérebro] Identidade atualizada! Nome do jogador salvo como: ", name_found)
		

# =================================================================
#  FUNÇÕES PROCESSUAIS DO GERADOR DE HISTÓRIAS (FINAL DO ARQUIVO)
# =================================================================

func generate_procedural_story() -> String:
	# REMOVIDO: A chamada ao MoodManager foi retirada para evitar o erro de função inexistente.
	# O seu pipeline original já atualiza o humor automaticamente no 'process_player_input'.
	
	var intro: String = _get_unique_chunk("intro")
	var tech: String = _get_unique_chunk("tech_context")
	var twist: String = _get_unique_chunk("twist_bug")
	var conclusion: String = _get_unique_chunk("conclusion")
	
	# Injetamos as tags visuais. O Main.gd lerá e trocará as animações da face do Cosmo.
	var full_story: String = "[mood:thinking]" + intro + tech + twist + " [mood:smug]" + conclusion
	
	return apply_context(full_story)

func _get_unique_chunk(category: String) -> String:
	# Segurança: caso o JSON falhe ou não tenha a chave, evita crash do jogo
	if not storyteller_data or not storyteller_data.has(category):
		print("[Erro Cérebro] Categoria '", category, "' não encontrada no storyteller_data.")
		return " [Erro de Dados] "
		
	# Injeta dinamicamente a estrutura de histórico dentro da memória da sessão
	if not memory_data.has("story_history_cache"):
		memory_data["story_history_cache"] = {
			"intro": [],
			"tech_context": [],
			"twist_bug": [],
			"conclusion": []
		}
		
	var local_history: Dictionary = memory_data["story_history_cache"]
	var local_max_history: int = 2
		
	var pool: Array = storyteller_data[category]
	var valid_indices: Array = []
	
	# Varre o pool filtrando pelo histórico salvo na memória
	for i in range(pool.size()):
		if not local_history[category].has(i):
			valid_indices.append(i)
			
	# Fallback caso trave o histórico (limpa a categoria)
	if valid_indices.is_empty():
		local_history[category].clear()
		for i in range(pool.size()):
			valid_indices.append(i)
			
	# Sorteia e atualiza a fila de anti-repetição
	var chosen_index: int = valid_indices[randi() % valid_indices.size()]
	local_history[category].append(chosen_index)
	
	if local_history[category].size() > local_max_history:
		local_history[category].pop_front()
		
	return pool[chosen_index]
