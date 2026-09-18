extends Node

signal connected_to_server()
signal disconnected()
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal packet_received(sender_id: int, data: PackedByteArray)

enum MessageType {
	JOIN_REQUEST = 0,
	JOIN_ACCEPT = 1,
	PEER_JOINED = 2,
	PEER_LEFT = 3,
	DATA = 4
}

enum Status {
	OFFLINE = 0,
	CLIENT = 1,
	SERVER = 2
}

const SERVER_ID: int = 1

var socket := WebSocketPeer.new()
var connected_status := Status.OFFLINE
var my_id: int = 0
var peers: Array[int] = []
var relay_connected := false

func start_server(url: String) -> void:
	connected_status = Status.SERVER
	my_id = SERVER_ID
	peers.clear()
	connect_to_relay(url)

func start_client(url: String) -> void:
	connected_status = Status.CLIENT
	my_id = randi() % 900000 + 10000 # Generate a random unique ID for this client
	peers.clear()
	connect_to_relay(url)

func leave_server() -> void:
	if relay_connected: send_internal(MessageType.PEER_LEFT, 0)
	socket.close()
	peers.clear()
	relay_connected = false
	my_id = 0
	set_process(false)

func send_data(target_id: int, data: PackedByteArray) -> void:
	send_internal(MessageType.DATA, target_id, data)

func connect_to_relay(url: String) -> void:
	relay_connected = false
	var err := socket.connect_to_url(url)
	if err == OK: set_process(true)
	else: printerr("Failed to initialize WebSocket connection")

func _process(_delta: float) -> void:
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not relay_connected:
			relay_connected = true
			if connected_status == Status.SERVER: connected_to_server.emit()
			else:
				# Ask the host to acknowledge our connection
				send_internal(MessageType.JOIN_REQUEST, SERVER_ID)
		while socket.get_available_packet_count() > 0:
			handle_raw_packet(socket.get_packet())
	elif state == WebSocketPeer.STATE_CLOSED:
		disconnected.emit()
		leave_server()

func send_internal(type: int, target_id: int, payload: PackedByteArray = PackedByteArray()) -> void:
	# 9-Byte Header: [Type: u8 (1 byte)] + [Sender: i32 (4 bytes)] + [Target: i32 (4 bytes)]
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(type)
	buffer.put_32(my_id)
	buffer.put_32(target_id)
	var packet := buffer.data_array
	packet.append_array(payload)
	socket.send_packet(packet)

func handle_raw_packet(packet: PackedByteArray) -> void:
	if packet.size() < 9: return
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	var type := buffer.get_u8()
	var sender_id := buffer.get_32()
	var target_id := buffer.get_32()
	# Drop packets that are not broadcasts (0) and not explicitly targeting our ID
	if target_id != 0 and target_id != my_id: return
	# Extract everything after the 9-byte header
	var payload := packet.slice(9)
	match type:
		MessageType.JOIN_REQUEST:
			if connected_status != Status.SERVER: return
			if sender_id in peers: return
			peers.append(sender_id)
			var accept_buffer := StreamPeerBuffer.new()
			accept_buffer.put_32(peers.size() - 1)
			for p in peers:
				if p == sender_id: continue
				accept_buffer.put_32(p)
			send_internal(MessageType.JOIN_ACCEPT, sender_id, accept_buffer.data_array)
			var join_message := StreamPeerBuffer.new()
			join_message.put_32(sender_id)
			send_internal(MessageType.PEER_JOINED, 0, join_message.data_array)
			peer_connected.emit(sender_id)
		MessageType.JOIN_ACCEPT:
			if connected_status != Status.SERVER:
				peers.append(SERVER_ID)
				var player_buffer := StreamPeerBuffer.new()
				player_buffer.data_array = payload
				var peer_count := player_buffer.get_32()
				for i in range(peer_count): peers.append(player_buffer.get_32())
				connected_to_server.emit()
		MessageType.PEER_JOINED:
			var player_buffer := StreamPeerBuffer.new()
			player_buffer.data_array = payload
			var new_peer = player_buffer.get_32()
			if new_peer != my_id and not new_peer in peers:
				peers.append(new_peer)
				peer_connected.emit(new_peer)
		MessageType.PEER_LEFT:
			var pl_buffer := StreamPeerBuffer.new()
			pl_buffer.data_array = payload
			var left_peer = pl_buffer.get_32()
			if left_peer in peers:
				peers.erase(left_peer)
				peer_disconnected.emit(left_peer)
		MessageType.DATA: packet_received.emit(sender_id, payload)
