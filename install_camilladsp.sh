#!/bin/bash
# ==============================================================
#  CamillaDSP — Instalador Automático
#  Engine  +  GUI Backend  +  Frontend
# ==============================================================

SCRIPT_VERSION="1.2.0"

# Repositorios GitHub
CAMILLADSP_REPO="HEnquist/camilladsp"
CAMILLAGUI_REPO="HEnquist/camillagui-backend"
WEB_REPO_RAW="https://raw.githubusercontent.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend/main/web"

# Puertos por defecto
ENGINE_WS_PORT=1234
GUI_HTTP_PORT=5005
WEB_GUI_PORT=5000

# Argumentos
ARG_UPDATE=0
ARG_UNINSTALL=0
ARG_CHECK=0
ARG_NO_SERVICE=0
ARG_DIR=""

for arg in "$@"; do
  case "$arg" in
    --update)     ARG_UPDATE=1 ;;
    --uninstall)  ARG_UNINSTALL=1 ;;
    --check)      ARG_CHECK=1 ;;
    --no-service) ARG_NO_SERVICE=1 ;;
    --dir=*)      ARG_DIR="${arg#--dir=}" ;;
    -h|--help)
      echo ""
      echo "Uso: bash install_camilladsp.sh [opciones]"
      echo ""
      echo "Opciones:"
      echo "  (sin opciones)   Instalación completa interactiva"
      echo "  --update         Actualiza el engine y frontend a la última versión"
      echo "  --check          Muestra el estado de los servicios instalados"
      echo "  --uninstall      Elimina la instalación completa de CamillaDSP"
      echo "  --no-service     Instala archivos pero no inicia servicios"
      echo "  --dir=<ruta>     Directorio de instalación (default: ~/camilladsp)"
      echo ""
      echo "Servicios instalados:"
      echo "  camilladsp        Puerto WebSocket 1234 (engine DSP)"
      echo "  camilladsp-web    Puerto HTTP 5000 (consola web)"
      echo "  statime-inferno   Daemon PTP para sincronización Dante/AES67"
      echo ""
      echo "Acceso web: http://<ip-dispositivo>:5000"
      echo ""
      exit 0
      ;;
  esac
done

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()  { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
log_ok()    { echo -e "  ${GREEN}✔${RESET}  $*"; }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_error() { echo -e "  ${RED}✖${RESET}  $*"; }
log_step()  { echo -e "\n${CYAN}${BOLD}▶  $*${RESET}"; }

header() {
  echo -e ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗"
  echo -e "║         CamillaDSP  —  Instalador Automático             ║"
  echo -e "║         Engine DSP  +  Consola Web  +  Dante/AES67       ║"
  printf  "║                                         v%-19s║\n" "$SCRIPT_VERSION"
  echo -e "╚══════════════════════════════════════════════════════════╝${RESET}"
}

# Limpieza profunda de instalaciones previas
cleanup_previous_install() {
  local found_svcs
  found_svcs=$(systemctl list-unit-files --all 'camilla*' 2>/dev/null | grep 'camilla' | awk '{print $1}')

  if [ -n "$found_svcs" ]; then
    echo -e "${YELLOW}${BOLD}⚠ SE DETECTÓ UNA INSTALACIÓN PREVIA DE CAMILLADSP${RESET}"
    echo -e "Servicios encontrados:"
    echo "$found_svcs" | sed 's/^/  - /'
    echo ""
    echo -n " ¿Desea realizar una LIMPIEZA PROFUNDA antes de continuar? (Borrará directorios y servicios camilla*) [s/N]: "
    read -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Ss]$ ]]; then
      log_step "Iniciando limpieza profunda..."
      
      # Detener y deshabilitar servicios
      echo "$found_svcs" | while read -r svc; do
        log_info "Eliminando servicio: $svc"
        sudo systemctl stop "$svc" 2>/dev/null || true
        sudo systemctl disable "$svc" 2>/dev/null || true
        # Intentar modo usuario también
        systemctl --user stop "$svc" 2>/dev/null || true
        systemctl --user disable "$svc" 2>/dev/null || true
      done

      # Borrar archivos de unidad en el sistema
      log_info "Borrando archivos de unidad systemd..."
      sudo rm -f /etc/systemd/system/camilla* 2>/dev/null
      sudo rm -f /usr/lib/systemd/system/camilla* 2>/dev/null
      rm -f "$HOME/.config/systemd/user/camilla*" 2>/dev/null

      # Recargar systemd
      sudo systemctl daemon-reload 2>/dev/null || true
      sudo systemctl reset-failed 2>/dev/null || true
      systemctl --user daemon-reload 2>/dev/null || true

      # Borrar directorios en todo el sistema (excepto el actual)
      log_info "Buscando y borrando directorios camilla* en todo el sistema..."
      # Excluimos el directorio actual para no borrar el instalador mismo
      sudo find / -name "camilla*" -type d ! -path "$(pwd)*" -prune -exec rm -rf {} + 2>/dev/null
      
      log_ok "Limpieza completada. Continuando con la instalación limpia."
    else
      log_info "Continuando sin limpieza profunda."
    fi
  fi
}

# Detección de sistema
detect_system() {
  OS_NAME=""
  ARCH=""
  case "$(uname -s)" in
    Linux*)  OS_NAME="linux" ;;
    Darwin*) OS_NAME="darwin" ;;
    MINGW*|MSYS*|CYGWIN*) OS_NAME="windows" ;;
    *)       OS_NAME="unknown" ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    armv7*)        ARCH="armv7" ;;
    armv6*)        ARCH="armv6" ;;
    *)             ARCH="$(uname -m)" ;;
  esac
}

