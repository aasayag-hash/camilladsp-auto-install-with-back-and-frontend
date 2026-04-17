import websocket
ws = websocket.create_connection('ws://127.0.0.1:1234')
ws.send('{"command":"GetState"}')
print("State:", ws.recv()[:200])
ws.close()