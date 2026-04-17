import http.client, json
conn = http.client.HTTPConnection("192.168.1.101", 5000)
payload = json.dumps({"config": {"devices": {"samplerate": 48000}}})
conn.request("POST", "/api/config", body=payload, headers={"Content-Type": "application/json"})
r = conn.getresponse()
print(f"Status: {r.status}")
print(f"Response: {r.read().decode()[:300]}")