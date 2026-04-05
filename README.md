
# CamillaDSP Pro Master Console 🎛️

Una interfaz gráfica de usuario (GUI) avanzada y profesional construida con Python y PySide6 para controlar de forma remota **CamillaDSP**. Esta aplicación está diseñada para ingenieros de audio, audiófilos y entusiastas que buscan un control visual, rápido y preciso sobre su enrutamiento de audio, ecualización paramétrica y control dinámico.

## 🚀 Fortalezas y Características Principales

* **Control en Tiempo Real:** Visualiza vúmetros (VU meters) con respuestas instantáneas y controla las ganancias de tu hardware sin microcortes de audio.
* **Ecualizador Gráfico Interactivo:** Un motor matemático exacto dibuja la curva real de los filtros Biquad. Puedes crear, mover y ajustar el factor Q de tus filtros simplemente usando el ratón.
* **Auto-Compresión Dinámica:** Incluye una función inteligente que "escucha" un canal durante 5 segundos, analiza su rango dinámico y calibra automáticamente los tiempos de Ataque y Liberación (Attack/Release) del compresor.
* **Persistencia Inteligente:** La aplicación recuerda la última IP y Puerto utilizados, acelerando el flujo de trabajo en cada sesión.
* **Bilingüe:** Soporte nativo para alternar la interfaz entre Inglés y Español con un solo clic.
* **Interfaz Profesional (Dark Mode):** Diseñada para largas sesiones de estudio, con un esquema de colores oscuros, barras de desplazamiento dinámicas y elementos auto-ajustables (Responsive).

## 📋 Requisitos Previos

Para ejecutar esta aplicación, necesitas tener instalado Python 3.8 o superior, además de las siguientes librerías:

bash
pip install PySide6 camilladsp
(Nota: Asegúrate de tener CamillaDSP ejecutándose en tu servidor local o remoto, y que el puerto WebSocket esté habilitado en su configuración).


⚙️ Instalación y Ejecución
Clona o descarga este repositorio en tu máquina local.

Abre una terminal en la carpeta del proyecto.

Ejecuta el script principal:

Bash
python camilladsp_comp.py

📖 Guía de Uso
1. Conexión y Modo de Trabajo
Al iniciar, la aplicación te pedirá la IP y el Puerto de tu servidor CamillaDSP.

Modos de Trabajo: Puedes elegir modificar la EQ general ("Default"), aplicar filtros a pares estéreo de entrada ("Input Mode") o aplicar ecualización y dinámica a salidas específicas ("Output Mode").

2. Solapa: Vúmetros y Dinámica
Control total sobre la mezcla y niveles de salida:

Faders: Mantén presionado el clic izquierdo para mover el fader de volumen. El clic derecho resetea la ganancia a 0.0 dB.

Polaridad / Fase: Botón +/- para invertir la polaridad del canal al instante.

Mute: Haz clic en el nombre del canal de salida para mutearlo (se pondrá rojo).

Compresores Rápidos: Haz doble clic sobre un vúmetro de salida para inyectar automáticamente un compresor/limitador. En la tabla inferior podrás ajustar minuciosamente el Threshold, Ratio, Makeup Gain, etc. (¡Prueba el botón AUTO para calibración inteligente!).

3. Solapa: Filtros y EQ
Una pantalla dedicada a la respuesta de frecuencias:

Crear Filtro: Doble clic en cualquier parte vacía del fondo negro.

Mover Filtro: Mantén presionado el clic izquierdo sobre un punto (nodo) para ajustar su Frecuencia (Hz) y Ganancia (dB). Un cuadro de información inteligente seguirá tu cursor.

Ancho de Banda (Factor Q): Usa la rueda del ratón sobre el nodo de un filtro para hacerlo más estrecho o más ancho.

Borrar Filtro: Clic derecho sobre el nodo del filtro.

Todas las modificaciones se reflejan en la tabla inferior, donde puedes cambiar el tipo de filtro (Peaking, Highshelf, Lowpass, etc.) y escribir valores exactos si lo prefieres.
