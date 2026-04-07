### 3. `manual-de-usuario.md`

## === BARRA SUPERIOR Y CANALES ===

Botones IN / OUT: Seleccionan qué canales visualizar. Además, dictan sobre qué canales se aplicarán los nuevos filtros que crees o sobre cuáles actuará el botón de Bypass.

Botón ALL: Selecciona o deselecciona todos los canales simultáneamente de forma rápida.

CONSOLE (Consola / Log): Abre una ventana independiente que muestra en tiempo real todos los comandos y comunicaciones internas entre el software y el hardware de CamillaDSP.

=== GRÁFICOS DE EQ Y CROSSOVERS ===

Doble Clic Izquierdo (en el fondo vacío): CREA un nuevo filtro (Peaking en EQ, o Linkwitz-Riley en Crossover) asignado automáticamente a los canales que tengas seleccionados en la botonera superior.

Clic Izquierdo Sostenido (sobre el punto): Arrastra el punto libremente para ajustar la Frecuencia (Hz) y la Ganancia (dB).

Rueda del Mouse (sobre el punto): Ajusta el Ancho de Banda (Factor Q) en los ecualizadores, o cambia el Orden (las pendientes) en los Crossovers.

Clic Derecho (sobre el punto): BORRA definitivamente el ecualizador o crossover seleccionado de la memoria.

=== MATRIZ MIXER (RUTEO) ===

Doble Clic Izquierdo (sobre los Nombres): Permite renombrar globalmente cualquier entrada (Top) o salida (Izquierda).

Clic Izquierdo (en celda vacía '+'): CREA una conexión de ruteo enviando la señal de esa entrada hacia esa salida.

Clic Derecho (en celda verde): ELIMINA / Desconecta esa ruta de la matriz de audio en tiempo real.

=== VÚMETROS, FADERS Y COMPRESORES ===

Clic Derecho en el Nombre del Canal: Renombra el canal (IN o OUT).

Clic Izquierdo en el Nombre del Canal (Salidas): Mutea (se pone Rojo) o Desmutea (se pone Verde) el canal de salida completo.

Clic Izquierdo Sostenido (Fader): Ajusta el volumen maestro de esa salida (Gain) desde -50 dB hasta +10 dB sin saltos.

Clic Derecho (Fader o cuadro de Delay): Resetea instantáneamente el valor a 0.0.

Botón +/-: Invierte la polaridad (fase) de la salida correspondiente.

Doble Clic Izquierdo (Barra del Vúmetro): CREA un compresor/limitador dinámico en ese canal, ajustando el Threshold (Umbral) exactamente en los dB donde hiciste el clic.

Clic Derecho (Barra del Vúmetro): BORRA de forma definitiva y quirúrgica el compresor de ese canal.

Botón AUTO (Tabla de Compresores): Escucha y muestrea el audio real del canal durante 5 segundos, y configura automáticamente el Attack, Release y Makeup Gain en base al factor de cresta detectado (Loudness Matching).

Botón X (Tablas): Borra permanentemente el elemento de esa fila (Filtro, Crossover o Compresor).

=== BOTONES DE GESTIÓN ===

BYPASS EQ (SEL.): Apaga/Enciende temporalmente sólo los filtros de ecualización de los canales seleccionados. Se vuelve ROJO brillante al activarse. Crossovers, delays y volúmenes siguen intactos.

Importar / Exportar Filtros: Carga o guarda únicamente tus ecualizaciones (Compatible con los .txt exportados desde Room EQ Wizard - REW).

Importar / Exportar Config: Hace un backup o restaura una copia COMPLETA del estado del equipo (Matriz, Volúmenes, Nombres, EQ, Crossovers, Compresores y Delays) en archivos .yml o .json.

Config Default: Formatea todo el hardware y lo devuelve a un estado inicial plano y limpio (reset de fábrica).