# Limitar tamaño del journal para evitar que llene la RAM en equipos embebidos
configure_journal_limits() {
  local cfg="/etc/systemd/journald.conf"
  if ! grep -q "^SystemMaxUse=50M" "$cfg" 2>/dev/null; then
    sed -i '/^SystemMaxUse/d; /^RuntimeMaxUse/d; /^SystemKeepFree/d' "$cfg" 2>/dev/null || true
    printf '\nSystemMaxUse=50M\nRuntimeMaxUse=20M\nSystemKeepFree=100M\n' | sudo tee -a "$cfg" > /dev/null
    sudo systemctl restart systemd-journald 2>/dev/null || true
    log_ok "Journal limitado a 50MB"
  fi
}

# Verificación y resolución de dependencias
check_system_dependencies() {
  log_step "Verificando dependencias del sistema..."
  local deps="curl wget jq"
  local missing=""

  if command -v apt-get &>/dev/null; then
    for dep in $deps; do
      if ! command -v $dep &>/dev/null; then
        missing="$missing $dep"
      fi
    done

    # Revisar python-pip específicamente
    if ! command -v pip &>/dev/null && ! command -v pip3 &>/dev/null; then
      missing="$missing python3-pip"
    fi

    if [ -n "$missing" ]; then
      log_info "Instalando dependencias faltantes: $missing"
      if [ "$(id -u)" = "0" ]; then
        apt-get update -qq && apt-get install -y -qq $missing
      elif command -v sudo &>/dev/null; then
        # Actualizamos apt cache
        sudo apt-get update -qq && sudo apt-get install -y -qq $missing
      else
        log_warn "Sudo no encontrado. No se pudieron instalar dependencias automáticamente."
      fi
    else
      log_ok "Dependencias de sistema completas."
    fi
  else
    log_info "Gestor de paquetes apt no detectado (asumiendo entorno pre-configurado)."
  fi
}

get_install_base() {
  if [ -n "$ARG_DIR" ]; then
    INSTALL_BASE="$ARG_DIR"
    return
  fi
  case "$OS_NAME" in
    linux|darwin) INSTALL_BASE="$HOME/camilladsp" ;;
    windows)      INSTALL_BASE="/c/CamillaDSP" ;;
    *)            INSTALL_BASE="$HOME/camilladsp" ;;
  esac
}

# Descarga
DOWNLOADER=""
if command -v curl &>/dev/null; then
  DOWNLOADER="curl"
elif command -v wget &>/dev/null; then
  DOWNLOADER="wget"
fi

download_file() {
  local url="$1"
  local dest="$2"
  log_info "Descargando: $(basename "$dest")"
  if [ "$DOWNLOADER" = "curl" ]; then
    curl -L --progress-bar -o "$dest" "$url"
  else
    wget -O "$dest" "$url"
  fi
}

github_api_get() {
  local repo="$1"
  local url="https://api.github.com/repos/${repo}/releases/latest"
  if [ "$DOWNLOADER" = "curl" ]; then
    GH_JSON=$(curl -s "$url")
  else
    GH_JSON=$(wget -q -O- "$url")
  fi
}

json_get() {
  local json="$1"
  local field="$2"
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r ".$field // empty"
  else
    echo "$json" | grep -oP "\"${field}\"\s*:\s*\"\K[^\"]*" | head -1
  fi
}

json_array_urls() {
  local json="$1"
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r '.assets[] | "\(.name)|\(.browser_download_url)"'
  elif command -v python3 &>/dev/null; then
    echo "$json" | python3 -c "import sys,json; [print(a['name']+'|'+a['browser_download_url']) for a in json.load(sys.stdin).get('assets',[])]"
  elif command -v python &>/dev/null; then
    echo "$json" | python -c "import sys,json; [print(a['name']+'|'+a['browser_download_url']) for a in json.load(sys.stdin).get('assets',[])]"
  else
    echo "$json" | grep -oP '"browser_download_url":\s*"\K[^"]*' | while read -r url; do
      name=$(basename "$url" | sed 's/?.*$//')
      echo "${name}|${url}"
    done
  fi
}

# Buscar assets
find_engine_asset() {
  FOUND_ASSET=""
  local assets_list="$1"
  local os_key
  case "$OS_NAME" in
    linux)   os_key="linux" ;;
    darwin)  os_key="macos" ;;
    windows) os_key="windows" ;;
    *)       os_key="$OS_NAME" ;;
  esac
  local ext
  [ "$OS_NAME" = "windows" ] && ext=".zip" || ext=".tar.gz"

  while IFS= read -r line; do
    local name="${line%%|*}"
    local lower_name
    lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_name" | grep -q "camilladsp-${os_key}-${ARCH}"; then
      FOUND_ASSET="$line"
      return 0
    fi
  done <<< "$assets_list"
  return 1
}

find_gui_asset() {
  FOUND_ASSET=""
  local assets_list="$1"
  local os_key
  case "$OS_NAME" in
    linux)   os_key="linux" ;;
    darwin)  os_key="macos" ;;
    windows) os_key="windows" ;;
    *)       os_key="$OS_NAME" ;;
  esac

  while IFS= read -r line; do
    local lower_name
    lower_name=$(echo "${line%%|*}" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_name" | grep -q "bundle_${os_key}_${ARCH}"; then
      FOUND_ASSET="$line"
      return 0
    fi
  done <<< "$assets_list"
  return 1
}

extract_archive() {
  local archive="$1"
  local dest="$2"
  mkdir -p "$dest"
  case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" ;;
    *.zip)           unzip -q "$archive" -d "$dest" ;;
  esac
}

