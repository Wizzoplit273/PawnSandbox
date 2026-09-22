extends Node

var offline_menu: Control = null
var lobby: Control = null

const PRIVATE_CHAT_PREFIX: String = "PRIVATE "
const SYSTEM_CHAT_PREFIX: String = "SYSTEM "

func _enter_tree() -> void:
	create_offline_menu()
	create_lobby()
	NetworkManager.connect(&"global_chat", _on_network_global_chat)
	NetworkManager.connect(&"private_chat", _on_network_private_chat)
	NetworkManager.connect(&"system_chat", _on_network_system_chat)

const OFFLINE_MENU_SCENE_PATH: String = "res://ui/offline_menu/offline_menu.tscn"
func create_offline_menu() -> void:
	offline_menu = load(OFFLINE_MENU_SCENE_PATH).instantiate()
	add_child(offline_menu)

const LOBBY_SCENE_PATH: String = "res://ui/lobby/lobby.tscn"
func create_lobby() -> void:
	lobby = load(LOBBY_SCENE_PATH).instantiate()
	add_child(lobby)

func send_message(target_id: int, message: String) -> void:
	if target_id < 0: return
	if NetworkManager.my_id <= 0: return
	var payload: PackedByteArray = var_to_bytes(message)
	if target_id == 0: NetworkManager.send_data(NetworkManager.PacketType.GLOBAL_CHAT, 0, payload)
	if target_id > 0: NetworkManager.send_data(NetworkManager.PacketType.PRIVATE_CHAT, target_id, payload)

func _on_network_global_chat(sender_id: int, message: String) -> void:
	if not lobby: return
	lobby.append_message(sender_id, message)

func _on_network_private_chat(sender_id: int, message: String) -> void:
	if not lobby: return
	lobby.append_message(sender_id, PRIVATE_CHAT_PREFIX + message)

func _on_network_system_chat(message: String) -> void:
	if not lobby: return
	lobby.append_message(1, SYSTEM_CHAT_PREFIX + message)
