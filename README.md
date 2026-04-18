# CamillaDSP — Instalador Automático con Consola Web

Instalación completa de **CamillaDSP** en dispositivos Linux embebidos (TV-Box, Raspberry Pi, ARM boards). Incluye el engine DSP, una consola web propia accesible desde cualquier navegador, y soporte opcional para audio en red **Dante / AES67** via el plugin `inferno`.

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
  --uninstall      Elimina la instalación completa de CamillaDSP
  --no-service     Instala archivos pero no inicia servicios
  --dir=<ruta>     Directorio de instalación (default: ~/camilladsp)
  -h, --help       Muestra esta ayuda
```

---

## Servicios instalados

| Servicio | Puerto | Descripción |
|---|---|---|
| `camilladsp` | WS 1234 | Engine DSP (CamillaDSP) |
| `camilladsp-web` | HTTP 5000 | Consola web |
| `statime-inferno` | — | Daemon PTP para Dante/AES67 (solo con opción Dante) |

Todos los servicios se registran en systemd y arrancan automáticamente al encender el dispositivo.

```bash
# Ver estado
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
│   └── presets/          # Presets guardados
├── coeffs/               # Coeficientes FIR
├── scripts/
│   └── status.sh         # Script de estado rápido
└── start_camilladsp.sh   # Script de arranque del engine
```

---

## Funcionalidades de la consola web

### Panel principal
- **Estado del engine**: Running / Inactive / Error en tiempo real
- **VU Meters**: niveles RMS con peak hold por canal
- **Faders**: control de ganancia por canal con inversión de polaridad
- **Volumen global** y control de mute

### Tabs de configuración
- **EQ Gráfico**: ecualizador de 31 bandas con arrastre de curva
- **EQ Paramétrico**: gráfico interactivo 20 Hz–20 kHz, drag & drop de filtros, importación REW/APO
- **Crossovers**: filtros Butterworth y Linkwitz-Riley hasta 48 dB/oct
- **Mixer**: matriz de ruteo de canales con nombres personalizados y compresores por canal
- **Dispositivos**: selección de dispositivos ALSA, probe automático de parámetros de hardware

### Presets
- Guardar/cargar/eliminar configuraciones completas del pipeline DSP
- Presets incluidos (con Dante): `dante_to_maya44`, `maya44_to_dante`, `maya44usb`

### Reset / Reconfiguración
- Selector de dispositivos ALSA captura/reproducción (formato `hw:X,Y`)
- Probe automático: canales, sample rate y formato del hardware seleccionado
- Crea config completa con Mixer y reinicia el engine automáticamente

---

## Soporte Dante / AES67

Al instalar, el script pregunta si querés agregar soporte Dante. Si respondés que sí, instala:

- Plugin ALSA `inferno` (dispositivos `inferno_rx` / `inferno_tx`)
- Daemon PTP `statime-inferno` para sincronización de reloj
- Configuración `.asoundrc` con los parámetros correctos
- Script de arranque inteligente que:
  - Si el preset activo usa Dante pero no hay flujo, arranca con dispositivo `null` (siempre en estado Running)
  - Cuando Dante está disponible, recargás el preset desde la UI
  - Auto-incrementa `PROCESS_ID` en cada arranque para evitar conflictos de puerto

### Configurar Dante desde la web

1. Ir a tab **Mixer** → botón **Dante RX**
2. Elegir la interfaz de red (se detectan automáticamente)
3. Ingresar hostname o IP del transmisor Dante (se resuelve automáticamente)
4. Configurar los canales RX y guardar
5. El servicio reinicia statime y camilladsp automáticamente

---

## Solución de problemas

**Engine queda en Inactive o Error**
```bash
journalctl -u camilladsp -n 50
```
Causas comunes: dispositivo ALSA ocupado, preset Dante sin flujo, PROCESS_ID duplicado.

**No se ven dispositivos de audio en la web**
Verificar que el engine esté Running: el listado de dispositivos requiere que ALSA responda.

**Dante no sincroniza (no clock available)**
Verificar que `statime-inferno` esté corriendo en la interfaz correcta:
```bash
journalctl -u statime-inferno -n 20
cat /etc/statime-inferno.toml   # verificar campo interface
```
Desde la web, ir a Dante RX y seleccionar la interfaz con IP activa.

**Audio con glitches o dropouts**
Aumentar `chunksize` en el preset activo (512 → 1024 → 2048) y recargar.

---

## Plataformas probadas

- Armbian (Debian Trixie) en TV-Box aarch64
- Ubuntu 22.04 en Raspberry Pi 4
- Debian 12 en x86_64

---

## Créditos

- [CamillaDSP](https://github.com/HEnquist/camilladsp) por Henrik Enquist
- [inferno](https://github.com/hifiberry/inferno) plugin ALSA para Dante/AES67
- [statime](https://github.com/pendulum-project/statime) daemon PTP
