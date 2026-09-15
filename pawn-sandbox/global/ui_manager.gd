extends Node

var offline_menu: Control = null
var lobby: Control = null

func _enter_tree() -> void:
	create_offline_menu()
	create_lobby()

const OFFLINE_MENU_SCENE_PATH: String = "res://ui/offline_menu/offline_menu.tscn"
func create_offline_menu() -> void:
	offline_menu = load(OFFLINE_MENU_SCENE_PATH).instantiate()
	add_child(offline_menu)

const LOBBY_SCENE_PATH: String = "res://ui/lobby/lobby.tscn"
func create_lobby() -> void:
	lobby = load(LOBBY_SCENE_PATH).instantiate()
	add_child(lobby)
