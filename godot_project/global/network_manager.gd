extends Node

signal connected_to_server()
signal disconnected()
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal host_disconnected()
signal server_closing()
signal host_grant()
signal global_chat(sender_id: int, message: String)
signal private_chat(sender_id: int, message: String)
signal system_chat(message: String)
signal start_game()
signal end_game()
signal register_move(sender_id: int, move: Variant) ## idk the move's type for now
signal offer_draw(sender_id: int)
signal resign(sender_id: int)
signal assign_team(target_id: int, team: int)
signal set_username(target_id: int, username: String)
signal set_icon(target_id: int, icon_code: int)
signal set_color(target_id: int, color: Vector3)

const PACKET_HEADER_SIZE: int = 5
## any packet's header should be 5 bytes(1 byte PacketType + 4 bytes sender/target peer or unused)
enum PacketType {		  ## ---------------bytes to server----------------- : -------------------bytes to client---------------------------
	## connections
	JOIN_REQUEST = 0,	  ## 1 byte	+ 4 bytes unused						 : -
	JOIN_ACCEPT = 1,	  ## -												 : 1 byte + 4 bytes assigned peer + other peer profiles payload
	PEER_JOINED = 2,	  ## -												 : 1 byte + 4 bytes joined peer profile
	PEER_LEFT = 3,		  ## -												 : 1 byte + 4 bytes left peer
	HOST_LEFT = 4,		  ## -												 : 1 byte + 4 bytes unused(host peer is always 1)
	SERVER_CLOSING = 5,	  ## -												 : 1 byte + 4 bytes unused
	## host
	HOST_GRANT = 6,		  ## 1 byte + 4 bytes target peer					 : 1 byte + 4 bytes unused
	## messaging
	GLOBAL_CHAT = 7,	  ## 1 byte + 4 bytes unused	  + message payload	 : 1 byte + 4 bytes sender peer	  + message payload
	PRIVATE_CHAT = 8,	  ## 1 byte + 4 bytes target peer + message payload  : 1 byte + 4 bytes sender peer	  + message payload
	SYSTEM_CHAT = 9,	  ## 1 byte + 4 bytes unused	  + message payload	 : 1 byte + 4 bytes unused		  + message payload
	## game flow
	START_GAME = 10,	  ## 1 byte + 4 bytes unused						 : 1 byte + 4 bytes unused
	END_GAME = 11,		  ## 1 byte + 4 bytes unused						 : 1 byte + 4 bytes unused
	REGISTER_MOVE = 12,	  ## 1 byte + 4 bytes unused 	  + move payload	 : 1 byte + 4 bytes sender peer	  + move payload
	OFFER_DRAW = 13,	  ## 1 byte + 4 bytes unused						 : 1 byte + 4 bytes sender peer
	RESIGN = 14,		  ## 1 byte + 4 bytes unused						 : 1 byte + 4 bytes sender peer
	## peer lobby
	ASSIGN_TEAM = 15,	  ## 1 byte + 4 bytes target peer + team payload	 : 1 byte + 4 bytes target peer	   + team payload
	## peer profile
	SET_USERNAME = 16,	  ## 1 byte + 4 bytes target peer + username payload : 1 byte + 4 bytes target peer	   + username payload
	SET_ICON = 17,		  ## 1 byte + 4 bytes target peer + 1 byte enum		 : 1 byte + 4 bytes target peer	   + 1 byte enum
	SET_COLOR = 18,		  ## 1 byte + 4 bytes target peer + color payload	 : 1 byte + 4 bytes target peer	   + color payload
}
## message payload: string encoded in ASCII or UTF-8(we'll see in the future)
## move payload: more complicated, you could move multiple pieces + select promotion piece + move/capture flags + etc.
## username payload: string encoded in ASCII or UTF-8(we'll see in the future)
## team payload: unsigned 32-bit integer for team ID

const OFFLINE_ID: int = 0
const RELAY_ID: int = 0
const HOST_ID: int = 1
const BROADCAST_ID: int = 0

const MAX_PACKETS_PER_FRAME: int = 50
const MAX_PACKETS_PER_INTERVAL: int = 60
const RATE_LIMIT_RESET_INTERVAL: float = 1.0 ## in seconds
var peer_packet_counts: Dictionary = {} ## sender_id -> packet count each time interval
var rate_limit_timer: float = 0.0 ## in seconds

var socket := WebSocketPeer.new()
var is_online := false
var my_id: int = OFFLINE_ID
var peers: PackedInt32Array = []
var relay_connected := false

func _enter_tree() -> void:
	set_process(false)

func start_client(url: String) -> void:
	is_online = true
	my_id = OFFLINE_ID
	peers.clear()
	connect_to_relay(url)

