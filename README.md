# CamillaDSP Web Console & Auto-Installer

Complete solution for automated deployment of the **CamillaDSP** ecosystem on any Linux device (TV-Box, Raspberry Pi, server). Includes DSP engine, backend GUI, and a custom web frontend with premium design accessible from any browser.

---

## Features

### Installer
- **Automatic dependency resolution**: installs `curl`, `wget`, `python3-pip`, `jq` automatically
- **Smart cleanup**: detects previous/corrupted installations, frees blocked ports, removes old files
- **CRLF/LF handling**: `.gitattributes` prevents line ending issues when cloning from Windows
- **Auto-start**: configures systemd/rc.local/cron to start services on boot
- **Retry logic**: services retry up to 5 times on startup failure
- **Port management**: frees port 5000 before starting web server

### Web Console (port 5000)
- **VU Meters**: real-time RMS levels, peak hold, compressor gain reduction, per-channel faders with polarity invert
- **Graphic EQ**: 31-band linear-phase equalizer with drag control and touch support
- **Parametric EQ**: full-range interactive graph (20 Hz - 20 kHz), drag-and-drop filters, REW/APO import
- **Crossovers**: Butterworth and Linkwitz-Riley filters up to 48 dB/octave
- **Mixer**: real-time channel routing matrix with custom channel naming
- **Device selection**: only shows ALSA hw: devices (not plughw/dmix), current device marked with arrow
- **Reset wizard**: modal with device selectors, auto-probe of hardware params, sample rate selector, auto-restart engine
- **Presets**: save/load/delete complete DSP configurations
- **Compressor**: dynamic compressor with attack, release, threshold, ratio, makeup gain
- **Touch-friendly**: long-press for bypass/delete, double-tap to add filters, fullscreen mode

### Backend API (server.py)
- GET/POST config via WebSocket to CamillaDSP
- PATCH config (partial updates)
- Status, levels, volume control
- ALSA device listing (hw: format with card names)
- Hardware probe (channels, rate, format) with fallback for busy devices
- Format mapping: ALSA to CamillaDSP (S16_LE, S24_3_LE, S24_4_LE, S32_LE, F32_LE, F64_LE)
- Engine restart via CamillaGUI
- Flask 3.x compatible (json.loads instead of request.json)

---

## Quick Install

```bash
git clone https://github.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend.git
cd camilladsp-auto-install-with-back-and-frontend
bash install_camilladsp.sh
```

### Install Options
```bash
bash install_camilladsp.sh [options]

  (no options)    Full interactive installation
  --update       Update engine and GUI to latest version
  --check        Check status of all processes
  --uninstall    Remove entire CamillaDSP environment
  --no-service   Install files but don't start services
```

---

## Services & Ports

| Component | Protocol | Port | Description |
|---|---|---|---|
| **Web Console** | HTTP | `5000` | Custom frontend (this project) |
| **CamillaGUI** | HTTP | `5005` | Official backend/GUI by HEnquist |
| **CamillaDSP Engine** | WebSocket | `1234` | DSP engine control API |

---

## Directory Structure

```text
~/camilladsp/
+-- engine/             # CamillaDSP binary
+-- gui/                # CamillaGUI backend
+-- web/                # Web console (Flask server + frontend)
+-- config/             # Pipeline config, presets, YAML
+-- coeffs/             # FIR coefficients
+-- scripts/            # start_all.sh | stop_all.sh | status.sh
+-- logs/               # Engine and frontend logs
+-- pids/               # Process ID files
```

---

## Configuration Reset (Web UI)

The Reset button opens a modal that:
1. Lists ALSA hardware capture and playback devices (hw:X,Y format)
2. Auto-probes selected device for channels, sample rate, and format
3. Lets you choose sample rate (44100/48000/96000/192000 Hz)
4. Creates a complete config with Mixer 1 and sends it to the DSP
5. Automatically restarts the engine

---

## ALSA Device Format Mapping

| ALSA Format | CamillaDSP Format |
|---|---|
| S16_LE | S16_LE |
| S24_3LE | S24_3_LE |
| S24_LE | S24_4_LE |
| S24_4LE | S24_4_LE |
| S32_LE | S32_LE |
| FLOAT_LE | F32_LE |
| FLOAT64_LE | F64_LE |

---

## Troubleshooting

1. **Web UI shows no audio devices**: Make sure the CamillaDSP engine is running. Run `~/camilladsp/scripts/status.sh` and verify engine (1234) and GUI (5005) are active. Check logs in `~/camilladsp/logs/`.
2. **Audio dropouts or glitches**: Go to the MIXER tab, increase Chunksize (512 -> 1024 -> 2048) and click Engine restart.
3. **Installer freezes**: Press Ctrl+C and run `bash install_camilladsp.sh` again. It will detect the interrupted install and offer cleanup.
4. **Engine stays Inactive after Reset**: The engine needs a valid config to start. Make sure you selected capture and playback devices in the Reset modal, then click Create Config. The engine will auto-restart.

---

> Deployed, tested, and configured on Linux embedded devices, modified TV-Boxes (Armbian Debian Trixie/Ubuntu), and general-purpose servers.