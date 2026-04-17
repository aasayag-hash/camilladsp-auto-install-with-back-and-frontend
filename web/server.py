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
app.config['MAX_CONTENT_LENGTH'] = 5 * 1024 * 1024
_lock = threading.Lock()
_ws   = None

@app.errorhandler(400)
def bad_request(e):
    import traceback
    traceback.print_exc()
    return jsonify({"ok": False, "error": f"400: {str(e)}", "debug": traceback.format_exc()}), 400

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
        raw = request.data
        print(f"[set_config] raw body length: {len(raw)}, content_type: {request.content_type}")
        try:
            data = json.loads(raw)
        except Exception as e:
            print(f"[set_config] json.loads failed: {e}")
            return jsonify({"ok": False, "error": f"JSON parse error: {e}"}), 400
        cfg = data.get("config")
        if cfg is None:
            return jsonify({"ok": False, "error": "Missing 'config' key"}), 400
        def strip_nulls(obj):
            if isinstance(obj, dict):
                return {k: strip_nulls(v) for k, v in obj.items() if v is not None}
            if isinstance(obj, list):
                return [strip_nulls(v) for v in obj]
            return obj
        cfg = strip_nulls(cfg)
        print(f"[set_config] Sending config to CamillaDSP: {json.dumps(cfg)[:200]}...")
        result = cdsp("SetConfigJson", json.dumps(cfg))
        print(f"[set_config] CamillaDSP result: {result}")
        save_yaml_config(cfg)
        return jsonify({"ok": True})
    except Exception as e:
        print(f"[set_config] ERROR: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/patch", methods=["POST"])
def patch_config():
    try:
        data = json.loads(request.data)
        cdsp("PatchConfig", data.get("patch"))
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
        cdsp("SetVolume", float(json.loads(request.data).get("volume", 0.0)))
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
    import re
    card_map = {}
    try:
        with open("/proc/asound/cards") as f:
            for line in f:
                m = re.match(r'\s*(\d+)\s+\[(\w+)\s*\]:\s+(.+)', line)
                if m:
                    card_map[m.group(2)] = (int(m.group(1)), m.group(3).strip())
    except Exception:
        pass
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
                if current_id and (current_id.startswith("hw:") or current_id == "null"):
                    hw_id = current_id
                    m = re.match(r'hw:CARD=(\w+),DEV=(\d+)', current_id)
                    if m and m.group(1) in card_map:
                        hw_id = f"hw:{card_map[m.group(1)][0]},{m.group(2)}"
                    desc_str = " - ".join([d.strip(" ,") for d in current_desc if d.strip(" ,")])
                    devs.append([hw_id, desc_str])
                current_id = line.strip()
                current_desc = []
            else:
                current_desc.append(line.strip())
        if current_id and (current_id.startswith("hw:") or current_id == "null"):
            hw_id = current_id
            m = re.match(r'hw:CARD=(\w+),DEV=(\d+)', current_id)
            if m and m.group(1) in card_map:
                hw_id = f"hw:{card_map[m.group(1)][0]},{m.group(2)}"
            desc_str = " - ".join([d.strip(" ,") for d in current_desc if d.strip(" ,")])
            devs.append([hw_id, desc_str])
    except Exception:
        pass
    return devs

@app.route("/api/capturedevices")
def get_capture_devices():
    try:
        data = _list_hw_devices("capture")
        if not data:
            data = _cdsp_gui_get("/api/capturedevices/Alsa")
        return jsonify({"ok": True, "devices": data})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e), "devices": []})

@app.route("/api/playbackdevices")
def get_playback_devices():
    try:
        data = _list_hw_devices("playback")
        if not data:
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

DEFAULT_CONFIG_YAML = """\
description: default
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
  Mixer 1:
    channels:
      in: 4
      out: 4
    description: null
    labels: null
    mapping: []
pipeline: []
processors: {}
title: default
"""

