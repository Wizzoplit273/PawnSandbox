extends Node

var profiles: Dictionary = {} ## includes own profile: offline profile has peer ID set to 0
## peer ID -> { "username": String, "icon_code": IconCode, "color": Color }

enum IconCode {
	PAWN = 0,
	KNIGHT = 1,
	BISHOP = 2,
	ROOK = 3,
	QUEEN = 4,
	KING = 5
}

#func to_profile(username: String, icon_code: IconCode, color: Vector3) -> Dictionary:
	#var result: Dictionary = {
		#"username": username,
		#"icon_code": icon_code,
		#"color": Color(color.x, color.y, color.z)
	#}
	#return result
#
#func to_byte_array(profile: Dictionary) -> PackedByteArray:
	#return var_to_bytes(profile)

func update_profile(peer_id: int, profile: Dictionary) -> void:
	if peer_id < 0: return
	if not peer_id in NetworkManager.peers: NetworkManager.peers.append(peer_id)
	profiles[peer_id] = profile

func delete_profile(peer_id: int) -> void:
	if peer_id < 0: return
	NetworkManager.peers.erase(peer_id)
	profiles.erase(peer_id)

func copy_profile(old_peer_id: int, new_peer_id: int) -> void:
	if old_peer_id < 0: return
	if new_peer_id < 0: return
	update_profile(new_peer_id, profiles[old_peer_id])
	delete_profile(old_peer_id)
