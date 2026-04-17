import http.client
import json

conn = http.client.HTTPConnection("192.168.1.127", 5000)

# Test alsa-hw-capture
conn.request("GET", "/api/alsa-hw-capture")
r = conn.getresponse()
print(f"alsa-hw-capture: {r.status} {r.read().decode()}")

# Test alsa-hw-playback
conn.request("GET", "/api/alsa-hw-playback")
r = conn.getresponse()
print(f"alsa-hw-playback: {r.status} {r.read().decode()}")

# Test POST config (simulate what the browser does)
config = {
    "config": {
        "devices": {
            "samplerate": 48000,
            "chunksize": 1024,
            "capture": {"type": "Alsa", "channels": 2, "device": "hw:1,0"},
            "playback": {"type": "Alsa", "channels": 2, "device": "hw:1,0"}
        },
        "filters": {},
        "mixers": {"Mixer": {"channels": {"in": 2, "out": 2}, "mapping": [{"dest": 0, "sources": [{"channel": 0, "gain": 0, "mute": False, "inverted": False}]}, {"dest": 1, "sources": [{"channel": 1, "gain": 0, "mute": False, "inverted": False}]}]}},
        "pipeline": [{"type": "Mixer", "name": "Mixer"}],
        "processors": {}
    }
}
payload = json.dumps(config)
conn.request("POST", "/api/config", body=payload, headers={"Content-Type": "application/json"})
r = conn.getresponse()
print(f"POST config: {r.status} {r.read().decode()}")