def _restart_all_services():
    try:
        subprocess.run(["systemctl", "restart", "camilladsp"], timeout=10)
    except Exception: pass
    import time; time.sleep(2)
    try:
        subprocess.run(["systemctl", "restart", "camilladsp-web"], timeout=10)
    except Exception: pass
    import time; time.sleep(3)

@app.route("/api/recovery", methods=["POST"])
def recover_engine():
    try:
        with open(CFG_FILE, "w") as f:
            f.write(DEFAULT_CONFIG_YAML)
        _restart_all_services()
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
        d = json.loads(request.data)
        name = d.get("name", "").strip()
        cfg  = d.get("config")
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

def _increment_inferno_pid(device_name):
    """Incrementa el PROCESS_ID del bloque inferno exacto en .asoundrc."""
    import re
    asoundrc = os.path.expanduser("~/.asoundrc")
    try:
        content = open(asoundrc).read()
        # Buscar el bloque exacto: pcm.inferno_rx { ... } o pcm.inferno_tx { ... }
        # device_name puede ser "inferno_rx", "inferno_tx", etc.
        block_name = device_name.strip()
        # Extraer solo el bloque exacto y reemplazar su PROCESS_ID
        block_pat = re.compile(
            r'(pcm\.' + re.escape(block_name) + r'\s*\{)([^}]*?)(PROCESS_ID\s*")(\d+)(")',
            re.DOTALL
        )
        m = block_pat.search(content)
        if not m:
            print(f"[inferno] bloque {block_name} no encontrado en .asoundrc")
            return
        old = int(m.group(4))
        new = old + 1
        new_content = block_pat.sub(
            lambda x: x.group(1) + x.group(2) + x.group(3) + str(new) + x.group(5),
            content, count=1
        )
        open(asoundrc, "w").write(new_content)
        print(f"[inferno] {block_name} PROCESS_ID: {old} -> {new}")
    except Exception as e:
        print(f"[inferno] error incrementando PROCESS_ID: {e}")

@app.route("/api/presets/load", methods=["POST"])
def load_preset():
    try:
        name = json.loads(request.data).get("name", "").strip()
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
        # Si usa inferno, incrementar PROCESS_ID antes de aplicar para liberar puerto anterior
        capture_dev = cfg.get("devices", {}).get("capture", {}).get("device", "")
        playback_dev = cfg.get("devices", {}).get("playback", {}).get("device", "")
        if "inferno" in capture_dev:
            _increment_inferno_pid(capture_dev)
        if "inferno" in playback_dev:
            _increment_inferno_pid(playback_dev)
        # Apply to DSP
        cdsp("SetConfigJson", json.dumps(cfg))
        save_yaml_config(cfg)
        return jsonify({"ok": True, "config": cfg})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

@app.route("/api/presets/delete", methods=["POST"])
def delete_preset():
    try:
        name = json.loads(request.data).get("name", "").strip()
        if not name:
            return jsonify({"ok": False, "error": "Missing name"}), 400
        path = _preset_path(name)
        if os.path.exists(path):
            os.remove(path)
        return jsonify({"ok": True})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)}), 500

# ── ALSA hw device probe ──────────────────────────────────────────────────────
def _parse_proc_cards():
    cards = {}
    try:
        with open("/proc/asound/cards", "r") as f:
            for line in f:
                m = __import__("re").match(r"\s*(\d+)\s+\[(\w+)\s*\]:\s+(.+)", line)
                if m:
                    cards[int(m.group(1))] = {"id": m.group(2), "name": m.group(3).strip()}
    except: pass
    return cards

