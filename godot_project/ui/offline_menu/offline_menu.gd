extends TextureRect

func _ready() -> void:
	$Container/Version.text = "Version " + ProjectSettings.get_setting("application/config/version")

func _on_join_button_pressed() -> void:
	NetworkManager.start_client()
