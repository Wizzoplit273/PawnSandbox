extends TextureRect

func _ready() -> void:
	$Container/Version.text = "Version " + ProjectSettings.get_setting("application/config/version")
