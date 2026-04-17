import websocket, json
ws = websocket.create_connection("ws://127.0.0.1:1234", timeout=5)
ws.send(json.dumps({"GetState": None}))
print("Response:", ws.recv())
ws.close()
print("WebSocket OK!")