func leave_server() -> void:
	#if relay_connected: send_data(PacketType.PEER_LEFT, BROADCAST_ID) # ???
	socket.close()
	peers.clear()
	relay_connected = false
	my_id = OFFLINE_ID
	set_process(false)

func connect_to_relay(url: String) -> void:
	relay_connected = false
	var err := socket.connect_to_url(url)
	if err == OK: set_process(true)
	else: printerr("Failed to initialize WebSocket connection")

func process_rate_limit(delta: float) -> void:
	rate_limit_timer += delta
	if rate_limit_timer >= RATE_LIMIT_RESET_INTERVAL:
		rate_limit_timer = 0.0
		peer_packet_counts.clear()

func _process(delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	process_rate_limit(delta)
	if state == WebSocketPeer.STATE_OPEN:
		if not relay_connected:
			relay_connected = true
			if my_id == HOST_ID: connected_to_server.emit() # ???
			else: send_data(PacketType.JOIN_REQUEST)
		var processed_packet_count: int = 0
		while socket.get_available_packet_count() > 0 and processed_packet_count < MAX_PACKETS_PER_FRAME:
			handle_raw_packet(socket.get_packet())
			processed_packet_count += 1
	elif state == WebSocketPeer.STATE_CLOSED:
		disconnected.emit()
		leave_server()

func send_data(type: int, target_id: int = HOST_ID, payload: PackedByteArray = PackedByteArray()) -> void:
	## 5-byte header: 1 byte PacketType + 4 bytes 32-bit target_id if sending, sender_id if receiving, or unused
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(type)
	buffer.put_32(target_id)
	var packet := buffer.data_array
	packet.append_array(payload)
	socket.send(packet, WebSocketPeer.WRITE_MODE_BINARY)

func handle_raw_packet(packet: PackedByteArray) -> void:
	if packet.size() < PACKET_HEADER_SIZE: return
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	var type := buffer.get_u8()
	var sender_id := buffer.get_32()
	var current_packet_count: int = peer_packet_counts.get(sender_id, 0)
	if current_packet_count > MAX_PACKETS_PER_INTERVAL: return
	peer_packet_counts[sender_id] = current_packet_count + 1
	var payload := packet.slice(PACKET_HEADER_SIZE)
	match type:
		PacketType.JOIN_REQUEST: return
		PacketType.JOIN_ACCEPT:
			if my_id != OFFLINE_ID: return
			my_id = sender_id
			peers.append(HOST_ID)
			var player_buffer := StreamPeerBuffer.new()
			player_buffer.data_array = payload
			var peer_count := player_buffer.get_32()
			for i in range(peer_count):
				var pid: int = player_buffer.get_32()
				if pid == my_id: continue
				peers.append(pid)
			connected_to_server.emit()
		PacketType.PEER_JOINED:
			var player_buffer := StreamPeerBuffer.new()
			player_buffer.data_array = payload
			var new_peer = player_buffer.get_32()
			if new_peer != my_id and not new_peer in peers:
				peers.append(new_peer)
				peer_connected.emit(new_peer)
		PacketType.PEER_LEFT:
			var pl_buffer := StreamPeerBuffer.new()
			pl_buffer.data_array = payload
			var left_peer = pl_buffer.get_32()
			if left_peer in peers:
				peers.erase(left_peer)
				peer_disconnected.emit(left_peer)
		PacketType.HOST_LEFT:
			if 1 in peers:
				peers.erase(1)
				host_disconnected.emit()
		PacketType.SERVER_CLOSING:
			server_closing.emit()
			#relay_connected = false # ???
			leave_server()
		PacketType.HOST_GRANT:
			my_id = 1
			peers.erase(1)
			peers.append(sender_id)
			host_grant.emit()
		PacketType.GLOBAL_CHAT:
			var message: String = bytes_to_var(payload)
			global_chat.emit(sender_id, message)
		PacketType.PRIVATE_CHAT:
			var message: String = bytes_to_var(payload)
			private_chat.emit(sender_id, message)
		PacketType.SYSTEM_CHAT:
			var message: String = bytes_to_var(payload)
			system_chat.emit(message)
		PacketType.START_GAME: start_game.emit()
		PacketType.END_GAME: end_game.emit()
		PacketType.REGISTER_MOVE: return
		PacketType.OFFER_DRAW: offer_draw.emit(sender_id)
		PacketType.RESIGN: resign.emit(sender_id)
		PacketType.ASSIGN_TEAM:
			var team: int = bytes_to_var(payload)
			assign_team.emit(sender_id, team)
		PacketType.SET_USERNAME:
			var username: String = bytes_to_var(payload)
			set_username.emit(sender_id, username)
		PacketType.SET_ICON:
			var icon_code: int = bytes_to_var(payload)
			set_icon.emit(sender_id, icon_code)
		PacketType.SET_COLOR:
			var color: Vector3 = bytes_to_var(payload)
			set_color.emit(sender_id, color)
