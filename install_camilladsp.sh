#!/bin/bash
# ==============================================================
#  CamillaDSP — Instalador Automático
#  Engine  +  GUI Backend  +  Frontend
# ==============================================================

SCRIPT_VERSION="1.0.0"

# Repositorios GitHub
CAMILLADSP_REPO="HEnquist/camilladsp"
CAMILLAGUI_REPO="HEnquist/camillagui-backend"

# Puertos por defecto
ENGINE_WS_PORT=1234
GUI_HTTP_PORT=5005

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
      echo "Uso: bash install_camilladsp.sh [opciones]"
      echo "Opciones: --update, --uninstall, --check, --dir <ruta>"
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
  echo -e "║    Engine  +  GUI Backend  +  Frontend                   ║"
  printf  "║                                         v%-19s║\n" "$SCRIPT_VERSION"
  echo -e "╚══════════════════════════════════════════════════════════╝${RESET}"
  echo -e ""
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
  else
    echo "$json" | grep -oP '"name":\s*"\K[^"]+' | paste - <(echo "$json" | grep -oP '"browser_download_url":\s*"\K[^"]+') -d '|'
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

# Instalación de la GUI
install_gui() {
  log_step "CamillaDSP GUI"

  log_info "Consultando GitHub..."
  github_api_get "$CAMILLAGUI_REPO"

  local tag version
  tag=$(json_get "$GH_JSON" "tag_name")
  version="${tag#v}"
  log_info "Versión: ${version}"

  local assets_list
  assets_list=$(json_array_urls "$GH_JSON")

  local gui_dir="${INSTALL_BASE}/gui"

  if find_gui_asset "$assets_list"; then
    local asset_name="${FOUND_ASSET%%|*}"
    local asset_url="${FOUND_ASSET##*|}"
    log_info "Asset: ${asset_name}"

    local tmpdir=$(mktemp -d)
    local archive="${tmpdir}/${asset_name}"
    download_file "$asset_url" "$archive"

    local extract_dir="${tmpdir}/extracted"
    log_info "Extrayendo..."
    extract_archive "$archive" "$extract_dir"

    local config_backup=""
    if [ -f "${gui_dir}/config/camillagui.yml" ]; then
      config_backup=$(mktemp)
      cp "${gui_dir}/config/camillagui.yml" "$config_backup"
    fi
    
    [ -d "$gui_dir" ] && rm -rf "$gui_dir"
    cp -r "$extract_dir"/* "$gui_dir/"
    echo "$version" > "${gui_dir}/VERSION"
    
    if [ -n "$config_backup" ]; then
      mkdir -p "${gui_dir}/config"
      cp "$config_backup" "${gui_dir}/config/camillagui.yml"
      rm -f "$config_backup"
    else
      create_gui_config
    fi

    rm -rf "$tmpdir"
  else
    log_error "No se encontró bundle"
    return 1
  fi

  log_ok "GUI instalada"
  return 0
}

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

# Scripts de control
create_scripts() {
  log_step "Creando scripts"
  local scripts_dir="${INSTALL_BASE}/scripts"
  local logs_dir="${INSTALL_BASE}/logs"
  local pids_dir="${INSTALL_BASE}/pids"
  mkdir -p "$scripts_dir" "$logs_dir" "$pids_dir"

  cat > "${scripts_dir}/start_all.sh" << 'SCRIPT'
#!/bin/bash
PIDS=/home/user/camilladsp/pids
LOGS=/home/user/camilladsp/logs
ENGINE=/home/user/camilladsp/engine/camilladsp
CONFIG=/home/user/camilladsp/config/camilladsp.yml
GUI=/home/user/camilladsp/gui/camillagui_backend

start_svc() {
  local name=$1; shift
  local pid_file=$PIDS/$name.pid
  
  if [ -f $pid_file ]; then
    local old_pid=$(cat $pid_file 2>/dev/null)
    if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null
      sleep 1
    fi
    if kill -0 "$old_pid" 2>/dev/null; then
      kill -9 "$old_pid" 2>/dev/null
    fi
    rm -f $pid_file
  fi
  
  > "$LOGS/$name.log"
  setsid "$@" >> "$LOGS/$name.log" 2>&1 &
  local new_pid=$!
  echo $new_pid > $pid_file
  sleep 2
  
  if kill -0 "$new_pid" 2>/dev/null; then
    echo "  [OK] $name iniciado (PID $new_pid)"
  else
    echo "  [ERROR] $name no pudo iniciar"
  fi
}

echo "Iniciando CamillaDSP..."
start_svc engine $ENGINE $CONFIG -p 1234
sleep 2
start_svc gui $GUI --config /home/user/camilladsp/gui/config/camillagui.yml
echo ""
echo "  Abre: http://localhost:5005"
SCRIPT

  cat > "${scripts_dir}/stop_all.sh" << 'SCRIPT'
#!/bin/bash
PIDS=/home/user/camilladsp/pids
for svc in gui engine; do
  [ -f $PIDS/$svc.pid ] && kill $(cat $PIDS/$svc.pid) 2>/dev/null
done
echo "Detenido"
SCRIPT

  cat > "${scripts_dir}/status.sh" << 'SCRIPT'
#!/bin/bash
PIDS=/home/user/camilladsp/pids
echo "Estado:"
for svc in engine gui; do
  [ -f $PIDS/$svc.pid ] && kill -0 $(cat $PIDS/$svc.pid) 2>/dev/null && echo "  [ON] $svc" || echo "  [OFF] $svc"
done
SCRIPT

  chmod +x "${scripts_dir}"/*.sh
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
    device: default
    format: null
    type: Alsa
  capture_samplerate: 48000
  chunksize: 1024
  playback:
    channels: 2
    device: default
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

# Main
main() {
  header
  detect_system
  get_install_base

  log_info "Sistema: $(uname -s) $(uname -m)"
  log_info "Directorio: ${INSTALL_BASE}"

  if [ "$ARG_UPDATE" = "1" ]; then
    log_step "Modo actualización"
    if [ -f "${INSTALL_BASE}/scripts/stop_all.sh" ]; then
      bash "${INSTALL_BASE}/scripts/stop_all.sh" 2>/dev/null
      log_info "Servicios detenidos"
    fi
  fi

  # Instalar engine
  log_step "Instalando Engine..."
  install_engine
  ENGINE_OK=$?

  # Instalar GUI
  log_step "Instalando GUI..."
  install_gui
  GUI_OK=$?

  if [ "$ENGINE_OK" != "0" ] || [ "$GUI_OK" != "0" ]; then
    log_error "La instalación falló"
    exit 1
  fi

  # Crear config y scripts
  if [ "$ARG_UPDATE" != "1" ]; then
    create_default_config
    create_gui_config
  else
    if [ ! -f "${INSTALL_BASE}/gui/config/camillagui.yml" ]; then
      log_info "Creando configuración de GUI..."
      create_gui_config
    fi
  fi
  create_scripts

  # Asegurar que existen los directorios necesarios
  mkdir -p "${INSTALL_BASE}/config"
  mkdir -p "${INSTALL_BASE}/coeffs"
  mkdir -p "${INSTALL_BASE}/logs"
  mkdir -p "${INSTALL_BASE}/pids"
  mkdir -p "${INSTALL_BASE}/scripts"

  # Liberar puertos y detener servicios conflictivos antes de iniciar
  if [ "$ARG_NO_SERVICE" != "1" ]; then
    stop_conflicting_services
  fi

  # Iniciar servicios
  if [ "$ARG_NO_SERVICE" != "1" ]; then
    log_step "Iniciando servicios..."
    bash "${INSTALL_BASE}/scripts/start_all.sh"
    sleep 3
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
  echo -e "    ${CYAN}→ http://localhost:5005${RESET}"
  if [ -n "$host_ip" ]; then
    echo -e "    ${CYAN}→ http://${host_ip}:5005${RESET}"
  fi
  echo ""
}

main "$@"