def _list_hw_devices(mode):
    devices = [{"id": "null", "card_name": "null", "desc": "Discard all samples"}]
    cards = _parse_proc_cards()
    try:
        cmd = ["aplay", "-l"] if mode == "playback" else ["arecord", "-l"]
        out = subprocess.check_output(cmd, text=True, timeout=5)
        import re
        for line in out.splitlines():
            m = re.match(r"card (\d+): (\S+)\s+\[.*\], device (\d+):.*\[(.*)\]", line)
            if m:
                cnum = int(m.group(1))
                cid = m.group(2)
                dnum = int(m.group(3))
                desc = m.group(4).strip() or cid
                dev_id = f"hw:{cnum},{dnum}"
                card_name = cards.get(cnum, {}).get("name", cid)
                devices.append({"id": dev_id, "card_name": card_name, "desc": desc})
    except Exception as e:
        print(f"[ERROR] _list_hw_devices({mode}): {e}")
    dante_devs = _list_dante_devices(mode)
    devices.extend(dante_devs)
    return devices

def _list_dante_devices(mode):
    devs = []
    try:
        cmd = ["aplay", "-L"] if mode == "playback" else ["arecord", "-L"]
        out = subprocess.check_output(cmd, text=True, timeout=3)
        target = "inferno_tx" if mode == "playback" else "inferno_rx"
        for line in out.splitlines():
            line = line.strip()
            if line == target:
                devs.append({"id": target, "card_name": "Dante", "desc": "Dante/AES67 Network Audio" + (" (RX)" if "rx" in target else " (TX)")})
        if "inferno" not in out:
            pass
    except Exception:
        pass
    for alt in (["inferno_rx"] if mode == "capture" else ["inferno_tx"]):
        if not any(d["id"] == alt for d in devs):
            devs.append({"id": alt, "card_name": "Dante", "desc": "Dante/AES67 Network Audio" + (" (RX)" if "rx" in alt else " (TX)") + " (not detected)"})
    return devs

@app.route("/api/alsa-hw-capture")
def alsa_hw_capture():
    return jsonify({"ok": True, "devices": _list_hw_devices("capture")})

@app.route("/api/alsa-hw-playback")
def alsa_hw_playback():
    return jsonify({"ok": True, "devices": _list_hw_devices("playback")})

CDSP_FORMATS = {'S16_LE', 'S24_3_LE', 'S24_4_LE', 'S32_LE', 'F32_LE', 'F64_LE'}

ALSACTL_MAP = {
    'S16_LE': 'S16_LE', 'S24_3LE': 'S24_3_LE', 'S24_LE': 'S24_4_LE',
    'S32_LE': 'S32_LE', 'FLOAT_LE': 'F32_LE', 'FLOAT64_LE': 'F64_LE',
    'S24_4LE': 'S24_4_LE', 'F32_LE': 'F32_LE', 'F64_LE': 'F64_LE',
}

def _to_cdsp_fmt(fmt_list):
    for f in fmt_list:
        mapped = ALSACTL_MAP.get(f)
        if mapped and mapped in CDSP_FORMATS:
            return mapped
    return None

import re as _re

def _parse_hw_params_proc(device, mode):
    m = _re.match(r'hw:(\d+),(\d+)', device)
    if not m:
        return None
    card, dev = m.group(1), m.group(2)
    stream = "c" if mode == "capture" else "p"
    path = f"/proc/asound/card{card}/pcm{dev}{stream}/sub0/hw_params"
    try:
        with open(path) as f:
            text = f.read()
        if "closed" in text.lower():
            return None
        info = {}
        for line in text.strip().splitlines():
            k, _, v = line.partition(":")
            k, v = k.strip().lower(), v.strip()
            if k == "format":
                info["format"] = ALSACTL_MAP.get(v, v)
            elif k == "channels":
                info["channels"] = v
            elif k == "rate":
                nums = _re.findall(r'\d+', v)
                info["rate"] = str(max(map(int, nums))) if nums else v
        return info
    except:
        return None

