extends Node

var lobby: Control = null

func _enter_tree() -> void:
	create_lobby()

const LOBBY_SCENE_PATH: String = "res://ui/offline_menu/offline_menu.tscn"
func create_lobby() -> void:
	lobby = load(LOBBY_SCENE_PATH).instantiate()
	add_child(lobby)
