extends Node
class_name MoodManager

signal mood_changed(old_mood: String, new_mood: String)

# ==========================================
# DATA
# ==========================================

var mood_data: Dictionary = {}

var current_mood: String = "bored"
var previous_mood: String = ""

var last_trigger: String = ""

var last_mood_change_time: float = 0.0

# AJUSTADO: Conecta com o visual em AnimatedSprite2D
var animation_player: AnimatedSprite2D = null


# ==========================================
# SETUP
# ==========================================

func initialize(
	data: Dictionary,
	anim_player: AnimatedSprite2D = null # AJUSTADO TIPAGEM
) -> void:

	mood_data = data

	animation_player = anim_player

	current_mood = mood_data.get(
		"current_mood",
		"bored"
	)

	previous_mood = mood_data.get(
		"previous_mood",
		""
	)

	last_mood_change_time = Time.get_unix_time_from_system()


# ==========================================
# MAIN ENTRY
# ==========================================

func process_event(event_name: String) -> bool:

	if not can_change_mood():
		return false

	var triggers = mood_data.get("triggers", {})

	if not triggers.has(event_name):
		return false

	var target_mood = triggers[event_name]

	return change_mood(
		target_mood,
		event_name
	)


# ==========================================
# CHANGE MOOD
# ==========================================

func change_mood(
	new_mood: String,
	trigger_name: String = "manual"
) -> bool:

	if new_mood == current_mood:
		return false

	if not mood_exists(new_mood):
		push_warning(
			"Mood '%s' does not exist." % new_mood
		)
		return false

	previous_mood = current_mood

	current_mood = new_mood

	last_trigger = trigger_name

	last_mood_change_time = Time.get_unix_time_from_system()

	_save_state()

	_play_current_animation()

	emit_signal(
		"mood_changed",
		previous_mood,
		current_mood
	)

	return true


# ==========================================
# VALIDATION
# ==========================================

func mood_exists(mood_name: String) -> bool:

	var moods = mood_data.get("moods", {})

	return moods.has(mood_name)


func can_change_mood() -> bool:

	var cooldown_data = mood_data.get(
		"cooldowns",
		{}
	)

	var cooldown = cooldown_data.get(
		"mood_change_seconds",
		0
	)

	var now = Time.get_unix_time_from_system()

	var elapsed = now - last_mood_change_time

	return elapsed >= cooldown


# ==========================================
# ANIMATION
# ==========================================

func _play_current_animation() -> void:

	if animation_player == null:
		return

	var animation_name = get_current_animation()

	if animation_name.is_empty():
		return

	# AJUSTADO: Verificação nativa para AnimatedSprite2D usando sprite_frames
	if animation_player.sprite_frames and animation_player.sprite_frames.has_animation(
		animation_name
	):
		animation_player.play(
			animation_name
		)


func get_current_animation() -> String:

	var moods = mood_data.get(
		"moods",
		{}
	)

	if not moods.has(current_mood):
		return ""

	return moods[current_mood].get(
		"default_animation",
		""
	)


# ==========================================
# MOOD INFO
# ==========================================

func get_current_mood() -> String:
	return current_mood


func get_previous_mood() -> String:
	return previous_mood


func get_last_trigger() -> String:
	return last_trigger


func get_mood_intensity() -> int:

	var moods = mood_data.get(
		"moods",
		{}
	)

	if not moods.has(current_mood):
		return 0

	return moods[current_mood].get(
		"intensity",
		0
	)


# ==========================================
# HISTORY
# ==========================================

func _save_state() -> void:

	mood_data["current_mood"] = current_mood

	mood_data["previous_mood"] = previous_mood

	if not mood_data.has("history"):
		mood_data["history"] = []

	mood_data["history"].append({

		"from": previous_mood,

		"to": current_mood,

		"trigger": last_trigger,

		"time": Time.get_unix_time_from_system()

	})


func get_history() -> Array:

	return mood_data.get(
		"history",
		[]
	)


func clear_history() -> void:

	mood_data["history"] = []


# ==========================================
# UTILITIES
# ==========================================

func reset_to_default() -> void:

	change_mood(
		"bored",
		"reset"
	)


func force_mood(
	new_mood: String
) -> void:

	previous_mood = current_mood

	current_mood = new_mood

	last_trigger = "forced"

	last_mood_change_time = Time.get_unix_time_from_system()

	_save_state()

	_play_current_animation()