@app.route("/api/alsa-probe")
def alsa_probe():
    device = request.args.get("device", "")
    mode = request.args.get("mode", "capture")
    if not device:
        return jsonify({"ok": False, "error": "Missing device parameter"}), 400
    if device.startswith("inferno"):
        return jsonify({"ok": True, "probe": {
            "device": device, "formats": ["S32_LE"], "format": "S32_LE",
            "channels": "2", "rate": 48000, "dante": True
        }})
    result = {"device": device, "formats": []}
    try:
        cmd = ["aplay", "--dump-hw-params", "-D", device, "/dev/zero"] if mode == "playback" else ["arecord", "--dump-hw-params", "-D", device, "/dev/null"]
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        output = proc.stderr + proc.stdout
        print(f"[alsa_probe] cmd={' '.join(cmd)}, rc={proc.returncode}, output={output[:300]}")
        formats_raw = []
        found = False
        for line in output.splitlines():
            if "CHANNELS:" in line:
                vals = line.split(":", 1)[1].strip()
                result["channels"] = vals
                found = True
            elif line.startswith("RATE:"):
                vals = line.split(":", 1)[1].strip()
                result["rate_raw"] = vals
                nums = [int(x) for x in _re.findall(r'\d+', vals)]
                result["rate"] = max(nums) if nums else 48000
                found = True
            elif line.startswith("FORMAT:"):
                vals = line.split(":", 1)[1].strip()
                formats_raw = [v.strip() for v in vals.split()]
                found = True
        result["formats"] = formats_raw
        result["format"] = _to_cdsp_fmt(formats_raw)
        if not found:
            proc_info = _parse_hw_params_proc(device, mode)
            if proc_info:
                result.update(proc_info)
                if "format" in proc_info:
                    fmt = proc_info["format"]
                    mapped = ALSACTL_MAP.get(fmt)
                    result["format"] = mapped if mapped else fmt
                    result["formats"] = [fmt]
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})
    return jsonify({"ok": True, "probe": result})

# ── Dante / Inferno endpoints ───────────────────────────────────────────────────

DANTE_ASOUNDRC = os.path.expanduser("~/.asoundrc")

def _dante_service_active():
    try:
        out = subprocess.check_output(["systemctl", "is-active", "statime-inferno"], text=True, timeout=3).strip()
        return out == "active"
    except Exception:
        return False

def _dante_ptp_status():
    try:
        out = subprocess.check_output(
            ["journalctl", "-u", "statime-inferno", "--no-pager", "-n", "50"],
            text=True, timeout=3
        )
        has_master = "Recommended state port" in out and "M2(" in out
        lines = [l for l in out.splitlines() if "offset" in l.lower() or "delay" in l.lower()]
        offset_ns = None
        delay_ns = None
        for l in lines[-3:]:
            import re as _r
            m = _r.search(r"offset\s+([-\d.]+)ns", l)
            if m:
                try: offset_ns = float(m.group(1))
                except: pass
            m = _r.search(r"delay\s+([-\d.]+)", l)
            if m:
                try: delay_ns = float(m.group(1))
                except: pass
        locked = has_master
        return {"locked": locked, "offset_ns": offset_ns, "delay_ns": delay_ns, "raw_log": out[-500:]}
    except Exception as e:
        return {"locked": False, "offset_ns": None, "delay_ns": None, "raw_log": str(e)}

@app.route("/api/dante-status")
def dante_status():
    try:
        svc = _dante_service_active()
        ptp = _dante_ptp_status() if svc else {"locked": False, "offset_ns": None, "delay_ns": None, "raw_log": ""}
        devices = []
        for d in ["inferno_rx", "inferno_tx"]:
            try:
                cmd = ["arecord", "-L"] if "rx" in d else ["aplay", "-L"]
                out = subprocess.check_output(cmd, text=True, timeout=3)
                if d in out:
                    devices.append(d)
            except:
                pass
        inf_so = os.path.exists("/usr/lib/aarch64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so") or \
                 os.path.exists("/usr/lib/x86_64-linux-gnu/alsa-lib/libasound_module_pcm_inferno.so")
        return jsonify({
            "ok": True,
            "service_active": svc,
            "ptp": ptp,
            "devices": devices,
            "inferno_installed": inf_so,
            "asoundrc_exists": os.path.exists(DANTE_ASOUNDRC)
        })
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})

