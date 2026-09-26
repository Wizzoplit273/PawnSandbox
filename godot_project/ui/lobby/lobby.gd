extends Control

func append_message(sender_id: int, message: String) -> void:
	var id: String = str(sender_id)
	if sender_id == 0: id = "OFFLINE"
	if sender_id < 0: id = "*** " ## join/leave/system message
	var line: String = id + ": " + message + "\n"
	%ChatLabel.text += line

func _on_chat_input_text_submitted(new_text: String) -> void:
	%ChatInput.clear()
	append_message(NetworkManager.my_id, new_text)
	UIManager.send_network_message(0, new_text)