# Instalación del Engine
install_engine() {
  log_step "CamillaDSP Engine"
  [ -z "$DOWNLOADER" ] && { log_error "Se requiere curl o wget"; return 1; }

  log_info "Consultando GitHub..."
  github_api_get "$CAMILLADSP_REPO"

  local tag version
  tag=$(json_get "$GH_JSON" "tag_name")
  version="${tag#v}"
  log_info "Versión: ${version}"

  local assets_list
  assets_list=$(json_array_urls "$GH_JSON")

  find_engine_asset "$assets_list" || { log_error "No se encontró paquete"; return 1; }

  local asset_name="${FOUND_ASSET%%|*}"
  local asset_url="${FOUND_ASSET##*|}"
  log_info "Asset: ${asset_name}"

  local tmpdir=$(mktemp -d)
  local archive="${tmpdir}/${asset_name}"
  download_file "$asset_url" "$archive"

  local extract_dir="${tmpdir}/extracted"
  log_info "Extrayendo..."
  extract_archive "$archive" "$extract_dir"

  local src_binary
  [ "$OS_NAME" = "windows" ] && src_binary=$(find "$extract_dir" -name "camilladsp.exe" -type f) || src_binary=$(find "$extract_dir" -name "camilladsp" -type f)
  [ -z "$src_binary" ] && src_binary=$(find "$extract_dir" -name "camilladsp*" -type f | head -1)

  local engine_dir="${INSTALL_BASE}/engine"
  mkdir -p "$engine_dir"
  cp "$src_binary" "${engine_dir}/camilladsp"
  chmod +x "${engine_dir}/camilladsp"
  echo "$version" > "${engine_dir}/VERSION"

  rm -rf "$tmpdir"
  log_ok "Engine instalado"
  return 0
}

# install_gui: no se usa — este proyecto usa solo la consola web propia
install_gui() { return 0; }


# Liberar puertos y detener servicios conflictivos
stop_conflicting_services() {
  log_step "Liberando puertos..."

  # Detener servicios systemd del sistema (instalaciones previas en /opt etc.)
  for svc in camilladsp-backend camilladsp-engine camilladsp; do
    if systemctl is-active --quiet "${svc}.service" 2>/dev/null; then
      log_info "Deteniendo servicio del sistema: ${svc}..."
      if sudo -n systemctl stop "${svc}.service" 2>/dev/null; then
        sudo -n systemctl disable "${svc}.service" 2>/dev/null || true
        log_ok "${svc} detenido"
      else
        # Sin sudo: matar el proceso directamente por PID
        local main_pid
        main_pid=$(systemctl show -p MainPID --value "${svc}.service" 2>/dev/null)
        if [ -n "$main_pid" ] && [ "$main_pid" != "0" ]; then
          kill "$main_pid" 2>/dev/null && log_ok "${svc} detenido (PID $main_pid)" || log_warn "No se pudo detener ${svc}"
        fi
      fi
    fi
  done

  # Detener servicios systemd de usuario si están activos
  for svc in camilladsp-backend camilladsp-engine; do
    if systemctl --user is-active --quiet "${svc}.service" 2>/dev/null; then
      log_info "Deteniendo servicio de usuario: ${svc}..."
      systemctl --user stop "${svc}.service" 2>/dev/null || true
    fi
  done

  # Matar cualquier proceso que ocupe el puerto de la GUI
  local pid
  pid=$(ss -tlnp 2>/dev/null | grep ":${GUI_HTTP_PORT} " | grep -oP 'pid=\K[0-9]+' | head -1)
  if [ -n "$pid" ]; then
    log_info "Liberando puerto ${GUI_HTTP_PORT} (PID $pid)..."
    kill "$pid" 2>/dev/null
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    log_ok "Puerto ${GUI_HTTP_PORT} liberado"
  fi

  # Matar cualquier proceso que ocupe el puerto del engine
  pid=$(ss -tlnp 2>/dev/null | grep ":${ENGINE_WS_PORT} " | grep -oP 'pid=\K[0-9]+' | head -1)
  if [ -n "$pid" ]; then
    log_info "Liberando puerto ${ENGINE_WS_PORT} (PID $pid)..."
    kill "$pid" 2>/dev/null
    sleep 1
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
    log_ok "Puerto ${ENGINE_WS_PORT} liberado"
  fi
}

# Frontend Web
install_web_frontend() {
  log_step "Instalando Frontend Web (puerto ${WEB_GUI_PORT})..."
  local web_dir="${INSTALL_BASE}/web"
  mkdir -p "$web_dir"

  # Instalar dependencias Python
  log_info "Instalando paquetes Python: flask, websocket-client, pyyaml..."
  local pip_cmd=""
  if command -v pip3 &>/dev/null; then pip_cmd="pip3";
  elif command -v pip &>/dev/null; then pip_cmd="pip"; fi

  if [ -n "$pip_cmd" ]; then
    $pip_cmd install flask websocket-client pyyaml \
      --break-system-packages --quiet 2>/dev/null || \
    $pip_cmd install flask websocket-client pyyaml --quiet 2>/dev/null || true
  else
    log_warn "pip no encontrado — instala flask websocket-client pyyaml manualmente"
  fi

  # Descargar server.py e index.html desde el repositorio
  local dl_ok=1
  log_info "Descargando servidor web y frontend..."

  if command -v curl &>/dev/null; then
    curl -fsSL "${WEB_REPO_RAW}/server.py"  -o "${web_dir}/server.py"  2>/dev/null && \
    curl -fsSL "${WEB_REPO_RAW}/index.html" -o "${web_dir}/index.html" 2>/dev/null || dl_ok=0
  elif command -v wget &>/dev/null; then
    wget -q "${WEB_REPO_RAW}/server.py"  -O "${web_dir}/server.py"  2>/dev/null && \
    wget -q "${WEB_REPO_RAW}/index.html" -O "${web_dir}/index.html" 2>/dev/null || dl_ok=0
  else
    log_warn "curl/wget no disponible — no se pudo descargar el frontend web"
    dl_ok=0
  fi

  if [ "$dl_ok" = "0" ] || [ ! -f "${web_dir}/server.py" ] || [ ! -f "${web_dir}/index.html" ]; then
    log_warn "Frontend Web no instalado (requiere conexión a internet)"
    return 1
  fi

  # Reemplazar ruta de instalación en server.py (cualquier valor previo de INSTALL_BASE)
  sed -i "s|^INSTALL_BASE .*= .*|INSTALL_BASE  = \"${INSTALL_BASE}\"|" "${web_dir}/server.py" 2>/dev/null || true
  sed -i "s|^WEB_PORT .*= .*|WEB_PORT      = ${WEB_GUI_PORT}|" "${web_dir}/server.py" 2>/dev/null || true

  log_ok "Frontend Web instalado en ${web_dir}"
  return 0
}

