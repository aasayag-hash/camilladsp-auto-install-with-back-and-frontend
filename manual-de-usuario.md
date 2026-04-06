### 3. `manual-de-usuario.md`

```markdown
# Manual de Usuario - CamillaDSP Master Console

Este documento detalla el funcionamiento de las diversas herramientas gráficas incluidas en la consola de control maestro de CamillaDSP.

## Interfaz Principal y Navegación

Tras conectar la aplicación con éxito al hardware de audio (introduciendo IP y Puerto), la interfaz se divide en **3 pestañas principales**:
1. Vúmetros y Dinámica (Vumeters & Dynamics)
2. Filtros y EQ (EQ & Filters)
3. Crossovers

En la esquina superior derecha encontrarás un **selector rápido de canales (IN/OUT)**. Activa o desactiva canales en estos botones para que las gráficas y filtros creados solo se inyecten o visualicen en la ruta de audio que desees afectar.

---

## 1. Pestaña Vúmetros y Dinámica (Mixer y Compresores)

Esta pestaña se encarga de la visualización en tiempo real y la nivelación general del sonido. 

### Faders de Volumen y Fase
- **Volumen Principal:** Arrastra el punto de control azul verticalmente. El fader está escalado de forma profesional con un tope superior de **+10 dB** y un corte inferior de **-50 dB**.
- **Reset Rápido:** Haz *Clic Derecho* en la franja del fader para devolverlo instantáneamente a **0.0 dB**.
- **Polaridad (+/-):** El botón invierte 180 grados la fase acústica del canal. 
- **Delay:** Ingresa el valor en milisegundos (`ms`). Para desactivarlo, pon el valor a `0` o haz *Clic Derecho* sobre el cuadro numérico.

### Compresores y Limitadores
- **Creación:** Haz un *Doble Clic Izquierdo* sobre el nivel del Vúmetro de salida al que quieres limitar. La posición vertical en la que hagas clic determinará el *Threshold* (umbral) de inicio. Inmediatamente aparecerá registrado en la tabla inferior y una línea roja de limitación cruzará el Vúmetro.
- **Borrado:** Haz *Clic Derecho* sobre el Vúmetro, o haz clic en la **X** de la fila en la tabla de compresores. **Esto elimina el bloque completamente de la memoria.**
- **Bypass del Canal (Mute):** Un *Clic Izquierdo* sobre el Nombre del canal debajo del Vúmetro lo silenciará (se tornará Rojo). Haz clic nuevamente para reactivarlo (Verde).

### El Botón AUTO (Magia Dinámica)
Si presionas el botón **AUTO** en la tabla de compresores, el sistema empezará a "escuchar" el canal durante 5 segundos:
* **Attack & Release:** Medirá los *transientes* (velocidad en que aparecen los picos vs la caída) usando percentiles de densidad P50 y P95. Asignará tiempos ultra-rápidos si detecta golpes bruscos (como baterías) y tiempos suaves/lentos para sonidos continuos.
* **Makeup Gain:** Utiliza un cálculo "perceptual ponderado por energía". Evita subir ruidos silenciosos y calcula con precisión cuántos dB "útiles" fueron aplastados para luego compensarlos matemáticamente de forma transparente.

---

## 2. Pestaña Filtros y EQ (Ecualizador Vectorial)

- **Crear un Filtro:** Asegúrate de tener al menos un canal seleccionado arriba (IN o OUT). Luego, haz **Doble Clic** en cualquier parte vacía de la gráfica negra. El filtro (tipo *Peaking* por defecto) se creará en las coordenadas de frecuencia y ganancia correspondientes.
- **Manipular Filtros:** Haz **Clic y arrastra** el punto creado para moverlo sobre el espectro de frecuencias.
- **Ancho de banda (Factor Q):** Selecciona un filtro y usa la **Rueda del Ratón (Scroll)** hacia arriba o abajo para hacer que la curva del ecualizador sea más estrecha o más amplia.
- **Borrar Filtros:** Haz un **Clic Derecho** sobre el punto de ecualización que desees eliminar.

## 3. Pestaña Crossovers

Esta pestaña se enfoca en dividir frecuencias para enviar bajos a subwoofers y altos a tweeters. Funciona de forma similar al ecualizador.
- **Creación:** Haz doble clic sobre el lienzo (asegúrate de tener un canal OUT seleccionado). 
- **Control:** Arrastra el punto para deslizar el corte de frecuencia de cruce.
- **Curva / Orden:** Selecciona el punto y usa la **Rueda del Ratón** para aumentar o disminuir la dureza (orden) del corte (ej. subir hasta 4to Orden / 24dB por octava). En la tabla inferior puedes alternar entre tipologías como Butterworth o Linkwitz-Riley.
- **Borrar:** Clic derecho sobre el punto del crossover.
