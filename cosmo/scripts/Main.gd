extends Control
# Main.gd (Anexado ao nó raiz "Control")

# =====================================================
# REFERENCES (Rotas Diretas sem usar o % )
# =====================================================

# Caminho exato descendo pelos seus containers reais da imagem:
@onready var animation_sprite: AnimatedSprite2D = $GameContainer/FaceContainer/CosmoFace/Face/AnimatedSprite2D

@onready var dialogue_label: Label = $GameContainer/DialogueContainer/DialogueLabel
@onready var input_field: LineEdit = $InputField

@onready var cosmo_brain: CosmoBrain = $CosmoBrain


@onready var voice_player: AudioStreamPlayer = $VoicePlayer

# Nova Referência para o Painel de Música
@onready var music_player_panel: PanelContainer = $GameContainer/MusicPlayerPanel
@onready var play_button: Button = $GameContainer/MusicPlayerPanel/HBoxContainer/Play
@onready var pause_button: Button = $GameContainer/MusicPlayerPanel/HBoxContainer/Pause
@onready var next_button: Button = $GameContainer/MusicPlayerPanel/HBoxContainer/Next
@onready var bg_music_player: AudioStreamPlayer = $BackgroundMusicPlayer
@onready var current_track_label: Label = %CurrentTrackLabel

# Trava de segurança para impedir que a voz mude o sprite durante animações especiais
var _lock_talking_animation: bool = false

# Simulação da Playlist interna do Cosmo
var playlist: Array[String] = [
	"res://cosmo/playlist/Montanha Russa Beat C 83 BPM.wav",
	"res://cosmo/playlist/Em Busca do Infinito 113BPM Gm.wav",
	"res://cosmo/playlist/FASHION!!! D 120 e 155 bpm.mp3"
]
var current_track_index: int = 0
var is_playing_music: bool = false

