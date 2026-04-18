# CamillaDSP — Instalador automático con consola web

Instalación completa de **CamillaDSP** en dispositivos Linux embebidos (TV-Box, Raspberry Pi, ARM boards). Incluye el engine DSP, una consola web accesible desde cualquier navegador de la red local, y soporte opcional para audio en red **Dante / AES67** via el plugin `inferno`.

---

## Instalación rápida

```bash
git clone https://github.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend.git
cd camilladsp-auto-install-with-back-and-frontend
bash install_camilladsp.sh
```

Al finalizar, la consola web queda disponible en `http://<ip-dispositivo>:5000`

---

## Opciones del instalador

```
bash install_camilladsp.sh [opciones]

  (sin opciones)   Instalación completa interactiva
  --update         Actualiza el engine y frontend a la última versión
  --check          Muestra el estado de los servicios instalados
  --uninstall      Elimina la instalación completa
  --no-service     Instala archivos pero no inicia servicios
  --dir=<ruta>     Directorio de instalación (default: ~/camilladsp)
  -h, --help       Muestra esta ayuda
```

---

## Servicios instalados

| Servicio | Puerto | Descripción |
|---|---|---|
| `camilladsp` | WS 1234 | Engine DSP |
| `camilladsp-web` | HTTP 5000 | Consola web |
| `statime-inferno` | — | Daemon PTP para Dante/AES67 (solo con opción Dante) |

Todos los servicios arrancan automáticamente con el dispositivo.

```bash
systemctl status camilladsp
systemctl status camilladsp-web
journalctl -u camilladsp -f        # logs en tiempo real
```

---

## Estructura de directorios

```
~/camilladsp/
├── engine/               # Binario CamillaDSP
├── web/
│   ├── server.py         # Backend Flask (API + proxy WebSocket)
│   └── index.html        # Frontend (consola web)
├── config/
│   ├── camilladsp.yml    # Config activa
│   ├── presets/          # Presets guardados
│   └── dante_subscriptions.toml  # Referencia de suscripciones Dante
├── coeffs/               # Coeficientes FIR
└── start_camilladsp.sh   # Script de arranque del engine
```

---

## Consola web — funcionalidades

### Panel principal
- Estado del engine en tiempo real (Running / Idle / Error)
- VU Meters por canal con peak hold
- Faders de ganancia, mute e inversión de polaridad por canal
- Volumen global y delay por canal

### Solapas

| Solapa | Descripción |
|---|---|
| **VUmetros** | Monitoreo de niveles, faders, compresores por canal |
| **Graphic EQ** | Ecualizador gráfico de 31 bandas, fase lineal |
| **Parametric EQ** | EQ paramétrico con gráfico interactivo, importación REW/APO |
| **Crossovers** | Filtros Butterworth y Linkwitz-Riley hasta 48 dB/oct |
| **Mixer** | Matriz de ruteo, presets, selección de dispositivos, Dante RX |
| **Opciones** | Parámetros del engine (buffers, resampling, silencio, etc.) |

### Presets
- Guardar / cargar / eliminar configuraciones completas del pipeline DSP
- Los presets se almacenan en el dispositivo en `config/presets/`

### Reset / Reconfiguración
- Selección de dispositivos ALSA captura y reproducción
- Probe automático de canales, sample rate y formato del hardware
- Genera config nueva con Mixer y reinicia el engine automáticamente

---

## Soporte Dante / AES67

Al instalar, el script pregunta si querés agregar soporte Dante. Si respondés que sí, instala:

- Plugin ALSA `inferno` — dispositivos `inferno_rx` e `inferno_tx`
- Daemon PTP `statime-inferno` para sincronización de reloj
- `.asoundrc` configurado con nombre de interfaz de red (no IP fija)
- Script de arranque que auto-incrementa `PROCESS_ID` y arranca `inferno_rx` siempre

### Cómo funciona

El dispositivo aparece en la red como **tvbox-dante** via mDNS. La asignación de canales Dante → CamillaDSP se hace desde **Dante Controller** (software de Audinate), que corre en cualquier PC de la red. No se requiere configuración manual de hostnames ni suscripciones pull-mode.

### Configurar la interfaz de red Dante desde la web

1. Ir a solapa **Mixer** → botón **♫ Dante RX**
2. Elegir la interfaz de red (se detectan automáticamente con sus IPs)
3. Guardar — el servicio reinicia `statime-inferno` y CamillaDSP automáticamente
4. Abrir **Dante Controller** y asignar los canales TX → RX desde ahí

---

## Solución de problemas

**Engine en Inactive o Error**
```bash
journalctl -u camilladsp -n 50
```
Causas comunes: dispositivo ALSA ocupado, hardware no reconocido.

**Sin audio Dante**
- Verificar que `statime-inferno` esté corriendo: `systemctl status statime-inferno`
- Abrir Dante Controller y asignar los canales TX → RX desde ahí
- En la web, ir a Mixer → Dante RX y verificar que la interfaz seleccionada tenga IP activa

**No se ven dispositivos de audio en la web**
El listado requiere que el engine esté Running. Verificar con `journalctl -u camilladsp -n 20`.

**Audio con glitches o dropouts**
Aumentar `chunksize` en la solapa Opciones (512 → 1024 → 2048).

**Dante no sincroniza (no clock available)**
```bash
journalctl -u statime-inferno -n 20
cat /etc/statime-inferno.toml   # verificar campo interface
```
Desde la web, ir a Mixer → Dante RX y seleccionar la interfaz con IP activa.

---

## Plataformas probadas

- Armbian (Debian Trixie) en TV-Box aarch64
- Ubuntu 22.04 en Raspberry Pi 4
- Debian 12 en x86_64

---

## Créditos

- [CamillaDSP](https://github.com/HEnquist/camilladsp) por Henrik Enquist
- [inferno](https://github.com/hifiberry/inferno) — plugin ALSA para Dante/AES67
- [statime](https://github.com/pendulum-project/statime) — daemon PTP