# Scripts de estado
create_scripts() {
  log_step "Creando scripts de utilidad"
  local scripts_dir="${INSTALL_BASE}/scripts"
  mkdir -p "$scripts_dir"

  cat > "${scripts_dir}/status.sh" << SCRIPT
#!/bin/bash
echo "=== CamillaDSP Status ==="
for svc in camilladsp camilladsp-web statime-inferno; do
  state=\$(systemctl is-active "\$svc" 2>/dev/null || echo "not-found")
  echo "  \$svc: \$state"
done
echo ""
echo "Web Console: http://\$(hostname -I | awk '{print \$1}'):5000"
SCRIPT

  chmod +x "${scripts_dir}/status.sh"
  log_ok "Scripts creados"
}

# Configuración por defecto
create_default_config() {
  local config_file="${INSTALL_BASE}/config/camilladsp.yml"
  mkdir -p "${INSTALL_BASE}/config"
  cat > "$config_file" << 'EOF'
---
description: default
devices:
  adjust_period: null
  capture:
    channels: 2
    device: "null"
    format: null
    type: Alsa
  capture_samplerate: 48000
  chunksize: 1024
  playback:
    channels: 2
    device: "null"
    format: null
    type: Alsa
  samplerate: 48000
filters: {}
pipeline: []
EOF
  log_ok "Configuración creada"

  mkdir -p "${INSTALL_BASE}/coeffs"
}

create_gui_config() {
  local cfg="${INSTALL_BASE}/gui/config/camillagui.yml"
  mkdir -p "${INSTALL_BASE}/gui/config"
  mkdir -p "${INSTALL_BASE}/coeffs"
  cat > "$cfg" << EOF
---
camilla_host: "localhost"
camilla_port: ${ENGINE_WS_PORT}
bind_address: "0.0.0.0"
port: ${GUI_HTTP_PORT}
ssl_certificate: null
ssl_private_key: null
gui_config_file: null
config_dir: "${INSTALL_BASE}/config"
coeff_dir: "${INSTALL_BASE}/coeffs"
default_config: "${INSTALL_BASE}/config/camilladsp.yml"
statefile_path: "${INSTALL_BASE}/statefile.yml"
log_file: "${INSTALL_BASE}/logs/camilladsp.log"
on_set_active_config: null
on_get_active_config: null
supported_capture_types: null
supported_playback_types: null
EOF
  log_ok "Config GUI creada"
}

# Autostart al arranque del sistema (sin Dante — instala servicios system)
setup_autostart() {
  local base="${INSTALL_BASE}"
  local start_script="${base}/start_camilladsp.sh"

  if command -v systemctl &>/dev/null; then
    sudo tee /etc/systemd/system/camilladsp.service > /dev/null << EOF
[Unit]
Description=CamillaDSP Audio Processor
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=${start_script}
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=60
StartLimitBurst=5
KillMode=process
TimeoutStartSec=120
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

    sudo tee /etc/systemd/system/camilladsp-web.service > /dev/null << EOF
[Unit]
Description=CamillaDSP Web Console
After=network-online.target

[Service]
ExecStart=/usr/bin/python3 ${base}/web/server.py
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable camilladsp camilladsp-web
    sudo systemctl start camilladsp-web
    sudo systemctl start camilladsp
    sleep 3
    systemctl is-active --quiet camilladsp-web && log_ok "camilladsp-web activo" || log_warn "camilladsp-web no arrancó"
    systemctl is-active --quiet camilladsp      && log_ok "camilladsp activo"    || log_warn "camilladsp iniciando..."
    return 0
  fi

  log_warn "No se pudo configurar autostart (requiere systemd)"
}

# ── Dante / Inferno ───────────────────────────────────────────────────────────

DANTE_ZIP_NAME="dante-aarch64.zip"
DANTE_ZIP_URL="https://github.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend/releases/download/dante-plugin/${DANTE_ZIP_NAME}"
INFERNO_STATE_BASE="$HOME/.local/state/inferno_aoip"

ask_dante() {
  echo ""
  echo -e "${CYAN}${BOLD}┌─────────────────────────────────────────────────────┐"
  echo -e "│          Integración Dante / AES67 (inferno)        │"
  echo -e "└─────────────────────────────────────────────────────┘${RESET}"
  echo -e "  Instala el plugin inferno (RX/TX Dante via red)"
  echo -e "  y el demonio PTP ${BOLD}statime-inferno${RESET} para sincronización."
  echo ""
  echo -n "  ¿Instalar soporte Dante/AES67? [s/N]: "
  read -n 1 -r DANTE_REPLY
  echo ""
  [[ "$DANTE_REPLY" =~ ^[Ss]$ ]]
}

