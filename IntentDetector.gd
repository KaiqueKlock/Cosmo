extends Node
# IntentDetector.gd

var keywords = {
	"greeting": ["oi", "olá", "ola", "eae", "salve", "bom dia"],
	"music": ["música", "musica", "som", "cantando", "tocar"],
	"story": ["história", "historia", "me conta", "conto", "passado"],
	"personal": ["você", "voce", "seu nome", "quem é", "criador"]
}

func detect_intent(text: String) -> String:
	var clean_text = text.to_lower().strip_edges()
	
	for intent in keywords.keys():
		for keyword in keywords[intent]:
			if keyword in clean_text:
				return intent
				
	return "challenge" # Default se o Cosmo não entender (ele se sente desafiado)
