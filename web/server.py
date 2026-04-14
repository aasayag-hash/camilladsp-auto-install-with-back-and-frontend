#!/usr/bin/env python3
"""CamillaDSP Web GUI — Servidor Flask"""
import json, threading, os
from flask import Flask, jsonify, request, send_file, Response
import websocket, urllib.request

# Configurable — el instalador reemplaza este path
INSTALL_BASE = "/root/camilladsp"
CDSP_WS      = "ws://127.0.0.1:1234"
CFG_FILE     = INSTALL_BASE + "/config/camilladsp.yml"
WEB_DIR      = os.path.dirname(os.path.abspath(__file__))
WEB_PORT     = 5000

app = Flask(__name__)
_lock = threading.Lock()
_ws   = None

try:
    import yaml
    HAS_YAML = True
except ImportError:
    HAS_YAML = False

# ── WebSocket helper ──────────────────────────────────────────────────────────
def cdsp(cmd, payload=None):
    global _ws
    with _lock:
        for attempt in range(2):
            try:
                if _ws is None:
                    _ws = websocket.create_connection(CDSP_WS, timeout=5)
                _ws.send(json.dumps({cmd: payload}))
                resp = json.loads(_ws.recv())
                r = resp.get(cmd, {})
                if isinstance(r, dict):
                    if r.get("result") == "Ok":
                        return r.get("value")
                    elif r.get("result") == "Error":
                        raise Exception(r.get("value", "CamillaDSP error"))
                return r
            except Exception as e:
                try:    _ws.close()
                except: pass
                _ws = None
                if attempt == 1:
                    raise e

# ── Config YAML ───────────────────────────────────────────────────────────────
def load_yaml_config():
    if not HAS_YAML: return {}
    try:
        with open(CFG_FILE, "r") as f:
            return yaml.safe_load(f) or {}
    except:
        return {}

def save_yaml_config(cfg):
    if not HAS_YAML: return
    try:
        with open(CFG_FILE, "w") as f:
            yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
    except Exception as e:
        print(f"Error saving config: {e}")

# ── Rutas ─────────────────────────────────────────────────────────────────────
@app.route("/")
def root():
    return send_file(os.path.join(WEB_DIR, "index.html"))

@app.route("/api/config", methods=["GET"])
def get_config():
    try:
        v = cdsp("GetConfigJson")
        if v and v != "null":
            cfg = json.loads(v) if isinstance(v, str) else v
        else:
            cfg = load_yaml_config()
            try: cdsp("SetConfigJson", json.dumps(cfg))
            except: pass
        return jsonify({"ok": True, "config": cfg})
    except Exception as e:
        try:
            return jsonify({"ok": True, "config": load_yaml_config()})
        except Exception as e2:
            return jsonify({"ok": False, "error": str(e2)}), 500

@app.route("/api/config", methods=["POST"])
def set_config():
    try:
        cfg = request.json.get("config")
        cdsp("SetConfigJson", json.dumps(cfg))
        save_yaml_config(cfg)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/patch", methods=["POST"])
def patch_config():
    try:
        cdsp("PatchConfig", request.json.get("patch"))
        try:
            v = cdsp("GetConfigJson")
            if v and v != "null":
                save_yaml_config(json.loads(v) if isinstance(v, str) else v)
        except: pass
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/levels", methods=["GET"])
def get_levels():
    try:
        cap  = cdsp("GetCaptureSignalRms")  or []
        play = cdsp("GetPlaybackSignalRms") or []
        vol  = cdsp("GetVolume") or 0.0
        return jsonify({"ok": True, "capture": cap, "playback": play, "volume": vol})
    except:
        return jsonify({"ok": True, "capture": [], "playback": [], "volume": 0.0})

@app.route("/api/volume", methods=["POST"])
def set_volume():
    try:
        cdsp("SetVolume", float(request.json.get("volume", 0.0)))
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/export", methods=["GET"])
def export_config():
    try:
        v = cdsp("GetConfigJson")
        cfg = json.loads(v) if isinstance(v, str) else v
        if HAS_YAML:
            yml = yaml.dump(cfg, default_flow_style=False, sort_keys=False, allow_unicode=True)
            return Response(yml, mimetype="application/x-yaml",
                            headers={"Content-Disposition": "attachment; filename=camilladsp.yml"})
        return jsonify(cfg)
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/import-support")
def import_support():
    return jsonify({"ok": True})

CDSP_GUI = "http://127.0.0.1:5005"

def _cdsp_gui_get(path):
    with urllib.request.urlopen(f"{CDSP_GUI}{path}", timeout=5) as r:
        return json.loads(r.read())

@app.route("/api/capturedevices")
def get_capture_devices():
    try:
        data = _cdsp_gui_get("/api/capturedevices/Alsa")
        return jsonify({"ok": True, "devices": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "devices": []})

@app.route("/api/playbackdevices")
def get_playback_devices():
    try:
        data = _cdsp_gui_get("/api/playbackdevices/Alsa")
        return jsonify({"ok": True, "devices": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "devices": []})

@app.route("/api/restart", methods=["POST"])
def restart_engine():
    try:
        req = urllib.request.Request(f"{CDSP_GUI}/api/stopcamilladsp",
                                     method="GET")
        urllib.request.urlopen(req, timeout=3)
    except Exception:
        pass
    try:
        req = urllib.request.Request(f"{CDSP_GUI}/api/startcamilladsp",
                                     method="GET")
        urllib.request.urlopen(req, timeout=3)
    except Exception:
        pass
    return jsonify({"ok": True})

if __name__ == "__main__":
    print(f"CamillaDSP Web GUI → http://0.0.0.0:{WEB_PORT}")
    app.run(host="0.0.0.0", port=WEB_PORT, threaded=True)
