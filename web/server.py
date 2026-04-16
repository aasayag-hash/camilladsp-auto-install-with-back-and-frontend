#!/usr/bin/env python3
"""CamillaDSP Web GUI — Servidor Flask"""
import json, threading, os, subprocess
from flask import Flask, jsonify, request, send_file, Response
import websocket, urllib.request

# Configurable — el instalador reemplaza este path
INSTALL_BASE  = "/root/camilladsp"
CDSP_WS       = "ws://127.0.0.1:1234"
CFG_FILE      = INSTALL_BASE + "/config/camilladsp.yml"
PRESETS_DIR   = INSTALL_BASE + "/config/presets"
WEB_DIR       = os.path.dirname(os.path.abspath(__file__))
WEB_PORT      = 5000

os.makedirs(PRESETS_DIR, exist_ok=True)

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

@app.route("/api/status", methods=["GET"])
def get_status():
    try:
        state  = cdsp("GetState")  or "Unknown"
        buf    = cdsp("GetBufferLevel")
        load   = cdsp("GetProcessingLoad")
        return jsonify({"ok": True, "state": state, "buffer": buf, "load": load})
    except Exception as e:
        return jsonify({"ok": False, "state": "Error", "buffer": None, "load": None})

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

import re

def _get_alsa_hw(mode):
    cmd = "arecord -L" if mode == "capture" else "aplay -L"
    devs = []
    try:
        out = subprocess.check_output(cmd, shell=True, text=True)
        current_id = None
        current_desc = []
        for line in out.splitlines():
            if not line:
                continue
            if line[0] not in ' \t':
                if current_id and current_id != "null":
                    desc_str = " - ".join([d.strip(" ,") for d in current_desc if d.strip(" ,")])
                    devs.append([current_id, desc_str])
                current_id = line.strip()
                current_desc = []
            else:
                current_desc.append(line.strip())
        if current_id and current_id != "null":
            desc_str = " - ".join([d.strip(" ,") for d in current_desc if d.strip(" ,")])
            devs.append([current_id, desc_str])
    except Exception:
        pass
    return devs

@app.route("/api/capturedevices")
def get_capture_devices():
    try:
        # Fallback a CamillaGUI si _get_alsa_hw falla, pero nativo primero
        data = _get_alsa_hw("capture")
        if not data:
            data = _cdsp_gui_get("/api/capturedevices/Alsa")
        return jsonify({"ok": True, "devices": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "devices": []})

@app.route("/api/playbackdevices")
def get_playback_devices():
    try:
        data = _get_alsa_hw("playback")
        if not data:
            data = _cdsp_gui_get("/api/playbackdevices/Alsa")
        return jsonify({"ok": True, "devices": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "devices": []})

def _get_alsa_hw_only(mode):
    cmd = "arecord -L" if mode == "capture" else "aplay -L"
    devs = []
    try:
        out = subprocess.check_output(cmd, shell=True, text=True, timeout=5)
        current_id = None
        current_desc = []
        for line in out.splitlines():
            if not line:
                continue
            if line[0] not in ' \t':
                if current_id:
                    desc_str = " - ".join([d.strip(" ,") for d in current_desc if d.strip(" ,")])
                    devs.append({"id": current_id, "desc": desc_str})
                current_id = line.strip()
                current_desc = []
            else:
                current_desc.append(line.strip())
        if current_id:
            desc_str = " - ".join([d.strip(" ,") for d in current_desc if d.strip(" ,")])
            devs.append({"id": current_id, "desc": desc_str})
    except Exception:
        pass
    hw_devs = [d for d in devs if d["id"].startswith("hw:")]
    for d in hw_devs:
        try:
            parts = d["id"].split(",")
            card_num = parts[0].replace("hw:", "")
            with open(f"/proc/asound/card{card_num}/id", "r") as f:
                d["card_name"] = f.read().strip()
        except Exception:
            d["card_name"] = ""
    return hw_devs

def _probe_alsa_hw(device_id, mode):
    cmd_base = "aplay" if mode == "playback" else "arecord"
    try:
        result = subprocess.run(
            [cmd_base, "--dump-hw-params", "-D", device_id] +
            (["-d", "1", "/dev/null"] if mode == "capture" else ["/dev/zero"]),
            capture_output=True, text=True, timeout=8
        )
        output = result.stderr + "\n" + result.stdout
        info = {"device": device_id, "mode": mode, "channels": None, "rate": None, "format": None, "raw": output}
        for line in output.splitlines():
            line = line.strip()
            if line.startswith("CHANNELS:"):
                info["channels"] = int(line.split(":")[1].strip().split()[0])
            elif line.startswith("RATE:"):
                val = line.split(":")[1].strip().split()[0]
                try:
                    info["rate"] = int(val)
                except ValueError:
                    info["rate"] = val
            elif line.startswith("FORMAT:"):
                info["format"] = line.split(":")[1].strip().split()[0]
        return info
    except Exception as e:
        return {"device": device_id, "mode": mode, "error": str(e)}

@app.route("/api/alsa-hw-capture")
def alsa_hw_capture():
    try:
        devs = _get_alsa_hw_only("capture")
        return jsonify({"ok": True, "devices": devs})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "devices": []})