@app.route("/api/dante-config", methods=["POST"])
def dante_config():
    try:
        d = json.loads(request.data)
        bind_ip = d.get("bind_ip", "192.168.1.127")
        sample_rate = d.get("sample_rate", "48000")
        rx_channels = d.get("rx_channels", "2")
        tx_channels = d.get("tx_channels", "2")
        clock_path = d.get("clock_path", "/tmp/ptp-usrvclock")
        asoundrc = f"""pcm.inferno {{
    type inferno
    @args.NAME {{ type string }}
    @args.DEVICE_ID {{ type string }}
    @args.BIND_IP {{ type string }}
    @args.SAMPLE_RATE {{ type string }}
    @args.PROCESS_ID {{ type string }}
    @args.ALT_PORT {{ type string }}
    @args.RX_CHANNELS {{ type string }}
    @args.TX_CHANNELS {{ type string }}
    @args.CLOCK_PATH {{ type string }}
    @args.RX_LATENCY_NS {{ type string }}
    @args.TX_LATENCY_NS {{ type string }}
    NAME $NAME
    DEVICE_ID $DEVICE_ID
    BIND_IP $BIND_IP
    SAMPLE_RATE $SAMPLE_RATE
    PROCESS_ID $PROCESS_ID
    ALT_PORT $ALT_PORT
    RX_CHANNELS $RX_CHANNELS
    TX_CHANNELS $TX_CHANNELS
    CLOCK_PATH $CLOCK_PATH
    RX_LATENCY_NS $RX_LATENCY_NS
    TX_LATENCY_NS $TX_LATENCY_NS
}}

pcm.inferno_rx {{
    type inferno
    BIND_IP "{bind_ip}"
    SAMPLE_RATE "{sample_rate}"
    RX_CHANNELS "{rx_channels}"
    TX_CHANNELS "0"
    PROCESS_ID "0"
    CLOCK_PATH "{clock_path}"
}}

pcm.inferno_tx {{
    type inferno
    BIND_IP "{bind_ip}"
    SAMPLE_RATE "{sample_rate}"
    RX_CHANNELS "0"
    TX_CHANNELS "{tx_channels}"
    PROCESS_ID "1"
    ALT_PORT "8700"
    CLOCK_PATH "{clock_path}"
}}
"""
        with open(DANTE_ASOUNDRC, "w") as f:
            f.write(asoundrc)
        return jsonify({"ok": True, "asoundrc": asoundrc})
    except Exception as e:
        return jsonify({"ok": False, "error": str(e)})


# == Dante Subscription endpoints ==
import re as _re

INFERNO_STATE = os.path.expanduser('~/.local/state/inferno_aoip')

def _find_active_rx_dir():
    PAT_IP  = r'inferno_rx' + r'\s*\{[^}]*BIND_IP\s+' + '"([^"]+)"'
    PAT_PID = r'inferno_rx' + r'\s*\{[^}]*PROCESS_ID\s+' + '"([^"]+)"'
    try:
        asoundrc = open(DANTE_ASOUNDRC).read()
        m_ip  = _re.search(PAT_IP,  asoundrc, _re.DOTALL)
        m_pid = _re.search(PAT_PID, asoundrc, _re.DOTALL)
        if m_ip and m_pid:
            parts   = m_ip.group(1).split('.')
            ip_hex  = ''.join('{:02x}'.format(int(p)) for p in parts)
            pid_hex = '{:04x}'.format(int(m_pid.group(1)))
            cand = os.path.join(INFERNO_STATE, '0000' + ip_hex + pid_hex)
            if os.path.exists(cand):
                return cand
    except Exception:
        pass
    try:
        for d in sorted(os.listdir(INFERNO_STATE), reverse=True):
            path = os.path.join(INFERNO_STATE, d, 'rx_subscriptions.toml')
            if os.path.exists(path) and 'tx_hostname' in open(path).read():
                return os.path.join(INFERNO_STATE, d)
    except Exception:
        pass
    return None

