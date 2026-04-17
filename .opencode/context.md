# Contexto del Proyecto — CamillaDSP Auto-Install

## Proyecto
**camilladsp-auto-install-with-back-and-frontend**

Solución completa para automatizar el despliegue de CamillaDSP en dispositivos Linux (TV-Box, Raspberry Pi, servidores). Incluye:
- Instalador automático (`install_camilladsp.sh`)
- Backend Flask (`web/server.py`) — puerto 5000
- Frontend web (`web_index.html`) — interfaz de control DSP
- Motor CamillaDSP — WebSocket puerto 1234
- CamillaGUI oficial — puerto 5005

## Stack Tecnológico
- **Backend**: Python 3 / Flask + websocket-client
- **Frontend**: HTML/CSS/JS (archivo único `web_index.html`, 82KB)
- **DSP Engine**: CamillaDSP (WebSocket API en `ws://127.0.0.1:1234`)
- **GUI Oficial**: CamillaGUI (`http://127.0.0.1:5005`)
- **Config**: YAML (`/root/camilladsp/config/camilladsp.yml`)
- **Presets**: `/root/camilladsp/config/presets/`
- **Instalador**: Bash script con opciones `--update`, `--check`, `--uninstall`, `--no-service`

## Funcionalidades Implementadas (Backend — server.py)
- GET/POST config (get/set YAML config via WebSocket)
- PATCH config (patch parcial)
- Status del motor (estado, buffer, load)
- Niveles RMS en tiempo real (capture/playback/volume)
- Control de volumen
- Exportar config como YAML
- Listar dispositivos ALSA (capture y playback)
- Restart del motor (stop + start via CamillaGUI)
- Recovery (reset a config default + purge statefile)
- Presets: listar, guardar, cargar, eliminar
- CPU load via top
- **GET /api/alsa-hw-capture** — lista dispositivos hw: de captura con card_name (formato hw:X,Y)
- **GET /api/alsa-hw-playback** — lista dispositivos hw: de reproducción con card_name (formato hw:X,Y)
- **GET /api/alsa-probe** — probea hw params (channels, rate, format) de un dispositivo ALSA
  - Fallback a /proc/asound cuando dispositivo está ocupado
  - Mapeo de formatos ALSA a formatos CamillaDSP (S16_LE, S24_3LE, S24_4LE, S32_LE, F32_LE, F64_LE)
  - Rate máxima extraída de rangos como [44100 48000]
  - Filtro de SUBFORMAT para no confundir con FORMAT
- **POST /api/config** — usa json.loads(request.data) en vez de request.json (Flask 3.x fix)
- **GET /api/capturedevices** — solo dispositivos hw: y null (filtrado)
- **GET /api/playbackdevices** — solo dispositivos hw: y null (filtrado), convierte hw:CARD=name a hw:X,Y

## Funcionalidades Frontend — Reset con selector ALSA
- Modal overlay en vez de prompts
- Selectores de dispositivos hw: (captura y reproducción) con opción "null"
- Probe automático al seleccionar (muestra canales, rate, formato disponibles)
- Selector de Sample Rate (44100/48000/96000/192000) con detección automática del máximo
- Botón "Crear Config" que genera YAML completo con datos del hardware
- Mixer configurado como "Mixer 1" con channels in/out según dispositivos, mapping vacío
- stripNulls() elimina valores null del JSON antes de enviar a CamillaDSP
- Manejo de errores con toast en setFullConfig()

## Funcionalidades Frontend — Mixer
- Selectores de dispositivos IN/OUT muestran solo hw:X,Y y null
- Dispositivo actual pre-seleccionado y marcado con ▶ en verde/negrita
- Si el dispositivo actual no está en la lista, se agrega como "(dispositivo actual)"

## Bugs Fixed
- Flask 3.x: request.json falla → json.loads(request.data) con try/except
- _list_hw_devices: UnboundLocalError en tupla unpack → asignación separada
- _list_hw_devices: regex no matcheaba dispositivos con [] vacío → regex mejorado
- _get_alsa_hw: hw:CARD=name no coincide con hw:X,Y del config → conversión via /proc/asound/cards
- SUBFORMAT:STD confundido con FORMAT → filtro con startswith("FORMAT:")
- Probe devuelve vacío cuando dispositivo busy → fallback a /proc/asound

## Pendiente / Notas
- (Actualizar al final de cada sesión con el progreso realizado)

## MCP Servers Configurados
- **filesystem** (`@modelcontextprotocol/server-filesystem`): lectura/escritura directa de archivos del proyecto
- **notebooklm** (`@m4ykeldev/notebooklm-mcp`): integración con Google NotebookLM (32 herramientas — notebooks, fuentes, research, studio)
  - Requiere autenticación: `npx -y @m4ykeldev/notebooklm-mcp auth`
  - Credenciales en `~/.notebooklm-mcp/auth.json`

## Última sesión: 2026-04-17 (Sesión 2 — Dante/Inferno)
- Inferno ALSA plugin compilado e instalado en TV-Box 192.168.1.127 (aarch64)
- Statime PTP daemon compilado e instalado (con patch para identity manual)
- .asoundrc configurado con pcm.inferno_rx/tx + CLOCK_PATH=/tmp/ptp-usrvclock
- Statime systemd service creado (statime-inferno.service, wlan1, hardware-clock=none)
- PipeWire instalado y corriendo (aunque no necesario — CamillaDSP acepta inferno_rx directo)
- CamillaDSP acepta device: "inferno_rx" como dispositivo ALSA
- Sin dispositivo Dante master en la red, inferno devuelve "no clock available" (esperado)
- dante-aarch64.zip guardado en workspace (binarios precompilados para redistribución)
- Backend: nuevos endpoints /api/dante-status, /api/dante-config
- Backend: _list_hw_devices() ahora incluye inferno_rx/tx en capture/playback
- Backend: /api/alsa-probe detecta dispositivos "inferno*" y devuelve S32_LE/2ch/48kHz
- Statime config: virtual-system-clock-base=tai, identity=a871166c70900000, wlan1, PTPv1

## Pendiente
- Frontend: selector de dispositivo Dante, indicador PTP, panel config Dante
- Prueba end-to-end con hardware Dante presente
- Sincronizar a segunda TV-Box (192.168.1.101) cuando esté conectada
- Agregar --dante flag a install_camilladsp.sh