@app.route("/api/alsa-hw-playback")
def alsa_hw_playback():
    try:
        devs = _get_alsa_hw_only("playback")
        return jsonify({"ok": True, "devices": devs})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "devices": []})

@app.route("/api/alsa-probe")
def alsa_probe():
    device = request.args.get("device", "")
    mode = request.args.get("mode", "playback")
    if not device:
        return jsonify({"ok": False, "error": "Missing device parameter"}), 400
    info = _probe_alsa_hw(device, mode)
    if "error" in info:
        return jsonify({"ok": False, "error": info["error"]})
    return jsonify({"ok": True, "probe": info})

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

@app.route("/api/recovery", methods=["POST"])
def recover_engine():
    try:
        yaml_content = """description: default
devices:
  adjust_period: null
  capture:
    channels: 4
    device: "null"
    format: null
    labels: null
    link_mute_control: null
    link_volume_control: null
    stop_on_inactive: null
    type: Alsa
  capture_samplerate: 48000
  chunksize: 1024
  enable_rate_adjust: null
  multithreaded: null
  playback:
    channels: 4
    device: "null"
    format: null
    type: Alsa
  queuelimit: null
  rate_measure_interval: null
  resampler: null
  samplerate: 48000
  silence_threshold: null
  silence_timeout: null
  stop_on_rate_change: null
  target_level: null
  volume_limit: null
  volume_ramp_time: null
  worker_threads: null
filters: {}
mixers:
  Mixer:
    description: null
    channels:
      in: 4
      out: 4
    mapping: []
    labels: null
processors: {}
pipeline:
- type: Mixer
  name: Mixer
  description: null
  bypassed: null
title: default"""
        
        with open(CFG_FILE, "w", encoding="utf-8") as f:
            f.write(yaml_content)
            
        import tempfile
        # Purge CamillaGUI statefile because it often overrides physical camilladsp.yml on start
        STATE_FILE = os.path.dirname(CFG_FILE).replace("config", "statefile.yml")
        if os.path.exists(STATE_FILE):
            try: os.remove(STATE_FILE)
            except: pass
        if os.path.exists("/root/camilladsp/statefile.yml"):
            try: os.remove("/root/camilladsp/statefile.yml")
            except: pass
        
        import os, threading
        def restart_svc():
            import time
            time.sleep(0.5)
            os.system("systemctl --user restart camilladsp.service || systemctl restart camilladsp.service || systemctl restart camilladsp-web")
        threading.Thread(target=restart_svc).start()
            
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

# ── Presets ───────────────────────────────────────────────────────────────────
def _preset_path(name):
    # Sanitize: keep only alphanumeric, spaces, hyphens, underscores
    safe = "".join(c for c in name if c.isalnum() or c in (" ", "-", "_")).strip()
    if not safe:
        raise ValueError("Invalid preset name")
    return os.path.join(PRESETS_DIR, safe + ".yml")

@app.route("/api/cpuload", methods=["GET"])
def get_cpu_load():
    try:
        out = subprocess.check_output(
            "top -bn1 | awk '/Cpu/ {print 100 - $8}'",
            shell=True, text=True, timeout=3
        ).strip()
        return jsonify({"ok": True, "cpu": out + "%"})
    except Exception as e:
        return jsonify({"ok": False, "cpu": "—"})

@app.route("/api/presets", methods=["GET"])
def list_presets():
    try:
        files = sorted(
            f[:-4] for f in os.listdir(PRESETS_DIR)
            if f.endswith(".yml")
        )
        return jsonify({"ok": True, "presets": files})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "presets": []})

@app.route("/api/presets/save", methods=["POST"])
def save_preset():
    try:
        name = request.json.get("name", "").strip()
        cfg  = request.json.get("config")
        if not name or not cfg:
            return jsonify({"ok": False, "error": "Missing name or config"}), 400
        path = _preset_path(name)
        if HAS_YAML:
            with open(path, "w") as f:
                yaml.dump(cfg, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
        else:
            with open(path, "w") as f:
                json.dump(cfg, f)
        return jsonify({"ok": True, "name": os.path.basename(path)[:-4]})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/presets/load", methods=["POST"])
def load_preset():
    try:
        name = request.json.get("name", "").strip()
        if not name:
            return jsonify({"ok": False, "error": "Missing name"}), 400
        path = _preset_path(name)
        if not os.path.exists(path):
            return jsonify({"ok": False, "error": "Preset not found"}), 404
        if HAS_YAML:
            with open(path, "r") as f:
                cfg = yaml.safe_load(f) or {}
        else:
            with open(path, "r") as f:
                cfg = json.load(f)
        # Apply to DSP
        cdsp("SetConfigJson", json.dumps(cfg))
        save_yaml_config(cfg)
        return jsonify({"ok": True, "config": cfg})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/presets/delete", methods=["POST"])
def delete_preset():
    try:
        name = request.json.get("name", "").strip()
        if not name:
            return jsonify({"ok": False, "error": "Missing name"}), 400
        path = _preset_path(name)
        if os.path.exists(path):
            os.remove(path)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

if __name__ == "__main__":
    print(f"CamillaDSP Web GUI → http://0.0.0.0:{WEB_PORT}")
    app.run(host="0.0.0.0", port=WEB_PORT, threaded=True)
