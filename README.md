# CamillaDSP Web Console

Instalador automático para **CamillaDSP** con interfaz web completa para ecualización gráfica y paramétrica, crossovers, compresión dinámica y control de dispositivos de audio.

---

## Descripción

Esta herramienta instala y configura automáticamente el ecosistema CamillaDSP en un dispositivo embebido (TV-box, Raspberry Pi, servidor Linux, etc.) y despliega una consola web accesible desde cualquier navegador de la red local.

### Componentes instalados

| Componente | Descripción | Puerto |
|---|---|---|
| **CamillaDSP Engine** | Motor DSP de alto rendimiento, procesamiento en tiempo real | WS `0.0.0.0:1234` |
| **CamillaGUI Backend** | API REST/WebSocket oficial de CamillaGUI | HTTP `0.0.0.0:5005` |
| **Web Console** | Interfaz web personalizada (este proyecto) | HTTP `0.0.0.0:5000` |

---

## Interfaz Web — Funciones

La consola web (`http://IP-DISPOSITIVO:5000`) cuenta con 5 pestañas:

### VÚMETROS
- Vúmetros RMS en tiempo real de todos los canales de entrada y salida
- Indicador de reducción de ganancia del compresor (GR) por canal
- Peak hold con retención de 2 segundos
- Indicador visual del umbral del compresor
- Faders de ganancia por canal (−∞ a +6 dB), arrastre con valor en tiempo real
- Control de polaridad (inversión de fase) por canal
- Retardo (delay) configurable en milisegundos por canal
- Mute individual por canal y MUTE ALL global
- Volumen maestro
- Tabla de compresores: Attack, Release, Threshold, Ratio, Makeup, ClipLimiter, Auto-release

### GRAPHIC EQ
- Ecualizador gráfico de **31 bandas** de fase lineal
- Rango **±9 dB**, escala lineal, marcas de referencia en 0 / ±3 / ±6 / ±9 dB
- Frecuencias de banda (patrón ×1.25/banda):
  `20, 26, 32, 41, 51, 65, 82, 103, 130, 163, 206, 259, 324, 405, 506, 632, 790, 988, 1.2k, 1.5k, 1.9k, 2.4k, 3.0k, 3.8k, 4.7k, 5.9k, 7.3k, 9.2k, 11k, 14k, 18k Hz`
- **Multiselección de canales**: aplicar a uno o varios canales de entrada simultáneamente (botón ALL o toggle individual)
- Tooltip con valor exacto en dB durante el arrastre
- Doble clic sobre una banda para resetearla a 0 dB
- Botones **Flat** (todas las bandas a 0) y **Reset canal** (elimina el filtro del pipeline)
- Solo aplicable a canales de **entrada**
- Filtro generado en CamillaDSP: `BiquadCombo / GraphicEqualizer`

### PARAMETRIC EQ
- Ecualizador paramétrico de precisión por canal (entradas y salidas)
- Gráfico de respuesta en frecuencia interactivo (20 Hz – 20 kHz, ±18 dB)
- Clic en el gráfico para añadir filtros; curva total en blanco
- Tipos de filtro: Peaking, Highshelf, Lowshelf, Highpass, Lowpass
- Parámetros editables: Frecuencia, Ganancia, Q
- **Importación de filtros REW / Equalizer APO**:
  - Formato REW Generic: `Filter 1: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.41`
  - Formato Equalizer APO: `Filter: ON PK Fc 1000 Hz Gain 3.0 dB Q 1.41`
  - HP/LP sin Gain, BW Oct para ancho de banda en octavas
  - Tipos soportados: PK, PEQ, LS, LSC, HS, HSC, HP, HPQ, LP, LPQ

### CROSSOVERS
- Filtros de división de frecuencia para sistemas multiamplificados
- Tipos: Butterworth LP/HP y Linkwitz-Riley LP/HP
- Órdenes: 2 (12 dB/oct), 4 (24 dB/oct), 8 (48 dB/oct)
- Gráfico de respuesta por canal; asignables a canales de salida

### MIXER
- Matriz de mezcla: enruta y combina entradas hacia salidas
- Selector de tarjeta de sonido de captura (IN) y reproducción (OUT) con dispositivos ALSA en tiempo real
- Selector de Chunksize: 128 / 256 / 512 / 1024 / 2048 / 4096 muestras
- Botón de reinicio del motor de audio (⟳ Motor)

### Barra superior
- Indicador de conexión al DSP (verde/rojo)
- Estado en tiempo real: **State**, **Buffer level**, **DSP load** (actualización cada 200 ms)
- Botones: Imp Cfg / Exp Cfg (YAML completo), Imp EQ / Exp EQ (filtros paramétricos), Reset
- **Cambio de idioma ES/EN** (persiste entre sesiones)
- **Panel de ayuda** completo integrado en la interfaz

---

## Puertos de red

| Servicio | Puerto | Acceso | Descripción |
|---|---|---|---|
| CamillaDSP WebSocket | `1234` | LAN (`0.0.0.0`) | API de control del motor DSP |
| CamillaGUI API | `5005` | LAN (`0.0.0.0`) | Backend REST para configuración avanzada |
| Web Console | `5000` | LAN (`0.0.0.0`) | Interfaz web principal (este proyecto) |

> El motor CamillaDSP arranca con `-a 0.0.0.0 -w` para exponer el WebSocket a toda la red local. Esto permite conectar herramientas externas (otras instancias de GUI, scripts, etc.) directamente al puerto 1234 desde cualquier dispositivo de la LAN.

