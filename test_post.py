import http.client
import json
conn = http.client.HTTPConnection("127.0.0.1", 5000)
payload = json.dumps({"config": {"devices": {"samplerate": 48000}}})
conn.request("POST", "/api/config", body=payload, headers={"Content-Type": "application/json"})
r = conn.getresponse()
print(f"Status: {r.status}")
print(f"Response: {r.read()[:300]}")