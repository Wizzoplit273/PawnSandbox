const WebSocket = require('ws');
const ws_server = new WebSocket.Server({ port: 8080 });

const clients = new Map(); // Peer ID (int) -> WebSocket Object
let nextPeerId = 1;

ws_server.on('connection', (ws) => {
    const peerId = nextPeerId++;
    ws.peerId = peerId;
    clients.set(peerId, ws);
    console.log(`Client connected and assigned peer ID: ${peerId}`);
    ws.on('message', (data, isBinary) => {
        // Ensure data is binary and long enough for the 9-byte header
        if (!isBinary || data.length < 9) return;
        // Parse Header: [Type (1 byte)] [Sender ID (4 bytes)] [Target ID (4 bytes)]
        const msgType = data.readUInt8(0);
        const senderId = data.readInt32BE(1);
        const targetId = data.readInt32BE(5);
        if (senderId === 0) {
            if (ws.hasJoined || targetId !== 1) {
                console.warn(`Unauthorized temp packet from ${ws.peerId}. Disconnecting`);
                ws.close(1008, "Invalid zero-sender state");
                return;
            }
            ws.hasJoined = true;
        } else if (senderId !== ws.peerId) {
            // Spoof check
            console.warn(`Spoofing detected! Socket ${ws.peerId} claimed to be ${senderId}. Disconnecting`);
            ws.close(1008, "Identity spoofing detected");
            return;
        }
        // Client broadcast check
        if (senderId !== 1 && targetId === 0) { return; }
        if (targetId === 0) {
            clients.forEach((clientWs, id) => {
                if (id !== ws.peerId && clientWs.readyState === WebSocket.OPEN) {
                    clientWs.send(data);
                }
            });
        } else {
            const targetWs = clients.get(targetId);
            if (targetWs && targetWs.readyState === WebSocket.OPEN) {
                targetWs.send(data);
            }
        }
    });
    ws.on('close', () => {
        clients.delete(ws.peerId);
        console.log(`Client ${ws.peerId} disconnected`);
    });
});
