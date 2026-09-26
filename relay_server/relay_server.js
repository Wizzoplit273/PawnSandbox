const http = require('http');
const WebSocket = require('ws');

// PORT assigned by hosting environment or default to 8080
const PORT = process.env.PORT || 8080;

// HTTP server for health checks
const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/plain' });
    res.end('WebSocket relay server is active.');
});

const ws_server = new WebSocket.Server({ server });

const PacketType = Object.freeze({
    JOIN_REQUEST: 0,
    JOIN_ACCEPT: 1,
    PEER_JOINED: 2,
    PEER_LEFT: 3,
    HOST_LEFT: 4,
    SERVER_CLOSING: 5,
    HOST_GRANT: 6,
    GLOBAL_CHAT: 7,
    PRIVATE_CHAT: 8,
    SYSTEM_CHAT: 9,
    START_GAME: 10,
    END_GAME: 11,
    REGISTER_MOVE: 12,
    OFFER_DRAW: 13,
    RESIGN: 14,
    SET_TEAM: 15,
    SET_USERNAME: 16,
    SET_ICON: 17,
    SET_COLOR: 18
});

const clients = new Map(); // Peer ID (int) -> WebSocket Object
let nextPeerId = 1;

const PACKET_HEADER_SIZE = 5

function broadcast(exceptId, data) {
    clients.forEach((clientWs, id) => {
        if (id !== exceptId && clientWs.readyState === WebSocket.OPEN) {
            clientWs.send(data);
        }
    });
}

function sendTo(targetId, data) {
    const targetWs = clients.get(targetId);
    if (targetWs && targetWs.readyState === WebSocket.OPEN) {
        targetWs.send(data);
    }
}

ws_server.on('connection', (ws) => {
    ws.hasJoined = false;

    ws.on('message', (data, isBinary) => {
        if (!isBinary || data.length < PACKET_HEADER_SIZE) return;
        const msgType = data.readUInt8(0);
        if (msgType === PacketType.JOIN_REQUEST) {
            if (ws.hasJoined) return;
            const peerId = nextPeerId++;
            ws.peerId = peerId;
            ws.hasJoined = true;
            clients.set(peerId, ws);
            console.log(`Client joined and assigned peer ID: ${peerId}`);

            const peerCount = clients.size - 1;
            const acceptBuf = Buffer.alloc(PACKET_HEADER_SIZE + 4 + (peerCount * 4));
            acceptBuf.writeUInt8(PacketType.JOIN_ACCEPT, 0);
            acceptBuf.writeInt32BE(peerId, 1);       // Assigned ID
            acceptBuf.writeInt32BE(peerCount, 5);    // Payload: peer_count

            let offset = PACKET_HEADER_SIZE + 4;
            clients.forEach((cWs, id) => {
                if (id !== peerId) {
                    acceptBuf.writeInt32BE(id, offset);
                    offset += 4;
                }
            });
            ws.send(acceptBuf);

            const joinedBuf = Buffer.alloc(PACKET_HEADER_SIZE);
            joinedBuf.writeUInt8(PacketType.PEER_JOINED, 0);
            joinedBuf.writeInt32BE(peerId, 1);
            broadcast(peerId, joinedBuf);
            return;
        }
        if (!ws.hasJoined) return;

        const targetId = data.readInt32BE(1);
        switch (msgType) {
            case PacketType.SET_TEAM:
            case PacketType.SET_USERNAME:
            case PacketType.SET_ICON:
            case PacketType.SET_COLOR:
                if (ws.peerId !== 1 && targetId !== ws.peerId) return;
                broadcast(ws.peerId, data);
                break;

            case PacketType.PRIVATE_CHAT:
                data.writeInt32BE(ws.peerId, 1);
                sendTo(targetId, data);
                break;

            case PacketType.GLOBAL_CHAT:
            case PacketType.SYSTEM_CHAT:
                data.writeInt32BE(ws.peerId, 1);
                broadcast(ws.peerId, data);
                break;

            case PacketType.HOST_GRANT:
            case PacketType.START_GAME:
            case PacketType.END_GAME:
                if (ws.peerId !== 1) return;
                broadcast(1, data);
            	break;
            case PacketType.REGISTER_MOVE:
            case PacketType.OFFER_DRAW:
            case PacketType.RESIGN:
                broadcast(ws.peerId, data);
            	break;
            default: return;
        }
    });

    ws.on('close', () => {
        if (!ws.hasJoined) return;

        clients.delete(ws.peerId);
        console.log(`Client ${ws.peerId} disconnected`);

        const leftBuf = Buffer.alloc(PACKET_HEADER_SIZE);
        if (ws.peerId === 1) leftBuf.writeUInt8(PacketType.PEER_LEFT, 0);
        else {
            leftBuf.writeUInt8(PacketType.HOST_LEFT, 0);
            leftBuf.writeInt32BE(ws.peerId, 1);
        }
        broadcast(ws.peerId, leftBuf);
    });
});

server.listen(PORT, () => {
    console.log(`Relay server running on port ${PORT}`);
});
