# CamillaDSP EQ & Compressor GUI

Instalador automático para **CamillaDSP** con interfaz web para ecualización y compresión dinámica.

## Componentes

| Componente | Descripción |
|------------|-------------|
| **CamillaDSP Engine** | Motor DSP de audio de alto rendimiento |
| **CamillaGUI Backend** | Servidor Python + API WebSocket |
| **Frontend** | Interfaz web para configuración |

## Requisitos

- Linux, macOS o Windows (WSL)
- `curl` o `wget`
- Python 3.8+ (para la GUI)
- `tar` / `unzip`

## Instalación rápida

```bash
git clone https://github.com/tu-usuario/camilladsp-EQ-comp-GUI.git
cd camilladsp-EQ-comp-GUI
bash install_camilladsp.sh
```

## Uso del instalador

| Comando | Descripción |
|---------|-------------|
| `bash install_camilladsp.sh` | Instalación interactiva |
| `bash install_camilladsp.sh --update` | Actualizar a última versión |
| `bash install_camilladsp.sh --check` | Verificar estado |
| `bash install_camilladsp.sh --uninstall` | Desinstalar todo |
| `bash install_camilladsp.sh --dir /ruta` | Directorio personalizado |

## Después de instalar

1. **Iniciar servicios:**
   ```bash
   ~/camilladsp/scripts/start_all.sh
   ```

2. **Abrir interfaz web:**
   ```
   http://localhost:5005
   ```

3. **Detener servicios:**
   ```bash
   ~/camilladsp/scripts/stop_all.sh
   ```

## Estructura de directorios

```
~/camilladsp/
├── engine/           # Binario camilladsp
├── gui/              # Backend Python
├── config/           # Configuraciones
├── coeffs/           # Filtros FIR/IIR
├── logs/             # Logs de servicios
├── pids/             # PIDs de procesos
└── scripts/          # Scripts de control
    ├── start_all.sh
    ├── stop_all.sh
    └── status.sh
```

## Inicio automático (Linux)

```bash
systemctl --user enable camilladsp-engine.service
systemctl --user enable camilladsp-gui.service
systemctl --user start camilladsp-engine.service
systemctl --user start camilladsp-gui.service
```

## Referencias

- [CamillaDSP](https://github.com/HEnquist/camilladsp)
- [CamillaGUI Backend](https://github.com/HEnquist/camillagui-backend)
- [Documentación oficial](https://henquist.github.io/camilladsp/)