install_dante() {
  log_step "Instalando soporte Dante / Inferno"

  # ── 1. Detectar interfaz de red para Dante ─────────────────────────────────
  local eth_iface eth_ip
  # Primero buscar Ethernet con IP; si no hay, usar cualquier interfaz con IP (incluido WiFi)
  eth_iface=$(ip -o link show | awk -F': ' '$2 !~ /^lo|^docker|^veth|^br/ {print $2}' | while read iface; do
    ip=$(ip -4 addr show "$iface" 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}' | head -1)
    if [ -n "$ip" ]; then echo "$iface"; break; fi
  done)
  eth_ip=$(ip -4 addr show "$eth_iface" 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}' | head -1)

  if [ -z "$eth_ip" ]; then
    log_warn "No se detectó IP en ninguna interfaz — asegurate de tener red conectada"
    eth_ip="0.0.0.0"
    eth_iface="eth0"
  fi
  log_info "Interfaz Dante: $eth_iface ($eth_ip)"

  # ── 2. Instalar plugin inferno (.so) ────────────────────────────────────────
  local alsa_plugin_dir="/usr/lib/$(uname -m)-linux-gnu/alsa-lib"
  local inferno_so="${alsa_plugin_dir}/libasound_module_pcm_inferno.so"

  if [ -f "$inferno_so" ]; then
    log_ok "Plugin inferno ya instalado"
  else
    log_info "Buscando $DANTE_ZIP_NAME..."
    local zip_path=""

    # Buscar en directorio del script primero
    if [ -f "${SCRIPT_DIR}/${DANTE_ZIP_NAME}" ]; then
      zip_path="${SCRIPT_DIR}/${DANTE_ZIP_NAME}"
      log_info "Encontrado en directorio local"
    else
      log_info "Descargando desde releases..."
      local tmp_zip="/tmp/${DANTE_ZIP_NAME}"
      if curl -fsSL "$DANTE_ZIP_URL" -o "$tmp_zip" 2>/dev/null || \
         wget -q "$DANTE_ZIP_URL" -O "$tmp_zip" 2>/dev/null; then
        zip_path="$tmp_zip"
      else
        log_error "No se pudo descargar $DANTE_ZIP_NAME"
        log_warn "Descargalo manualmente y colócalo junto al instalador"
        return 1
      fi
    fi

    log_info "Extrayendo plugin..."
    local tmp_dir="/tmp/dante_extract"
    rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"
    unzip -q "$zip_path" -d "$tmp_dir"

    local so_file
    so_file=$(find "$tmp_dir" -name "libasound_module_pcm_inferno.so" | head -1)
    if [ -z "$so_file" ]; then
      log_error "No se encontró libasound_module_pcm_inferno.so en el zip"
      return 1
    fi

    sudo mkdir -p "$alsa_plugin_dir"
    sudo cp "$so_file" "$inferno_so"
    sudo chmod 644 "$inferno_so"
    rm -rf "$tmp_dir"
    log_ok "Plugin inferno instalado en $inferno_so"
  fi

  # ── 3. Instalar statime-inferno ─────────────────────────────────────────────
  # El binario en el zip se llama "statime" y se instala en /usr/local/bin/statime
  if ! command -v statime &>/dev/null && [ ! -f /usr/local/bin/statime ]; then
    log_info "Buscando statime en zip..."
    local zip_path=""
    if [ -f "${SCRIPT_DIR}/${DANTE_ZIP_NAME}" ]; then
      zip_path="${SCRIPT_DIR}/${DANTE_ZIP_NAME}"
    elif [ -f "/tmp/${DANTE_ZIP_NAME}" ]; then
      zip_path="/tmp/${DANTE_ZIP_NAME}"
    fi

    if [ -n "$zip_path" ]; then
      local tmp_dir="/tmp/dante_extract2"
      rm -rf "$tmp_dir"; mkdir -p "$tmp_dir"
      unzip -q "$zip_path" -d "$tmp_dir"
      local statime_bin
      # Buscar primero "statime-inferno", luego "statime" (nombre varía según versión del zip)
      statime_bin=$(find "$tmp_dir" -name "statime-inferno" -type f | head -1)
      [ -z "$statime_bin" ] && statime_bin=$(find "$tmp_dir" -name "statime" -type f | head -1)
      if [ -n "$statime_bin" ]; then
        sudo cp "$statime_bin" /usr/local/bin/statime
        sudo chmod +x /usr/local/bin/statime
        log_ok "statime instalado en /usr/local/bin/statime"
      else
        log_warn "statime no encontrado en el zip"
      fi
      rm -rf "$tmp_dir"
    fi
  else
    log_ok "statime ya instalado"
  fi

  # ── 4. Configurar statime-inferno.toml ────────────────────────────────────
  local statime_cfg="/etc/statime-inferno.toml"
  if [ ! -f "$statime_cfg" ]; then
    sudo tee "$statime_cfg" > /dev/null << EOF
loglevel = "info"
identity = "$(cat /sys/class/net/${eth_iface}/address 2>/dev/null | tr -d ':' | head -c 12)0000"
sdo-id = 0
domain = 0
priority1 = 251
virtual-system-clock = true
virtual-system-clock-base = "tai"
usrvclock-export = true
usrvclock-path = "/tmp/ptp-usrvclock"

[[port]]
interface = "${eth_iface}"
network-mode = "ipv4"
hardware-clock = "none"
protocol-version = "PTPv1"
EOF
    log_ok "statime-inferno.toml creado ($eth_iface)"
  else
    # Actualizar interfaz si cambió
    sudo sed -i "s/^interface = \"[^\"]*\"/interface = \"${eth_iface}\"/" "$statime_cfg"
    log_ok "statime-inferno.toml actualizado (interfaz: $eth_iface)"
  fi

  # ── 5. Script pre-start para detectar interfaz automáticamente ─────────────
  sudo cp "$(dirname "$0")/statime-update-iface.sh" /usr/local/bin/statime-update-iface.sh 2>/dev/null || \
  sudo tee /usr/local/bin/statime-update-iface.sh > /dev/null << 'SCRIPTEOF'
#!/bin/bash
ASOUNDRC="${HOME:-/root}/.asoundrc"
TOML="/etc/statime-inferno.toml"
BIND_IP=$(grep -oP 'BIND_IP\s+"\K[^"]+' "$ASOUNDRC" | head -1)
if [ -z "$BIND_IP" ]; then exit 0; fi
IFACE=$(ip -4 addr show | awk -v ip="$BIND_IP" '/^[0-9]+:/ { iface=$2; sub(/:$/, "", iface) } /inet / { if (index($2, ip"/") == 1) print iface }')
if [ -z "$IFACE" ]; then exit 0; fi
CURRENT=$(grep -oP 'interface\s*=\s*"\K[^"]+' "$TOML" | head -1)
if [ "$CURRENT" != "$IFACE" ]; then
    sed -i "s/interface = \"$CURRENT\"/interface = \"$IFACE\"/" "$TOML"
    echo "[statime-pre] interfaz actualizada: $CURRENT -> $IFACE (IP=$BIND_IP)"
fi
SCRIPTEOF
  sudo chmod +x /usr/local/bin/statime-update-iface.sh

  # ── 6. Servicio systemd statime-inferno ────────────────────────────────────
  if [ ! -f /etc/systemd/system/statime-inferno.service ]; then
    sudo tee /etc/systemd/system/statime-inferno.service > /dev/null << 'EOF'
[Unit]
Description=Statime PTP Daemon for Inferno/Dante
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Environment=RUST_LOG=warn
StandardOutput=null
StandardError=null
ExecStartPre=/usr/local/bin/statime-update-iface.sh
ExecStart=/usr/local/bin/statime -c /etc/statime-inferno.toml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
    sudo systemctl daemon-reload
    sudo systemctl enable statime-inferno
    sudo systemctl start statime-inferno
    sleep 2
    if systemctl is-active --quiet statime-inferno; then
      log_ok "statime-inferno activo"
    else
      log_warn "statime-inferno no pudo iniciar (puede requerir PTP master en la red)"
    fi
  else
    sudo systemctl restart statime-inferno 2>/dev/null || true
    log_ok "statime-inferno reiniciado"
  fi

  # ── 6. Crear socket PTP ────────────────────────────────────────────────────
  # statime-inferno expone el reloj PTP en este socket
  local ptp_socket="/tmp/ptp-usrvclock"

  # ── 7. Configurar .asoundrc con inferno_rx e inferno_tx ──────────────────
  local asoundrc="$HOME/.asoundrc"
  local ip_hex
  ip_hex=$(printf '%02x' $(echo "$eth_ip" | tr '.' ' '))

  # PROCESS_ID inicial para inferno_rx (1000 = 0x03e8)
  local rx_pid=1000

  cat > "$asoundrc" << EOF
pcm.inferno {
    type inferno
    @args.NAME { type string }
    @args.BIND_IP { type string }
    @args.SAMPLE_RATE { type string }
    @args.PROCESS_ID { type string }
    @args.RX_CHANNELS { type string }
    @args.TX_CHANNELS { type string }
    @args.CLOCK_PATH { type string }
    @args.RX_LATENCY_NS { type string }
    NAME \$NAME
    BIND_IP \$BIND_IP
    SAMPLE_RATE \$SAMPLE_RATE
    PROCESS_ID \$PROCESS_ID
    RX_CHANNELS \$RX_CHANNELS
    TX_CHANNELS \$TX_CHANNELS
    CLOCK_PATH \$CLOCK_PATH
    RX_LATENCY_NS \$RX_LATENCY_NS
}

pcm.inferno_rx {
    type inferno
    NAME "tvbox-dante"
    BIND_IP "${eth_iface}"
    SAMPLE_RATE "48000"
    RX_CHANNELS "2"
    TX_CHANNELS "0"
    PROCESS_ID "${rx_pid}"
    CLOCK_PATH "${ptp_socket}"
    RX_LATENCY_NS "1000000"
}

pcm.inferno_tx {
    type inferno
    BIND_IP "${eth_iface}"
    SAMPLE_RATE "48000"
    RX_CHANNELS "0"
    TX_CHANNELS "2"
    PROCESS_ID "10"
    ALT_PORT "8700"
    CLOCK_PATH "${ptp_socket}"
    RX_LATENCY_NS "1000000"
    TX_LATENCY_NS "1000000"
}
EOF
  log_ok ".asoundrc configurado (interfaz: $eth_iface / IP: $eth_ip)"

  # ── 8. Crear directorio de estado inferno_rx con suscripciones vacías ────
  local rx_dir="${INFERNO_STATE_BASE}/0000${ip_hex}$(printf '%04x' $rx_pid)"
  mkdir -p "$rx_dir"
  if [ ! -f "${rx_dir}/rx_subscriptions.toml" ]; then
    echo 'channels = []' > "${rx_dir}/rx_subscriptions.toml"
    log_ok "rx_subscriptions.toml creado vacío (Dante Controller asigna canales)"
  fi

  # Archivo canónico de suscripciones (referencia fuera del dir inferno que se limpia en cada arranque)
  local dante_subs="${INSTALL_BASE}/config/dante_subscriptions.toml"
  if [ ! -f "$dante_subs" ]; then
    echo 'channels = []' > "$dante_subs"
    log_ok "dante_subscriptions.toml creado vacío"
  fi

  # ── 9. Instalar start_camilladsp.sh (arranque robusto) ──────────────────
  local start_script="${INSTALL_BASE}/start_camilladsp.sh"
  if [ -f "${SCRIPT_DIR}/start_camilladsp.sh" ]; then
    cp "${SCRIPT_DIR}/start_camilladsp.sh" "$start_script"
    sed -i "s|CONFIG=\"/root/camilladsp/config/camilladsp.yml\"|CONFIG=\"${INSTALL_BASE}/config/camilladsp.yml\"|" "$start_script"
    sed -i "s|ASOUNDRC=\"/root/.asoundrc\"|ASOUNDRC=\"${HOME}/.asoundrc\"|" "$start_script"
    sed -i "s|STATE_BASE=\"/root/.local/state/inferno_aoip\"|STATE_BASE=\"${HOME}/.local/state/inferno_aoip\"|" "$start_script"
    sed -i "s|ENGINE=\"/root/camilladsp/engine/camilladsp\"|ENGINE=\"${INSTALL_BASE}/engine/camilladsp\"|" "$start_script"
    log_ok "start_camilladsp.sh instalado desde repo"
  else
    log_warn "start_camilladsp.sh no encontrado en ${SCRIPT_DIR} — descargando..."
    local start_url="https://raw.githubusercontent.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend/main/start_camilladsp.sh"
    curl -fsSL "$start_url" -o "$start_script" 2>/dev/null || \
      wget -q "$start_url" -O "$start_script" 2>/dev/null || \
      { log_error "No se pudo obtener start_camilladsp.sh"; return 1; }
    sed -i "s|/root/camilladsp|${INSTALL_BASE}|g" "$start_script"
    sed -i "s|/root/\.asoundrc|${HOME}/.asoundrc|g" "$start_script"
    sed -i "s|/root/\.local|${HOME}/.local|g" "$start_script"
    log_ok "start_camilladsp.sh descargado"
  fi
  chmod +x "$start_script"

  # ── 10. Servicio camilladsp systemd (root, Restart=always) ───────────────
  sudo tee /etc/systemd/system/camilladsp.service > /dev/null << EOF
[Unit]
Description=CamillaDSP Audio Processor
After=network-online.target statime-inferno.service
Wants=network-online.target

[Service]
ExecStart=${start_script}
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=60
StartLimitBurst=5
KillMode=process
TimeoutStartSec=120
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
EOF

  sudo tee /etc/systemd/system/camilladsp-web.service > /dev/null << EOF
[Unit]
Description=CamillaDSP Web Console
After=network-online.target

[Service]
ExecStart=python3 ${INSTALL_BASE}/web/server.py
Restart=on-failure
RestartSec=5
StartLimitIntervalSec=60
StartLimitBurst=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable camilladsp camilladsp-web
  log_ok "Servicios systemd camilladsp y camilladsp-web configurados"

  # ── 11. Config YAML por defecto con inferno_rx ────────────────────────────
  cat > "${INSTALL_BASE}/config/camilladsp.yml" << 'EOF'
description: inferno_rx_direct
devices:
  samplerate: 48000
  chunksize: 512
  enable_rate_adjust: true
  capture_samplerate: 48000
  capture:
    type: Alsa
    channels: 2
    device: inferno_rx
    format: S32_LE
  playback:
    type: Alsa
    channels: 2
    device: "null"
    format: S16_LE
mixers: {}
pipeline: []
EOF
  log_ok "Config CamillaDSP con inferno_rx creada"

  # ── 11b. Presets de audio ──────────────────────────────────────────────────
  local presets_dir="${INSTALL_BASE}/config/presets"
  mkdir -p "$presets_dir"

  # Preset: Dante RX -> MAYA44
  cat > "${presets_dir}/dante_to_maya44.yml" << 'EOF'
description: inferno_rx_direct
devices:
  samplerate: 48000
  chunksize: 1024
  capture_samplerate: 48000
  enable_rate_adjust: true
  capture:
    type: Alsa
    channels: 2
    device: inferno_rx
    format: S32_LE
  playback:
    type: Alsa
    channels: 4
    device: hw:1,0
    format: S16_LE
mixers:
  Mixer 1:
    channels:
      in: 2
      out: 4
    mapping:
    - {dest: 0, mute: false, sources: [{channel: 0, gain: 0, inverted: false, mute: false, scale: dB}]}
    - {dest: 1, mute: false, sources: [{channel: 1, gain: 0, inverted: false, mute: false, scale: dB}]}
    - {dest: 2, mute: false, sources: [{channel: 0, gain: 0, inverted: false, mute: false, scale: dB}]}
    - {dest: 3, mute: false, sources: [{channel: 1, gain: 0, inverted: false, mute: false, scale: dB}]}
pipeline:
- {type: Mixer, name: Mixer 1}
processors: {}
EOF

  # Preset: MAYA44 -> Dante TX
  cat > "${presets_dir}/maya44_to_dante.yml" << 'EOF'
description: maya44_to_dante_tx
devices:
  samplerate: 48000
  chunksize: 1024
  capture_samplerate: 48000
  capture:
    type: Alsa
    channels: 4
    device: hw:1,0
    format: S16_LE
  playback:
    type: Alsa
    channels: 2
    device: inferno_tx
    format: S32_LE
mixers:
  Mixer 1:
    channels:
      in: 4
      out: 2
    mapping:
    - {dest: 0, mute: false, sources: [{channel: 0, gain: 0, inverted: false, mute: false, scale: dB}]}
    - {dest: 1, mute: false, sources: [{channel: 1, gain: 0, inverted: false, mute: false, scale: dB}]}
pipeline:
- {type: Mixer, name: Mixer 1}
processors: {}
EOF

  # Preset: MAYA44 local
  cat > "${presets_dir}/maya44usb.yml" << 'EOF'
description: maya44_local
devices:
  samplerate: 48000
  chunksize: 1024
  capture:
    type: Alsa
    channels: 4
    device: hw:1,0
    format: S16_LE
  playback:
    type: Alsa
    channels: 4
    device: hw:1,0
    format: S16_LE
mixers:
  Mixer 1:
    channels:
      in: 4
      out: 4
    mapping:
    - {dest: 0, mute: false, sources: [{channel: 0, gain: 0, inverted: false, mute: false, scale: dB}]}
    - {dest: 1, mute: false, sources: [{channel: 1, gain: 0, inverted: false, mute: false, scale: dB}]}
    - {dest: 2, mute: false, sources: [{channel: 0, gain: 0, inverted: false, mute: false, scale: dB}]}
    - {dest: 3, mute: false, sources: [{channel: 1, gain: 0, inverted: false, mute: false, scale: dB}]}
pipeline:
- {type: Mixer, name: Mixer 1}
processors: {}
EOF

  log_ok "Presets de audio creados en ${presets_dir}"

  # ── 12. Prueba funcional ───────────────────────────────────────────────────
  log_step "Prueba de integración Dante"

  # Verificar plugin ALSA carga
  if aplay -L 2>/dev/null | grep -q "inferno"; then
    log_ok "Plugin inferno visible en ALSA"
  else
    log_warn "Plugin inferno no aparece en ALSA — verificar instalación"
  fi

  # Verificar statime-inferno
  if systemctl is-active --quiet statime-inferno; then
    log_ok "statime-inferno corriendo"
  else
    log_warn "statime-inferno no activo (normal sin PTP master en la red)"
  fi

  echo ""
  log_ok "Instalación Dante completada"
  echo ""
  echo -e "  ${YELLOW}Próximos pasos:${RESET}"
  echo -e "  1. En la web → tab MIXER → botón ${BOLD}Dante RX${RESET}"
  echo -e "     Ingresar hostname del equipo Dante y nombres de canales TX"
  echo -e "  2. Seleccionar ${BOLD}inferno_rx${RESET} como dispositivo de entrada"
  echo -e "  3. El servicio camilladsp arrancará automáticamente"
  echo ""
}

