# CamillaDSP Master Console

**CamillaDSP Master Console** es una interfaz gráfica de usuario (GUI) avanzada y profesional construida con Python y PySide6 (Qt) para controlar y auditar el motor de procesamiento de audio **CamillaDSP** (compatible con v4.0.1+).

## Características Principales

- **Control de Vúmetros y Dinámica:** Visualiza los niveles RMS de entrada y salida en tiempo real.
- **Compresores Dinámicos Inteligentes:** - Creación rápida haciendo doble clic en el vúmetro de salida.
  - Función **AUTO** que muestrea el audio durante 5 segundos para calcular parámetros de *Attack*, *Release* basados en detección de transientes (derivadas y percentiles P50/P95).
  - Cálculo automático de *Makeup Gain* ponderado por energía perceptual.
- **Mezclador Integrado:** Faders de control de ganancia de salida calibrados precisamente entre **+10 dB y -50 dB**. Controles de inversión de polaridad de un solo toque y ajuste de Delay (ms) por canal.
- **Ecualizador Paramétrico (PEQ) Visual:** Dibuja, arrastra y ajusta filtros en una pantalla vectorial suave. Soporta Peaking, Highpass, Lowpass, Highshelf, y Lowshelf.
- **Crossovers Vectoriales:** Ajusta cortes de frecuencia visualmente, soportando topologías como Butterworth y Linkwitz-Riley (hasta 48vo orden).
- **Log de Comandos Crudos:** Ventana de consola interactiva que detalla cada comando JSON que la aplicación envía y recibe del servidor hardware.

## Requisitos Previos

- **Python 3.9** o superior.
- Librerías requeridas: `PySide6`, `camilladsp` (librería de cliente oficial de CamillaDSP) y dependencias estándar (`json`, `math`, `time`, `re`).

Para instalar las dependencias:
```bash
pip install PySide6 camilladsp