---

## Requisitos

| Requisito | Detalle |
|---|---|
| Sistema operativo | Linux (ARM/x86), macOS, Windows (WSL) |
| Herramientas | `curl` o `wget`, `tar` / `unzip` |
| Python | Python 3 con `pip` (para el servidor web) |
| Paquetes Python | `flask`, `websocket-client`, `pyyaml` (instalados automáticamente) |
| Red | Acceso a internet durante la instalación |

---

## Instalación

### Instalación rápida

```bash
git clone https://github.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend.git
cd camilladsp-auto-install-with-back-and-frontend
bash install_camilladsp.sh
```

Al finalizar, el instalador muestra las URLs de acceso con la IP real del dispositivo.

### Opciones del instalador

```
bash install_camilladsp.sh [opciones]

  (sin opciones)    Instalación completa interactiva
  --update          Actualizar engine y GUI a la última versión
  --check           Verificar estado de la instalación actual
  --uninstall       Desinstalar completamente
  --dir=/ruta       Directorio de instalación personalizado (por defecto: ~/camilladsp)
  --no-service      Instalar sin iniciar servicios
  -h, --help        Mostrar ayuda
```

---

## Acceso después de instalar

```
Web Console:    http://IP-DISPOSITIVO:5000   ← interfaz principal
CamillaGUI:     http://IP-DISPOSITIVO:5005   ← GUI oficial (avanzado)
WebSocket DSP:  ws://IP-DISPOSITIVO:1234     ← API directa del engine
```

---

## Scripts de control

```bash
~/camilladsp/scripts/start_all.sh   # Iniciar todos los servicios
~/camilladsp/scripts/stop_all.sh    # Detener todos los servicios
~/camilladsp/scripts/status.sh      # Ver estado de servicios y puertos
```

---

## Estructura de directorios

```
~/camilladsp/
├── engine/
│   └── camilladsp          # Binario del motor DSP
├── gui/                    # Backend CamillaGUI
│   └── config/
│       └── camillagui.yml
├── web/
│   ├── index.html          # Interfaz Web Console
│   └── server.py           # Servidor Flask (proxy al engine)
├── config/
│   └── camilladsp.yml      # Configuración del pipeline de audio
├── coeffs/                 # Coeficientes de filtros FIR/IIR
├── logs/
│   ├── engine.log
│   ├── gui.log
│   └── web.log
├── pids/                   # PIDs de procesos activos
└── scripts/
    ├── start_all.sh        # Arranque (engine + GUI + web)
    ├── stop_all.sh         # Parada completa
    └── status.sh           # Estado de servicios
```

---

## Inicio automático con systemd (Linux)

```bash
# Habilitar inicio tras reinicio
systemctl --user enable camilladsp-engine.service
systemctl --user enable camilladsp-gui.service

# Verificar estado
systemctl --user status camilladsp-engine.service

# Ver logs en vivo
journalctl --user -u camilladsp-engine.service -f
```

---

## Troubleshooting

### La Web Console no carga (puerto 5000)

```bash
~/camilladsp/scripts/status.sh
cat ~/camilladsp/logs/web.log
ss -tlnp | grep 5000
```

### El engine no es accesible desde la LAN (puerto 1234)

El engine debe escuchar en `0.0.0.0:1234`, no en `127.0.0.1:1234`.

```bash
# Verificar (debe mostrar 0.0.0.0:1234)
ss -tlnp | grep 1234

# Si muestra 127.0.0.1:1234, corregir el script de arranque:
sed -i 's|start_svc engine.*-p 1234.*|start_svc engine $ENGINE $CONFIG -p 1234 -a 0.0.0.0 -w|' \
  ~/camilladsp/scripts/start_all.sh

# Reiniciar
~/camilladsp/scripts/stop_all.sh && ~/camilladsp/scripts/start_all.sh
```

### No hay sonido / error de dispositivo ALSA

```bash
# Listar dispositivos disponibles
aplay -l && arecord -l

# Ver errores del engine
tail -30 ~/camilladsp/logs/engine.log
```

Causas frecuentes:
- Nombre de dispositivo incorrecto → usar selector IN/OUT en la pestaña MIXER
- PulseAudio/PipeWire bloqueando el dispositivo → detener con `pulseaudio --kill` o `systemctl --user stop pipewire`
- Chunksize muy bajo → aumentar en el selector Chunk del MIXER (512 → 1024)

### Los selectores IN/OUT del Mixer aparecen vacíos

El listado de dispositivos viene de CamillaGUI (puerto 5005):

```bash
ss -tlnp | grep 5005
cat ~/camilladsp/logs/gui.log
```

### Alto consumo de CPU / dropouts

1. Aumentar Chunksize en la pestaña MIXER (512 → 1024 → 2048)
2. Revisar **DSP load** en la barra superior de la consola web
3. Reducir el número de filtros activos si supera el 80%

### Actualizar a la última versión

```bash
# Detener servicios primero
~/camilladsp/scripts/stop_all.sh

# Actualizar engine y GUI backend
bash install_camilladsp.sh --update
```

---

## Referencias

- [CamillaDSP — Repositorio oficial](https://github.com/HEnquist/camilladsp)
- [CamillaGUI Backend](https://github.com/HEnquist/camillagui-backend)
- [Documentación de CamillaDSP](https://henquist.github.io/camilladsp/)

---

## Licencia

MIT License
