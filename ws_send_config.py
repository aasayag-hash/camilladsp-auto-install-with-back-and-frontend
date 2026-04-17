import websocket, json

ws = websocket.create_connection("ws://127.0.0.1:1234", timeout=10)

# Read config from YAML
with open("/root/camilladsp/config/camilladsp.yml") as f:
    import yaml
    cfg = yaml.safe_load(f)

# Send config
ws.send(json.dumps({"SetConfigJson": json.dumps(cfg)}))
resp = ws.recv()
print("SetConfig response:", resp)

# Check state
ws.send(json.dumps({"GetState": None}))
print("GetState:", ws.recv())

ws.close()