# Main
main() {
  # Capturar directorio del script antes de cualquier cambio de directorio
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

  header
  detect_system
  check_system_dependencies
  cleanup_previous_install
  get_install_base

  log_info "Sistema: $(uname -s) $(uname -m)"
  log_info "Directorio: ${INSTALL_BASE}"

  configure_journal_limits

  if [ "$ARG_UPDATE" = "1" ]; then
    log_step "Modo actualización"
    sudo systemctl stop camilladsp camilladsp-web 2>/dev/null || true
    log_info "Servicios detenidos"
  fi

  # Liberar puertos y detener procesos anteriores para evitar el error "Text file busy" al copiar binarios
  if [ "$ARG_NO_SERVICE" != "1" ]; then
    stop_conflicting_services
  fi

  # Instalar engine
  log_step "Instalando Engine..."
  install_engine
  ENGINE_OK=$?

  if [ "$ENGINE_OK" != "0" ]; then
    log_error "La instalación del engine falló"
    exit 1
  fi

  # Instalar Frontend Web
  install_web_frontend || true

  # Instalar start_camilladsp.sh (siempre, Dante o no)
  local start_script="${INSTALL_BASE}/start_camilladsp.sh"
  if [ ! -f "$start_script" ]; then
    if [ -f "${SCRIPT_DIR}/start_camilladsp.sh" ]; then
      cp "${SCRIPT_DIR}/start_camilladsp.sh" "$start_script"
      sed -i "s|/root/camilladsp|${INSTALL_BASE}|g" "$start_script"
      sed -i "s|/root/\.asoundrc|${HOME}/.asoundrc|g" "$start_script"
      sed -i "s|/root/\.local|${HOME}/.local|g" "$start_script"
      log_ok "start_camilladsp.sh instalado"
    else
      local start_url="https://raw.githubusercontent.com/aasayag-hash/camilladsp-auto-install-with-back-and-frontend/main/start_camilladsp.sh"
      curl -fsSL "$start_url" -o "$start_script" 2>/dev/null || \
        wget -q "$start_url" -O "$start_script" 2>/dev/null || \
        log_warn "No se pudo obtener start_camilladsp.sh"
      sed -i "s|/root/camilladsp|${INSTALL_BASE}|g" "$start_script" 2>/dev/null || true
      sed -i "s|/root/\.asoundrc|${HOME}/.asoundrc|g" "$start_script" 2>/dev/null || true
      sed -i "s|/root/\.local|${HOME}/.local|g" "$start_script" 2>/dev/null || true
      log_ok "start_camilladsp.sh descargado"
    fi
    chmod +x "$start_script"
  fi

  # Crear config y scripts
  if [ "$ARG_UPDATE" != "1" ]; then
    create_default_config
    create_gui_config
  fi
  create_scripts

  # Asegurar que existen los directorios necesarios
  mkdir -p "${INSTALL_BASE}/config"
  mkdir -p "${INSTALL_BASE}/coeffs"
  mkdir -p "${INSTALL_BASE}/logs"
  mkdir -p "${INSTALL_BASE}/scripts"

  # ── Dante opcional ────────────────────────────────────────────────────────
  INSTALL_DANTE=0
  if [ "$ARG_UPDATE" != "1" ]; then
    if ask_dante; then
      INSTALL_DANTE=1
      install_dante || log_warn "Instalación Dante incompleta — ver mensajes anteriores"
    fi
  fi

  # Configurar e iniciar servicios
  if [ "$ARG_NO_SERVICE" != "1" ]; then
    if [ "$INSTALL_DANTE" = "1" ]; then
      # install_dante() ya creó e inició los servicios systemd
      log_step "Reiniciando servicios con Dante..."
      sudo systemctl restart camilladsp-web
      sudo systemctl restart camilladsp
      sleep 5
      systemctl is-active --quiet camilladsp-web && log_ok "camilladsp-web activo" || log_warn "camilladsp-web no arrancó"
      systemctl is-active --quiet camilladsp      && log_ok "camilladsp activo"     || log_warn "camilladsp iniciando (arranca lento con Dante)"
    else
      # Sin Dante: setup_autostart crea los servicios systemd y los inicia
      log_step "Configurando e iniciando servicios..."
      setup_autostart
    fi
  fi


  local host_ip
  host_ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  
  echo ""
  if [ "$ARG_UPDATE" = "1" ]; then
    log_ok "Actualización completada"
  else
    log_ok "Instalación completada"
  fi
  
  echo ""
  echo -e "  ${GREEN}Accede a:${RESET}"
  echo -e "    ${CYAN}Web Console → http://localhost:${WEB_GUI_PORT}${RESET}"
  if [ -n "$host_ip" ]; then
    echo -e "    ${CYAN}Web Console → http://${host_ip}:${WEB_GUI_PORT}${RESET}"
  fi
  echo ""

  # Eliminar el directorio clonado del instalador solo si es un clone temporal (sin .git propio usado)
  if [ -n "$SCRIPT_DIR" ] && \
     [ "$SCRIPT_DIR" != "/" ] && \
     [ "$SCRIPT_DIR" != "$HOME" ] && \
     [ "$SCRIPT_DIR" != "$INSTALL_BASE" ] && \
     [ ! -d "$SCRIPT_DIR/.git" ]; then
    log_step "Limpiando instalador..."
    rm -rf "$SCRIPT_DIR"
    log_ok "Directorio del instalador eliminado: $SCRIPT_DIR"
  fi
}

main "$@"