# =====================================================
# LIFECYCLE
# =====================================================
func _ready() -> void:
	await get_tree().process_frame
	
	if is_instance_valid(cosmo_brain) and is_instance_valid(animation_sprite):
		cosmo_brain.animation_player = animation_sprite
		cosmo_brain.setup_mood_manager()
	
	_reset_to_current_mood_animation()
	dialogue_label.text = "..."
	
	# Garante o estado inicial invisível do painel
	music_player_panel.visible = false
	music_player_panel.modulate.a = 0.0
	
	# Conecta os sinais físicos dos botões que você já criou
	play_button.pressed.connect(_on_play_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	next_button.pressed.connect(_on_next_pressed)
	
	# 🔥 INJETADO: Inicializa o motor de fala nativo do S.O.
	_initialize_cosmo_tts()


# Variável global para armazenar o ID da voz do Cosmo
var _cosmo_voice_id: String = ""

func _initialize_cosmo_tts() -> void:
	
	var available_voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("pt")
	
	print("\n=== 🎙️ VOZES DETECTADAS NO SISTEMA ===")
	for i in range(available_voices.size()):
		print("Índice [", i, "]: ", available_voices[i])
	print("======================================\n")
	
	# Fallback: Se não encontrar vozes explícitas em português, tenta buscar as globais
	if available_voices.is_empty():
		# tts_get_voices() retorna um Array[Dictionary]. Aqui sim precisaríamos extrair.
		# Mas para blindar contra falhas e manter o padrão simples do PackedStringArray:
		var global_voices = DisplayServer.tts_get_voices()
		if not global_voices.is_empty():
			# Pega o ID de dicionário se vier do método global corporativo
			_cosmo_voice_id = global_voices[0].get("id", "")
	else:
		# CORREÇÃO: Como 'available_voices' é um PackedStringArray, pegamos o índice diretamente!
		_cosmo_voice_id = available_voices[0]
		
	if not _cosmo_voice_id.is_empty():
		print("[TTS] Sistema sincronizado! ID da voz ativa: ", _cosmo_voice_id)
	else:
		print("[TTS Alerta] O Cosmo está mudo. Nenhuma voz de síntese nativa foi identificada no S.O.")


# =====================================================
# PIPELINE ENTRY
# =====================================================
func _on_input_field_text_submitted(_text: String) -> void:
	var clean_text = input_field.text.strip_edges()
	if clean_text.is_empty():
		input_field.clear()
		return
		
	input_field.clear()
	input_field.editable = false
	
	dialogue_label.text = "..."
	if animation_sprite.sprite_frames.has_animation("thinking_animation"):
		animation_sprite.play("thinking_animation")
		
	await get_tree().create_timer(1.2).timeout
	
	var cosmo_output: Dictionary = cosmo_brain.process_player_input(clean_text)
	var intent: String = cosmo_output.get("intent", "unknown")
	
	# Executa a fala typewriter e o TTS real do Cosmo de forma assíncrona
	await execute_cosmo_reaction(cosmo_output.get("text", "..."), cosmo_output.get("animation", "talking_animation"))
	
	# -----------------------------------------------------------------
	# CONTROLE RIGOROSO DE INTERFACE BASEADO NO TOKEN DE INTENÇÃO
	# -----------------------------------------------------------------
	if intent == "start_music_mode":
		# CORREÇÃO DE SEGURANÇA: Limpa completamente o stream procedural de beeps 
		# para dar liberdade total ao player carregar as faixas reais .wav sem conflitos
		if is_instance_valid(voice_player):
			voice_player.stop()
			voice_player.stream = null 
		
		# Força a visibilidade imediata para garantir que o contêiner receba os comandos
		music_player_panel.visible = true
		
		# Executa a sua rotina nativa de animação por Tween que você criou
		_toggle_music_panel(true)
		
		# Dispara a reprodução real da faixa de música (.wav)
		_play_track(current_track_index)
			
	elif intent == "exit_music_mode":
		_toggle_music_panel(false)
		is_playing_music = false
		if is_instance_valid(voice_player):
			voice_player.stop()
			
	# Só executa o reset automático de animação se o jogador NÃO estiver no modo música.
	if intent != "start_music_mode" and cosmo_brain.memory_data["conversation_context"]["current_game_mode"] != "music":
		_reset_to_current_mood_animation()
		
	input_field.editable = true
	input_field.grab_focus()

# =====================================================
# VISUAL REACTION & TIMING (Com efeito Typewriter e TTS)
# =====================================================
func execute_cosmo_reaction(speech_text: String, anim_name: String) -> void:
	# 1. PROCESSAMENTO DE TAGS: Varre e identifica se existem humores na string
	var thinking_index: int = speech_text.find("[mood:thinking]")
	var smug_index: int = speech_text.find("[mood:smug]")
	
	# Controladores booleanos estáveis para a máquina visual do typewriter
	var is_thinking: bool = (thinking_index != -1)
	var is_smug: bool = false
	
	# Limpa os metadados textuais da string para não vazar na tela do terminal
	if thinking_index != -1:
		speech_text = speech_text.replace("[mood:thinking]", "")
		if smug_index != -1 and smug_index > thinking_index:
			smug_index -= 15 # Compensa os 15 caracteres removidos da primeira tag
			
	if smug_index != -1:
		speech_text = speech_text.replace("[mood:smug]", "")
		
	# Configura a interface com o texto limpo
	dialogue_label.text = speech_text
	dialogue_label.visible_ratio = 0.0
	
	# Garante a integridade física do nó de som original do projeto para os outros modos (Música)
	_setup_procedural_voice()
	
	# Define a velocidade e a animação do começo da frase
	var current_anim: String = anim_name
	var base_pitch_tts: float = 1.0 # Padrão do TTS do DisplayServer (0.0 a 2.0)
	
	if is_thinking:
		current_anim = "thinking"
		base_pitch_tts = 0.85 # Tom de voz levemente mais sóbrio e focado para a lore
			
	if animation_sprite.sprite_frames.has_animation(current_anim):
		animation_sprite.play(current_anim)
	elif animation_sprite.sprite_frames.has_animation("talking_animation"):
		animation_sprite.play("talking_animation")
		
	print("Cosmo diz: ", speech_text)
	
	# DISPARO DO TTS NATIVO: Fala o bloco INTEIRO linearmente sem interrupções
	if not _cosmo_voice_id.is_empty():
		DisplayServer.tts_stop() # Limpa buffers anteriores de segurança
		# Deixamos o Windows ditar a história toda de forma fluida e sem cortes mecânicos
		DisplayServer.tts_speak(speech_text, _cosmo_voice_id, 100, 1.15, 1.7)

	
	var total_chars = speech_text.length()
	var current_visible = 0
	
	# 2. LOOP DE TYPEWRITER COM EVENTOS EM TEMPO REAL
	while current_visible < total_chars:
		# EVENTO VISUAL SINCRONIZADO: O cursor de letras atingiu a reviravolta sarcástica?
		if smug_index != -1 and current_visible == smug_index:
			is_thinking = false
			is_smug = true
			
			# Chaveia visualmente o rosto para smug imediatamente na tela
			if animation_sprite.sprite_frames.has_animation("smug"):
				animation_sprite.play("smug")
				
			# REPARADO: Removemos o tts_stop() e o segundo tts_speak daqui de dentro!
			# A voz Maria continuará lendo a história organicamente até o fim sem ser cortada,
			# enquanto o rosto muda para o deboche visual de forma teatral e sincronizada.
			
			await get_tree().create_timer(0.3).timeout # Pequena pausa dramática na digitação
			smug_index = -1 # Consome o gatilho único
			
		current_visible += 1
		dialogue_label.visible_ratio = float(current_visible) / float(total_chars)
		
		var char_index = current_visible - 1
		if char_index >= total_chars:
			break
			
		var current_char = speech_text[char_index]
		var delay = 0.045 # Velocidade estável calibrada para leitura confortável
		
		if current_char == "," or current_char == ";":
			delay = 0.25
		elif current_char == "." or current_char == "!" or current_char == "?":
			delay = 0.55
			
		if current_char != " " and current_char != "\t" and not current_char in [".", ",", "!", "?", ";"]:
			# Sustenta ativamente as expressões na tela impedindo glitches nativos
			if is_thinking and animation_sprite.animation != "thinking":
				animation_sprite.play("thinking")
			elif is_smug and animation_sprite.animation != "smug":
				animation_sprite.play("smug")
			
		await get_tree().create_timer(delay).timeout
		
	# 3. MÁQUINA DE ESTADO FINAL: Retorna para o modo de escuta ativa
	if animation_sprite.sprite_frames.has_animation("listening_animation"):
		animation_sprite.play("listening_animation")
		
	# Reseta as configurações procedimentais do buffer para dar prioridade ao player de música
	_setup_procedural_voice()
	await get_tree().create_timer(1.5).timeout

# Isso garante que a onda senoidal gerada em '_setup_procedural_voice' seja tocada perfeitamente
func _play_voice_beep_safe() -> void:
	if is_instance_valid(voice_player):
		var base_pitch: float = voice_player.pitch_scale
		
		# Aplica a microvariação estrita de sintetizador apenas no disparo de áudio atual
		voice_player.pitch_scale = base_pitch + randf_range(-0.04, 0.04)
		voice_player.play()
		
		# Restaura imediatamente o valor base para o próximo caractere
		voice_player.pitch_scale = base_pitch
	else:
		print("[Erro Cérebro Main] Objeto 'voice_player' não possui instância válida carregada!")


func _setup_procedural_voice() -> void:
	if not is_instance_valid(voice_player):
		return
		
	# CORRIGIDO: Alterado de AudioStreamWav para AudioStreamWAV
	if voice_player.stream == null or not (voice_player.stream is AudioStreamWAV):
		var sample_rate = 44100.0
		var duration = 0.04 # Duração de cada bíp em segundos (bem curto)
		var frequency = 220.0 # Frequência base em Hz (som mais grave e robótico)
		
		var audio_buffer = PackedByteArray()
		var total_samples = int(sample_rate * duration)
		audio_buffer.resize(total_samples * 2) # 16-bit precisa de 2 bytes por amostra
		
		for i in range(total_samples):
			var t = float(i) / sample_rate
			var sample = sin(2.0 * PI * frequency * t)
			
			# Fade-out linear muito rápido para evitar estalos (clicks) de áudio no final do bíp
			var envelope = 1.0 - (float(i) / float(total_samples))
			sample *= envelope
			
			var value = int(sample * 32767.0)
			audio_buffer.encode_s16(i * 2, value)
			
		# CORRIGIDO: Instanciação usando a classe correta AudioStreamWAV
		var new_stream = AudioStreamWAV.new()
		new_stream.data = audio_buffer
		# CORRIGIDO: FORMAT_16_BITS agora pertence ao escopo de AudioStreamWAV
		new_stream.format = AudioStreamWAV.FORMAT_16_BITS
		new_stream.mix_rate = int(sample_rate)
		
		voice_player.stream = new_stream

	# AJUSTE DINÂMICO DE PITCH BASEADO NO HUMOR:
	if cosmo_brain and cosmo_brain.mood_manager:
		var intensity = cosmo_brain.mood_manager.get_mood_intensity()
		var mood = cosmo_brain.mood_manager.get_current_mood()
		
		match mood:
			"excited":
				voice_player.pitch_scale = 1.4
			"suspicious":
				voice_player.pitch_scale = 0.85
			"bored":
				voice_player.pitch_scale = 1.0
			_:
				voice_player.pitch_scale = 1.0 + (intensity * 0.1)


func _play_voice_beep() -> void:
	if is_instance_valid(voice_player):
		# Modula levemente o pitch de cada bíp de forma aleatória para não soar repetitivo ou irritante
		var original_pitch = voice_player.pitch_scale
		voice_player.pitch_scale += randf_range(-0.07, 0.07)
		voice_player.play()
		# Restaura o pitch base após tocar
		await voice_player.finished
		voice_player.pitch_scale = original_pitch


func _reset_to_current_mood_animation() -> void:
	# Verifica o humor atual do MoodManager e puxa a animação correspondente
	if cosmo_brain and cosmo_brain.mood_manager:
		var current_mood_anim = cosmo_brain.mood_manager.get_current_animation()
		if not current_mood_anim.is_empty() and animation_sprite.sprite_frames.has_animation(current_mood_anim):
			animation_sprite.play(current_mood_anim)
			return
			
	# Fallback padrão caso os sistemas de dados não estejam prontos
	if animation_sprite.sprite_frames.has_animation("idle_animation"):
		animation_sprite.play("idle_animation")

# =====================================================
# UI ANIMATION & MUSIC CONTROLS
# =====================================================
func _toggle_music_panel(show_panel: bool) -> void:
	var tween = create_tween().set_parallel(true)
	
	if show_panel:
		music_player_panel.visible = true
		tween.tween_property(music_player_panel, "modulate:a", 1.0, 0.4).set_trans(Tween.TRANS_SINE)
		print("[Interface] Painel de música exibido.")
	else:
		var fade_tween = create_tween()
		fade_tween.tween_property(music_player_panel, "modulate:a", 0.0, 0.3).set_trans(Tween.TRANS_SINE)
		await fade_tween.finished
		music_player_panel.visible = false
		# Para a música real imediatamente ao fechar a tela
		if bg_music_player.is_playing():
			bg_music_player.stop()
		print("[Interface] Painel de música ocultado.")


func _play_track(index: int) -> void:
	if playlist.is_empty():
		push_error("[Erro Player] A lista de arquivos .wav está vazia.")
		return
		
	current_track_index = index
	var track_path = playlist[current_track_index]
	
	# Verifica se o arquivo físico realmente existe no disco antes de carregar
	if not ResourceLoader.exists(track_path):
		push_error("[Erro Player] Arquivo não encontrado: " % track_path)
		dialogue_label.text = "Erro ao carregar trilha sonora..."
		return
		
	# CARREGAMENTO DINÂMICO: Transforma o caminho de string em um recurso executável
	var stream_resource = load(track_path)
	
	if stream_resource:
		bg_music_player.stream = stream_resource
		bg_music_player.play()
		
		# Extrai apenas o nome limpo do arquivo para exibir na interface visual
		var clean_name = track_path.get_file().replace(".wav", "").capitalize()
		current_track_label.text = clean_name
		
		# REPARADO: Removemos o Tween bruto que resetava a dialogue_label de forma agressiva.
		# Se o jogador acabou de pedir a música, mantemos a fala satírica do Cosmo na tela.
		# Atualizamos apenas o status da faixa no terminal de logs.
		print("[Music Player] Tocando arquivo real: ", clean_name)

func _on_play_pressed() -> void:
	# Se a música estava pausada no meio, apenas retoma sem recarregar do zero
	if bg_music_player.stream != null and not bg_music_player.is_playing():
		bg_music_player.play()
		# Descobre o ponto onde parou para continuar nativamente do mesmo segundo
		bg_music_player.seek(bg_music_player.get_playback_position())
		dialogue_label.text = "Áudio retomado."
		_play_voice_beep_safe()


func _on_pause_pressed() -> void:
	if bg_music_player.is_playing():
		bg_music_player.stop() # No Godot 4, stop() limpa o canal mas retém a playback position ao dar play novamente
		dialogue_label.text = "Música pausada por ordens humanas."
		_play_voice_beep_safe()


func _on_next_pressed() -> void:
	# Rotaciona o índice matematicamente pelo tamanho do seu array de caminhos .wav
	var next_index = (current_track_index + 1) % playlist.size()
	_play_track(next_index)
