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
	var intent = cosmo_output.get("intent", "") # Certifique-se de retornar intent se necessário, ou use a lógica abaixo
	
	# Executa a fala typewriter do Cosmo
	await execute_cosmo_reaction(cosmo_output.get("text", "..."), cosmo_output.get("animation", "talking_animation"))
	
	# Intercepta as novas intenções de troca de modo de tela
	if "start_music_mode" in cosmo_output.get("text") or cosmo_brain.memory_data["conversation_context"]["current_game_mode"] == "music":
		# Se a intenção processada foi entrar na música, exibe o painel
		if music_player_panel.visible == false:
			_toggle_music_panel(true)
			_play_track(current_track_index) # Autoplay ao entrar
	
	if "exit_music_mode" in cosmo_output.get("text") or cosmo_brain.memory_data["conversation_context"]["current_game_mode"] == "normal":
		# Se o jogador pediu para sair do modo de música, esconde o painel
		if music_player_panel.visible == true:
			_toggle_music_panel(false)
			is_playing_music = false
	
	_reset_to_current_mood_animation()
	input_field.editable = true
	input_field.grab_focus()

# =====================================================
# VISUAL REACTION & TIMING (Com efeito Typewriter)
# =====================================================
func execute_cosmo_reaction(speech_text: String, anim_name: String) -> void:
	dialogue_label.text = speech_text
	dialogue_label.visible_ratio = 0.0
	print("Cosmo diz: ", speech_text)
	
	if animation_sprite.sprite_frames.has_animation(anim_name):
		animation_sprite.play(anim_name)
	elif animation_sprite.sprite_frames.has_animation("talking_animation"):
		animation_sprite.play("talking_animation")
		
	_setup_procedural_voice()
	
	var total_chars = speech_text.length()
	var current_visible = 0
	
	# Usamos um controle manual de tempo em vez do Tween linear puro, 
	# assim conseguimos pausar o tempo nas pontuações!
	while current_visible < total_chars:
		current_visible += 1
		dialogue_label.visible_ratio = float(current_visible) / float(total_chars)
		
		# Pega o caractere atual que acabou de aparecer
		var current_char = speech_text[current_visible - 1]
		
		# Base de tempo padrão por caractere (0.03s)
		var delay = 0.03
		
		# Injeta pausas dinâmicas conforme a pontuação gramatical
		if current_char == "," or current_char == ";":
			delay = 0.25 # Pausa curta para respirar na frase
		elif current_char == "." or current_char == "!" or current_char == "?":
			delay = 0.5 # Pausa longa em fins de frase
			
		# Se não for espaço ou pontuação pura, toca o som procedimental
		if current_char != " " and current_char != "\t" and not current_char in [".", ",", "!", "?", ";"]:
			_play_voice_beep_safe()
			
		# Aguarda o tempo calculado antes de avançar para o próximo caractere
		await get_tree().create_timer(delay).timeout
		
	if animation_sprite.animation == "talking_animation" and animation_sprite.sprite_frames.has_animation("listening_animation"):
		animation_sprite.play("listening_animation")
	
	# Tempo extra de leitura estático no final da frase
	await get_tree().create_timer(2.0).timeout


# Nova função auxiliar de áudio sem await interno para evitar deadlock de thread
func _play_voice_beep_safe() -> void:
	if is_instance_valid(voice_player):
		# Modulação sutil de pitch rápida e sem travar o processo
		voice_player.pitch_scale += randf_range(-0.05, 0.05)
		voice_player.play()



func _setup_procedural_voice() -> void:
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
		
		# Cosmo comenta de forma síncrona no painel de conversa
		dialogue_label.visible_ratio = 0.0
		dialogue_label.text = "Iniciando reprodução de: %s" % clean_name
		create_tween().tween_property(dialogue_label, "visible_ratio", 1.0, 0.5)
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
