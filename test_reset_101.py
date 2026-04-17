import http.client, json

conn = http.client.HTTPConnection("192.168.1.101", 5000)

# First check ALSA devices
conn.request("GET", "/api/alsa-hw-capture")
r = conn.getresponse()
print(f"alsa-hw-capture: {r.status} {r.read().decode()[:200]}")

conn = http.client.HTTPConnection("192.168.1.101", 5000)
conn.request("GET", "/api/alsa-hw-playback")
r = conn.getresponse()
print(f"alsa-hw-playback: {r.status} {r.read().decode()[:200]}")

# Test POST full config like reset does
config = {
    "config": {
        "devices": {
            "samplerate": 48000,
            "capture_samplerate": 48000,
            "chunksize": 1024,
            "capture": {"type": "Alsa", "channels": 2, "device": "hw:1,0"},
            "playback": {"type": "Alsa", "channels": 2, "device": "hw:1,0"}
        },
        "filters": {},
        "mixers": {"Mixer 1": {"channels": {"in": 2, "out": 2}, "description": None, "labels": None, "mapping": []}},
        "pipeline": [{"type": "Mixer", "name": "Mixer 1"}],
        "processors": {}
    }
}

conn = http.client.HTTPConnection("192.168.1.101", 5000)
payload = json.dumps(config)
conn.request("POST", "/api/config", body=payload, headers={"Content-Type": "application/json"})
r = conn.getresponse()
print(f"POST config: {r.status} {r.read().decode()[:300]}")