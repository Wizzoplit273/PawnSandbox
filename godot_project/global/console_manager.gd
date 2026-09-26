extends Node

func execute_raw_string(raw_string: String) -> void:
	raw_string = raw_string.strip_edges()
	if raw_string.begins_with("/"): raw_string = raw_string.substr(1)
	var tokens: PackedStringArray = raw_string.split(" ", false)
	if tokens[0] == "set_url":
		NetworkManager.set_url(tokens[1])
		UIManager.send_local_message("URL set to " + tokens[1])
