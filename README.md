# CamillaDSP Web Console & Auto-Installer

Una solución completa, robusta y desatendida para automatizar el despliegue del ecosistema **CamillaDSP** en cualquier dispositivo (TV-Box, Raspberry Pi, servidor Linux). Incluye la instalación del motor DSP, el backend de la GUI oficial y una **interfaz web front-end personalizada** de diseño premium accesible desde cualquier navegador.

---

## 🚀 Características Principales

* **Instalación "Zero-Headache"**: El instalador ahora resuelve automáticamente sus propias dependencias (`curl`, `wget`, `python3-pip`, `jq`). Simplemente ejecuta el script en un entorno basado en Debian/Armbian/Ubuntu y él se encargará del resto.
* **Limpieza Profunda Inteligente**: Si detecta una instalación corrupta o previa de CamillaDSP, te ofrecerá deshabilitar servicios pasados, liberar los puertos obstruidos y eliminar archivos viejos antes de realizar un despliegue impecable.
* **Inmune a Errores de Formato**: Configurado nativamente con `.gitattributes` para evitar incompatibilidades de saltos de línea (CRLF/LF) al clonar desde entornos Windows a Linux.
* **Arranque Automático**: Configura el sistema operativo para levantar el ecosistema automáticamente tras los reinicios mediante `systemd`, `rc.local`, o `cron`.

---

## 🎛️ Interfaz Web Personalizada — Capacidades

La consola web (puerto `5000`) cuenta con panel táctil y diseño inmersivo:

* **Vúmetros Universales**: Mediciones RMS en tiempo real, histórico de picos e indicadores visuales de atenuación para el compresor, junto con Faders independientes y fase invertida por canal.
* **Ecualizador Gráfico de 31 Bandas**: Rango visual continuo de ±9 dB con fase lineal, función de enlazado global y control por doble-clic para reiniciar frecuencias puntuales.
* **Ecualizador Paramétrico (PEQ)**: Gráfico de rango completo (20 Hz - 20 kHz) interactivo (drag-and-drop). Ajuste de ganancia, frecuencia y factor de banda "Q" con soporte táctil. Importación directa de filtros nativos, REW Generic, o Equalizer APO.
* **Gestor de Crossovers**: Enrutamiento de alta fidelidad empleando filtros progresivos de Butterworth y Linkwitz-Riley (hasta 48 dB/octava).
* **Mixer en Tiempo Real**: Ruteo entre tarjetas de sonido físicas ALSA, selector dinámico de tamaño de búfer (Chunksize), y soporte completo para renombra miento custom de los canales sobre la marcha.

---

## 🛠️ Instalación Rápida

Asegúrate de contar con internet en tu TV Box o Raspberry Pi y simplemente ejecuta:

```bash
git clone https://github.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend.git
cd camilladsp-auto-install-with-back-and-frontend
bash install_camilladsp.sh
```

### Opciones de Instalación
```bash
bash install_camilladsp.sh [opciones]

  (sin opciones)    Instalación completa interactiva
  --update          Actualizar engine y GUI a la última versión
  --check           Verificar el estado general de los procesos
  --uninstall       Desinstalar todo el entorno Camilla
  --no-service      Instalar archivos pero no iniciar los servicios
```

---

## 🌐 Servicios y Puertos Ocupados

Por defecto, los servidores escucharán en las IPs correspondientes a tu red local (LAN) bajo los puertos:

| Componente | Protocolo | Puerto | Descripción |
|---|---|---|---|
| **Consola Web Custom** | HTTP | `5000` | Interfaz Front-end amigable (Este proyecto) |
| **CamillaGUI Oficial** | HTTP | `5005` | Backend avanzado/GUI de HEnquist |
| **CamillaDSP Engine** | WebSocket | `1234` | Motor de alto rendimiento y API de control |

---

## 📂 Directorio y Configuración (Backend)

La ejecución inicial asienta toda la carpeta de trabajo bajo la ubicación nativa del usuario principal (ejemplo `$HOME/camilladsp` o `/root/camilladsp` en TV-box).

```text
~/camilladsp/
├── engine/             # Binario del software
├── gui/                # Core de configuración Backend
├── web/                # Interfaz de usuario (Consola Web)
├── config/             # Tuberías, filtros y yaml del pipeline
├── coeffs/             # Archivos FIR y coeficientes
├── scripts/            # Comandos: start_all.sh | stop_all.sh
└── logs/               # Monitoreo del motor y el front-end
```

---

## 🔧 Resolución de Problemas

1. **La Interfaz Web no muestra ningún dispositivo de audio ALSA:**
   El demonio central debe estar operando. Ejecuta `~/camilladsp/scripts/status.sh` y asegúrate de que tanto el engine (1234) como la GUI (5005) estén "ON". Verifica tus logs en `~/camilladsp/logs/`.
2. **Audio saturado o caídas repentinas (Dropouts):**
   Accede a la pestaña `MIXER`, incrementa el valor de Chunksize en cascada (e.g., 512 → 1024 → 2048) y luego haz clic en `⟳ Motor`.
3. **El instalador se queda bloqueado o "Congelado":**
   Presiona `CTRL+C`, y vuelva a lanzar `bash install_camilladsp.sh`. La consola detectará vestigios de la instalación corrupta y te preguntará si quieres realizar un saneamiento ("Limpieza profunda"). Presiona la tecla `S` para aprobarlo y continuar.

---

> Desplegado, probado y configurado bajo entornos Linux embebidos, TV-Boxes modificados (Armbian Debian Trixie/Ubuntu) y equipos de capa general.
