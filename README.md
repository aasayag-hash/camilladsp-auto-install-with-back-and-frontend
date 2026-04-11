# CamillaDSP EQ & Compressor GUI

Instalador automático para **CamillaDSP** con interfaz web para ecualización y compresión dinámica.

## Descripción

Esta herramienta proporciona una instalación automatizada y configuración completa del ecosistema CamillaDSP, que incluye:

- **CamillaDSP Engine**: Motor DSP de audio de alto rendimiento para procesamiento en tiempo real
- **CamillaGUI Backend**: Servidor Python con API WebSocket para la interfaz gráfica
- **Frontend Web**: Interfaz intuitiva para configurar ecualizadores, filtros y compresores

## Características

- Instalación completamente automatizada
- Actualización con un solo comando
- Scripts de control (iniciar/detener/ver estado)
- Soporte para Linux, macOS y Windows (WSL)
- Configuración por defecto lista para usar
- Servicios systemctl (Linux)
- Soporte para filtros FIR e IIR
- Compresión dinámica configurabile
- Gestión de coeficientes de filtros

## Requisitos

| Requisito | Descripción |
|-----------|-------------|
| Sistema operativo | Linux, macOS o Windows (WSL) |
| Herramientas | `curl` o `wget` |
| Compresión | `tar` / `unzip` |
| Permisos | Acceso sudo para servicios systemd |

## Instalación

### Instalación rápida

```bash
git clone https://github.com/aasayag-hash/camilladsp-EQ-comp-GUI.git
cd camilladsp-EQ-comp-GUI
bash install_camilladsp.sh
```

### Instalación en directorio personalizado

```bash
bash install_camilladsp.sh --dir=/ruta/personalizada
```

El instalador detectará automáticamente tu sistema operativo y arquitectura, descargará las versiones más recientes de CamillaDSP y CamillaGUI, y configurará todo automáticamente.

### Opciones del instalador

| Opción | Descripción |
|--------|-------------|
| `bash install_camilladsp.sh` | Instalación interactiva completa |
| `bash install_camilladsp.sh --update` | Actualizar a la última versión |
| `bash install_camilladsp.sh --check` | Verificar estado de la instalación |
| `bash install_camilladsp.sh --uninstall` | Desinstalar completamente |
| `bash install_camilladsp.sh --dir=/ruta` | Directorio de instalación personalizado |
| `bash install_camilladsp.sh --no-service` | Instalar sin iniciar servicios |
| `bash install_camilladsp.sh -h` | Mostrar ayuda |

## Después de instalar

El instalador inicia automáticamente los servicios al finalizar. Para acceder a la interfaz web:

```
http://localhost:5005
```

### Verificar estado

```bash
~/camilladsp/scripts/status.sh
```

### Detener servicios

```bash
~/camilladsp/scripts/stop_all.sh
```

### Iniciar servicios (si están detenidos)

```bash
~/camilladsp/scripts/start_all.sh
```

## Inicio automático (Linux con systemd)

Para iniciar automáticamente después de reiniciar:

```bash
systemctl --user enable camilladsp-engine.service
systemctl --user enable camilladsp-gui.service
systemctl --user start camilladsp-engine.service
systemctl --user start camilladsp-gui.service
```

Para verificar el estado de los servicios:

```bash
systemctl --user status camilladsp-engine.service
systemctl --user status camilladsp-gui.service
```

## Desinstalación

### Método 1: Usar el script del instalador

```bash
bash install_camilladsp.sh --uninstall
```

### Método 2: Eliminación manual

Si instalaste en el directorio por defecto:

```bash
# Detener servicios
~/camilladsp/scripts/stop_all.sh

# Eliminar directorio de instalación
rm -rf ~/camilladsp

# Si usaste servicios systemd
systemctl --user disable camilladsp-engine.service
systemctl --user disable camilladsp-gui.service
rm ~/.config/systemd/user/camilladsp-engine.service
rm ~/.config/systemd/user/camilladsp-gui.service
```

## Estructura de directorios

