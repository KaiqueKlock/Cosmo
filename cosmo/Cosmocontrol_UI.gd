extends Node


@onready var face = $"../Face"

@onready var anim_player = $"../AnimationPlayer"

@onready var mood_manager = $"../MoodManager"



func _ready():

	mood_manager.connect(
		"mood_changed",
		_on_mood_changed
	)

	anim_player.play(
		"idle"
	)



func _on_mood_changed(
	new_mood:String
) -> void:

	var animation_name = get_ui_animation_for_mood(
		new_mood
	)

	anim_player.play(
		animation_name
	)



func get_ui_animation_for_mood(
	mood:String
) -> String:

	match mood:

		"bored":
			return "idle"

		"curious":
			return "thinking"

		"amused":
			return "smirking"

		"suspicious":
			return "thinking"

		"excited":
			return "happy"

		_:
			return "idle"



func play_talking():

	anim_player.play(
		"saying"
	)



func stop_talking():

	var mood = mood_manager.get_mood()

	var anim = get_ui_animation_for_mood(
		mood
	)

	anim_player.play(
		anim
	)
