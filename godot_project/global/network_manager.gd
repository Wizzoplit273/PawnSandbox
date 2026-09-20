extends Node

signal connected_to_server()
signal disconnected()
signal peer_connected(id: int)
signal peer_disconnected(id: int)
signal packet_received(sender_id: int, data: PackedByteArray)

enum PacketType {
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

const OFFLINE_ID: int = 0
const SERVER_ID: int = 1
const BROADCAST_ID: int = 0

const MAX_PACKETS_PER_FRAME: int = 50
const MAX_PACKETS_PER_INTERVAL: int = 60
const RATE_LIMIT_RESET_INTERVAL: float = 1.0 ## in seconds
var peer_packet_counts: Dictionary = {} ## sender_id -> packet count each time interval
var rate_limit_timer: float = 0.0 ## in seconds

var socket := WebSocketPeer.new()
var connected_status := Status.OFFLINE
var my_id: int = OFFLINE_ID
var peers: PackedInt32Array = []
var relay_connected := false

func _enter_tree() -> void:
	set_process(false)

func start_server(url: String) -> void:
	connected_status = Status.SERVER
	my_id = SERVER_ID
	peers.clear()
	connect_to_relay(url)

func start_client(url: String) -> void:
	connected_status = Status.CLIENT
	my_id = OFFLINE_ID
	peers.clear()
	connect_to_relay(url)

func leave_server() -> void:
	if relay_connected: send_internal(PacketType.PEER_LEFT, BROADCAST_ID)
	socket.close()
	peers.clear()
	relay_connected = false
	my_id = OFFLINE_ID
	set_process(false)

func send_data(target_id: int, data: PackedByteArray) -> void:
	send_internal(PacketType.DATA, target_id, data)

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
			if connected_status == Status.SERVER: connected_to_server.emit()
			else:
				# Ask the host to acknowledge our connection
				send_internal(PacketType.JOIN_REQUEST, SERVER_ID)
		var processed_packet_count: int = 0
		while socket.get_available_packet_count() > 0 and processed_packet_count < MAX_PACKETS_PER_FRAME:
			handle_raw_packet(socket.get_packet())
			processed_packet_count += 1
	elif state == WebSocketPeer.STATE_CLOSED:
		disconnected.emit()
		leave_server()

func send_internal(type: int, target_id: int, payload: PackedByteArray = PackedByteArray()) -> void:
	## 9-Byte Header: [Type: u8 (1 byte)] + [Sender: i32 (4 bytes)] + [Target: i32 (4 bytes)]
	var buffer := StreamPeerBuffer.new()
	buffer.put_u8(type)
	buffer.put_32(my_id)
	buffer.put_32(target_id)
	var packet := buffer.data_array
	packet.append_array(payload)
	socket.send(packet, WebSocketPeer.WRITE_MODE_BINARY)

func handle_raw_packet(packet: PackedByteArray) -> void:
	if packet.size() < 9: return
	var buffer := StreamPeerBuffer.new()
	buffer.data_array = packet
	var type := buffer.get_u8()
	var sender_id := buffer.get_32()
	var target_id := buffer.get_32()
	if target_id != BROADCAST_ID and target_id != my_id: return
	var current_packet_count: int = peer_packet_counts.get(sender_id, 0)
	if current_packet_count > MAX_PACKETS_PER_INTERVAL: return
	peer_packet_counts[sender_id] = current_packet_count + 1
	var payload := packet.slice(9)
	match type:
		PacketType.JOIN_REQUEST:
			if connected_status != Status.SERVER: return
			#if sender_id in peers: return
			var assign_id: int = generate_unique_id()
			peers.append(assign_id)
			var accept_buffer := StreamPeerBuffer.new()
			accept_buffer.put_32(peers.size() - 1)
			for p in peers:
				if p == assign_id: continue
				accept_buffer.put_32(p)
			send_internal(PacketType.JOIN_ACCEPT, assign_id, accept_buffer.data_array)
			var join_message := StreamPeerBuffer.new()
			join_message.put_32(assign_id)
			send_internal(PacketType.PEER_JOINED, BROADCAST_ID, join_message.data_array)
			peer_connected.emit(assign_id)
		PacketType.JOIN_ACCEPT:
			if connected_status != Status.CLIENT: return
			if my_id != OFFLINE_ID: return
			peers.append(SERVER_ID)
			var player_buffer := StreamPeerBuffer.new()
			player_buffer.data_array = payload
			var peer_count := player_buffer.get_32()
			for i in range(peer_count): peers.append(player_buffer.get_32())
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
		PacketType.DATA: packet_received.emit(sender_id, payload)

func generate_unique_id() -> int:
	if connected_status != Status.SERVER: return 0
	var new_id := randi_range(SERVER_ID + 1, INT32_MAX)
	while new_id in peers: new_id = randi_range(SERVER_ID + 1, INT32_MAX)
	return new_id