```
~/camilladsp/
├── engine/           # Binario camilladsp
├── gui/              # Backend Python de la GUI
├── config/           # Archivos de configuración YAML
│   └── camilladsp.yml
├── coeffs/           # Filtros FIR/IIR
├── logs/             # Logs de servicios
│   ├── engine.log
│   └── gui.log
├── pids/             # PIDs de procesos en ejecución
├── statefile.yml     # Estado actual de la configuración
└── scripts/          # Scripts de control
    ├── start_all.sh  # Iniciar todos los servicios
    ├── stop_all.sh   # Detener todos los servicios
    └── status.sh     # Ver estado de servicios
```

## Actualización

Para actualizar a la última versión disponible:

```bash
bash install_camilladsp.sh --update
```

Esto descargará e instalará las versiones más recientes de:
- CamillaDSP Engine
- CamillaGUI Backend

## Troubleshooting

### La interfaz web no carga

1. Verifica que el servicio GUI esté ejecutándose:
   ```bash
   ~/camilladsp/scripts/status.sh
   ```

2. Revisa los logs de la GUI:
   ```bash
   cat ~/camilladsp/logs/gui.log
   ```

3. Verifica que el puerto 5005 no esté en uso:
   ```bash
   netstat -tlnp | grep 5005
   ```

### No hay sonido

1. Verifica que el engine esté ejecutándose:
   ```bash
   ~/camilladsp/scripts/status.sh
   ```

2. Revisa los logs del engine:
   ```bash
   cat ~/camilladsp/logs/engine.log
   ```

3. Verifica la configuración de dispositivos en `~/camilladsp/config/camilladsp.yml`

4. Asegúrate de que los dispositivos de audio estén disponibles:
   ```bash
   aplay -l  # Linux
   ```

### Error de conexión con el engine

1. Verifica que el engine esté escuchando en el puerto 1234:
   ```bash
   netstat -tlnp | grep 1234
   ```

2. Revisa la configuración en `~/camilladsp/gui/config/camillagui.yml`

3. Reinicia los servicios:
   ```bash
   ~/camilladsp/scripts/stop_all.sh
   ~/camilladsp/scripts/start_all.sh
   ```

### La instalación falla por permisos

1. Asegúrate de tener permisos de escritura en el directorio de instalación
2. En Linux/macOS, verifica que el directorio HOME tenga permisos correctos

### Error de descarga

1. Verifica tu conexión a internet
2. Asegúrate de que curl o wget estén instalados
3. Prueba manualmente descargar un archivo de GitHub para verificar conectividad

### Problemas con ALSA (Linux)

1. Verifica que pulseaudio o pipewire no estén interceptando el dispositivo
2. Usa el nombre de dispositivo correcto en la configuración
3. Lista los dispositivos disponibles:
   ```bash
   aplay -l
   arecord -l
   ```

### Actualización no funciona

1. Detén los servicios antes de actualizar:
   ```bash
   ~/camilladsp/scripts/stop_all.sh
   ```
2. Luego ejecuta la actualización:
   ```bash
   bash install_camilladsp.sh --update
   ```

### El servicio no inicia automáticamente después de reiniciar

1. Verifica que systemd esté habilitado:
   ```bash
   systemctl --user list-unit-files | grep camilladsp
   ```

2. Habilita el servicio:
   ```bash
   systemctl --user enable camilladsp-engine.service
   systemctl --user enable camilladsp-gui.service
   ```

3. Verifica los logs de systemd:
   ```bash
   journalctl --user -u camilladsp-engine.service
   ```

### Alto consumo de CPU

1. Reduce el tamaño del buffer en la configuración (`chunksize`)
2. Aumenta el `adjust_period` si está definido
3. Revisa los filtros activos en la configuración

## Referencias

- [CamillaDSP - Repositorio oficial](https://github.com/HEnquist/camilladsp)
- [CamillaGUI Backend](https://github.com/HEnquist/camillagui-backend)
- [Documentación oficial de CamillaDSP](https://henquist.github.io/camilladsp/)

## Licencia

MIT License - Ver repositorio principal para más detalles.