@app.route('/api/dante-subscriptions', methods=['GET'])
def dante_get_subscriptions():
    try:
        rx_dir = _find_active_rx_dir()
        if not rx_dir:
            return jsonify({'ok': True, 'channels': []})
        sub_file = os.path.join(rx_dir, 'rx_subscriptions.toml')
        if not os.path.exists(sub_file):
            return jsonify({'ok': True, 'channels': []})
        channels = []
        current = {}
        for line in open(sub_file):
            line = line.strip()
            if line == '[[channels]]':
                if current:
                    channels.append(current)
                current = {}
            elif '=' in line:
                k, v = line.split('=', 1)
                k = k.strip(); v = v.strip().strip('"')
                try: v = int(v)
                except Exception: pass
                current[k] = v
        if current:
            channels.append(current)
        return jsonify({'ok': True, 'channels': channels, 'rx_dir': rx_dir})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)})

@app.route('/api/dante-subscriptions', methods=['POST'])
def dante_set_subscriptions():
    try:
        PAT_IP  = r'inferno_rx' + r'\s*\{[^}]*BIND_IP\s+' + '"([^"]+)"'
        PAT_PID = r'inferno_rx' + r'\s*\{[^}]*PROCESS_ID\s+' + '"([^"]+)"'
        d = json.loads(request.data)
        channels = d.get('channels', [])
        rx_dir = _find_active_rx_dir()
        if not rx_dir:
            asoundrc = open(DANTE_ASOUNDRC).read()
            m_ip  = _re.search(PAT_IP,  asoundrc, _re.DOTALL)
            m_pid = _re.search(PAT_PID, asoundrc, _re.DOTALL)
            if m_ip and m_pid:
                parts   = m_ip.group(1).split('.')
                ip_hex  = ''.join('{:02x}'.format(int(p)) for p in parts)
                pid_hex = '{:04x}'.format(int(m_pid.group(1)))
                rx_dir  = os.path.join(INFERNO_STATE, '0000' + ip_hex + pid_hex)
            else:
                return jsonify({'ok': False, 'error': 'No se pudo determinar directorio inferno_rx'})
        os.makedirs(rx_dir, exist_ok=True)
        sub_file = os.path.join(rx_dir, 'rx_subscriptions.toml')
        out = []
        for ch in channels:
            out.append('[[channels]]')
            out.append('local_channel_id = ' + str(ch['local_channel_id']))
            out.append('local_channel_name = "' + ch['local_channel_name'] + '"')
            out.append('tx_channel_name = "' + ch['tx_channel_name'] + '"')
            out.append('tx_hostname = "' + ch['tx_hostname'] + '"')
            out.append('')
        open(sub_file, 'w').write(chr(10).join(out))
        return jsonify({'ok': True, 'file': sub_file, 'channels': len(channels)})
    except Exception as e:
        return jsonify({'ok': False, 'error': str(e)})

def _push_saved_config():
    import time
    time.sleep(3)
    try:
        cfg = load_yaml_config()
        if not cfg or not cfg.get("devices"):
            return
        def strip_nulls(obj):
            if isinstance(obj, dict):
                return {k: strip_nulls(v) for k, v in obj.items() if v is not None}
            if isinstance(obj, list):
                return [strip_nulls(v) for v in obj]
            return obj
        cfg = strip_nulls(cfg)
        cdsp("SetConfigJson", json.dumps(cfg))
        print(f"[startup] config aplicada al arranque")
    except Exception as e:
        print(f"[startup] no se pudo aplicar config: {e}")

if __name__ == "__main__":
    print(f"CamillaDSP Web GUI → http://0.0.0.0:{WEB_PORT}")
    threading.Thread(target=_push_saved_config, daemon=True).start()
    app.run(host="0.0.0.0", port=WEB_PORT, threaded=True)
