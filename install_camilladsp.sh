#!/bin/bash
# ==============================================================
#  CamillaDSP — Instalador Automático
#  Engine  +  GUI Backend  +  Frontend
# ==============================================================

SCRIPT_VERSION="1.1.0"

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

  # Reemplazar ruta de instalación en server.py
  sed -i "s|INSTALL_BASE = \"/root/camilladsp\"|INSTALL_BASE = \"${INSTALL_BASE}\"|" "${web_dir}/server.py" 2>/dev/null || true
  sed -i "s|WEB_PORT     = 5000|WEB_PORT     = ${WEB_GUI_PORT}|" "${web_dir}/server.py" 2>/dev/null || true

  log_ok "Frontend Web instalado en ${web_dir}"
  return 0
}

# Scripts de control
create_scripts() {
  log_step "Creando scripts"
  local scripts_dir="${INSTALL_BASE}/scripts"
  local logs_dir="${INSTALL_BASE}/logs"
  local pids_dir="${INSTALL_BASE}/pids"
  mkdir -p "$scripts_dir" "$logs_dir" "$pids_dir"

  cat > "${scripts_dir}/start_all.sh" << SCRIPT
#!/bin/bash
PIDS=${INSTALL_BASE}/pids
LOGS=${INSTALL_BASE}/logs
ENGINE=${INSTALL_BASE}/engine/camilladsp
CONFIG=${INSTALL_BASE}/config/camilladsp.yml
GUI=${INSTALL_BASE}/gui/camillagui_backend

start_svc() {
  local name=\$1; shift
  local pid_file=\$PIDS/\$name.pid
  local max_retries=5
  local retry=0

  if [ -f \$pid_file ]; then
    local old_pid=\$(cat \$pid_file 2>/dev/null)
    if [ -n "\$old_pid" ] && kill -0 "\$old_pid" 2>/dev/null; then
      kill "\$old_pid" 2>/dev/null
      sleep 1
    fi
    if kill -0 "\$old_pid" 2>/dev/null; then
      kill -9 "\$old_pid" 2>/dev/null
    fi
    rm -f \$pid_file
  fi

  mkdir -p "\$LOGS" "\$PIDS"
  > "\$LOGS/\$name.log"

  while [ \$retry -lt \$max_retries ]; do
    setsid "\$@" >> "\$LOGS/\$name.log" 2>&1 &
    local new_pid=\$!
    echo \$new_pid > \$pid_file
    sleep 3

    if kill -0 "\$new_pid" 2>/dev/null; then
      echo "  [OK] \$name iniciado (PID \$new_pid)"
      return 0
    fi

    retry=\$((retry + 1))
    if [ \$retry -lt \$max_retries ]; then
      echo "  [WARN] \$name no pudo iniciar, reintentando (\$retry/\$max_retries)..."
      sleep 2
    fi
  done

  echo "  [ERROR] \$name no pudo iniciar"
  return 1
}

echo "Iniciando CamillaDSP..."
start_svc engine \$ENGINE -p ${ENGINE_WS_PORT} -a 0.0.0.0 -w
sleep 3
start_svc gui \$GUI --config ${INSTALL_BASE}/gui/config/camillagui.yml
sleep 2
# Liberar puerto del web server si está ocupado
fuser -k ${WEB_GUI_PORT}/tcp 2>/dev/null || true
sleep 1
start_svc web python3 ${INSTALL_BASE}/web/server.py
echo ""
echo "  GUI CamillaGUI: http://localhost:${GUI_HTTP_PORT}"
echo "  Web Console:    http://localhost:${WEB_GUI_PORT}"
SCRIPT

  cat > "${scripts_dir}/stop_all.sh" << SCRIPT
#!/bin/bash
PIDS=${INSTALL_BASE}/pids
for svc in web gui engine; do
  [ -f \$PIDS/\$svc.pid ] && kill \$(cat \$PIDS/\$svc.pid) 2>/dev/null
done
echo "Detenido"
SCRIPT

  cat > "${scripts_dir}/status.sh" << SCRIPT
#!/bin/bash
PIDS=${INSTALL_BASE}/pids
echo "Estado:"
for svc in engine gui web; do
  [ -f \$PIDS/\$svc.pid ] && kill -0 \$(cat \$PIDS/\$svc.pid) 2>/dev/null && echo "  [ON] \$svc" || echo "  [OFF] \$svc"
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

# Autostart al arranque del sistema
setup_autostart() {
  local base="${INSTALL_BASE}"
  local start_script="${base}/scripts/start_all.sh"

  # --- systemd (modo usuario) ---
  if command -v systemctl &>/dev/null; then
    local unit_dir="$HOME/.config/systemd/user"
    mkdir -p "$unit_dir"

    cat > "${unit_dir}/camilladsp.service" << EOF
[Unit]
Description=CamillaDSP + GUI + Web Console
After=network.target

[Service]
Type=forking
ExecStart=${start_script}
ExecStop=${base}/scripts/stop_all.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

    # Habilitar el servicio (requiere lingering para arranque sin sesión)
    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable camilladsp.service 2>/dev/null && \
      loginctl enable-linger "$(whoami)" 2>/dev/null || true
    log_ok "Autostart systemd habilitado (systemctl --user)"
    return 0
  fi

  # --- rc.local (fallback para sistemas sin systemd) ---
  local rc_local="/etc/rc.local"
  local marker="# camilladsp-autostart"

  if [ -f "$rc_local" ] || [ -d "/etc/rc.d" ]; then
    if ! grep -q "$marker" "$rc_local" 2>/dev/null; then
      # Insertar antes de 'exit 0' o al final
      if grep -q "^exit 0" "$rc_local" 2>/dev/null; then
        sed -i "s|^exit 0|${marker}\nbash ${start_script} &\n\nexit 0|" "$rc_local"
      else
        printf "\n%s\nbash %s &\n" "$marker" "$start_script" >> "$rc_local"
      fi
      chmod +x "$rc_local"
    fi
    log_ok "Autostart rc.local habilitado"
    return 0
  fi

  # --- cron @reboot (último recurso) ---
  if command -v crontab &>/dev/null; then
    local existing
    existing=$(crontab -l 2>/dev/null | grep -v "camilladsp-autostart" || true)
    printf "%s\n@reboot sleep 10 && bash %s  # camilladsp-autostart\n" \
      "$existing" "$start_script" | crontab -
    log_ok "Autostart cron @reboot habilitado"
    return 0
  fi

  log_warn "No se pudo configurar autostart (sin systemd, rc.local ni cron)"
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

  # ── 1. Detectar interfaz ethernet ──────────────────────────────────────────
  local eth_iface eth_ip
  eth_iface=$(ip -o link show | awk -F': ' '$2 !~ /^lo|^wl|^docker|^veth|^br/ {print $2; exit}')
  eth_ip=$(ip -4 addr show "$eth_iface" 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}' | head -1)

  if [ -z "$eth_ip" ]; then
    log_warn "No se detectó IP en $eth_iface — asegurate de tener Ethernet conectado"
    eth_ip="0.0.0.0"
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
  if ! command -v statime-inferno &>/dev/null && [ ! -f /usr/local/bin/statime-inferno ]; then
    log_info "Buscando statime-inferno en zip..."
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
      statime_bin=$(find "$tmp_dir" -name "statime-inferno" -type f | head -1)
      if [ -n "$statime_bin" ]; then
        sudo cp "$statime_bin" /usr/local/bin/statime-inferno
        sudo chmod +x /usr/local/bin/statime-inferno
        log_ok "statime-inferno instalado"
      else
        log_warn "statime-inferno no encontrado en el zip (opcional)"
      fi
      rm -rf "$tmp_dir"
    fi
  else
    log_ok "statime-inferno ya instalado"
  fi

  # ── 4. Configurar statime-inferno.toml ────────────────────────────────────
  local statime_cfg="/etc/statime-inferno.toml"
  if [ ! -f "$statime_cfg" ]; then
    sudo tee "$statime_cfg" > /dev/null << EOF
[port-configs.${eth_iface}]
announce-interval = 1
sync-interval = 0
delay-req-interval = 0
delay-mechanism = "E2E"
EOF
    log_ok "statime-inferno.toml creado ($eth_iface)"
  else
    # Actualizar interfaz si cambió
    sudo sed -i "s/^\[port-configs\.[^]]*\]/[port-configs.${eth_iface}]/" "$statime_cfg"
    log_ok "statime-inferno.toml actualizado (interfaz: $eth_iface)"
  fi

  # ── 5. Servicio systemd statime-inferno ────────────────────────────────────
  if [ ! -f /etc/systemd/system/statime-inferno.service ]; then
    sudo tee /etc/systemd/system/statime-inferno.service > /dev/null << 'EOF'
[Unit]
Description=statime PTP daemon for Dante/AES67
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/local/bin/statime-inferno -c /etc/statime-inferno.toml
Restart=always
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
    BIND_IP "${eth_ip}"
    SAMPLE_RATE "48000"
    RX_CHANNELS "2"
    TX_CHANNELS "0"
    PROCESS_ID "${rx_pid}"
    CLOCK_PATH "${ptp_socket}"
    RX_LATENCY_NS "1000000"
}

pcm.inferno_tx {
    type inferno
    BIND_IP "${eth_ip}"
    SAMPLE_RATE "48000"
    RX_CHANNELS "0"
    TX_CHANNELS "2"
    PROCESS_ID "1"
    ALT_PORT "8700"
    CLOCK_PATH "${ptp_socket}"
    RX_LATENCY_NS "1000000"
}
EOF
  log_ok ".asoundrc configurado (IP: $eth_ip)"

  # ── 8. Crear directorio de estado inferno_rx con suscripciones vacías ────
  local rx_dir="${INFERNO_STATE_BASE}/0000${ip_hex}$(printf '%04x' $rx_pid)"
  mkdir -p "$rx_dir"
  if [ ! -f "${rx_dir}/rx_subscriptions.toml" ]; then
    cat > "${rx_dir}/rx_subscriptions.toml" << 'EOF'
[[channels]]
local_channel_id = 1
local_channel_name = "RX 1"
tx_channel_name = "Dante Output 1"
tx_hostname = ""

[[channels]]
local_channel_id = 2
local_channel_name = "RX 2"
tx_channel_name = "Dante Output 2"
tx_hostname = ""
EOF
    log_ok "rx_subscriptions.toml creado (configurar hostname Dante en la web)"
  fi

  # ── 9. Instalar start_camilladsp.sh (arranque robusto) ──────────────────
  local start_script="${INSTALL_BASE}/start_camilladsp.sh"
  cat > "$start_script" << 'STARTSCRIPT'
#!/bin/bash
# Arranque robusto de CamillaDSP con inferno_rx (Dante via Ethernet)
# - Auto-detecta IP de eth0
# - Auto-incrementa PROCESS_ID para evitar error 1102 del P300
# - Verifica que el flujo Dante llegue antes de arrancar CamillaDSP

ASOUNDRC="$HOME/.asoundrc"
INFERNO_STATE="$HOME/.local/state/inferno_aoip"
ENGINE="/root/camilladsp/engine/camilladsp"
CONFIG="/root/camilladsp/config/camilladsp.yml"

# Detectar si la configuración activa usa inferno_rx
CAPTURE_DEV=$(grep -A5 'capture:' "$CONFIG" 2>/dev/null | grep 'device:' | head -1 | awk '{print $2}' | tr -d '"')

if [ "$CAPTURE_DEV" != "inferno_rx" ]; then
    # No es Dante, arrancar directo
    exec "$ENGINE" -p 1234 -a 0.0.0.0 -w
fi

# Modo Dante: auto-incrementar PROCESS_ID
ETH_IP=$(ip -4 addr show eth0 2>/dev/null | grep -o 'inet [0-9.]*' | awk '{print $2}' | head -1)
if [ -z "$ETH_IP" ]; then
    ETH_IP=$(ip -4 addr show | grep -o 'inet [0-9.]*' | awk 'NR==2{print $2}')
fi

# Calcular IP_HEX
IP_HEX=$(printf '%02x' $(echo "$ETH_IP" | tr '.' ' '))

# Obtener PROCESS_ID actual del .asoundrc
CURRENT_PID=$(grep -A10 'pcm.inferno_rx' "$ASOUNDRC" | grep 'PROCESS_ID' | head -1 | grep -o '[0-9]*')
NEW_PID=$((CURRENT_PID + 1))
NEW_PID_HEX=$(printf '%04x' $NEW_PID)

# Actualizar BIND_IP y PROCESS_ID en .asoundrc
sed -i "s/BIND_IP \"[^\"]*\"/BIND_IP \"$ETH_IP\"/g" "$ASOUNDRC"
# Actualizar solo el bloque inferno_rx
python3 - << EOF
import re
with open('$ASOUNDRC') as f: c = f.read()
c = re.sub(r'(pcm\.inferno_rx \{[^}]*PROCESS_ID\s+")[^"]+(")', r'\g<1>$NEW_PID\g<2>', c, flags=re.DOTALL)
with open('$ASOUNDRC', 'w') as f: f.write(c)
EOF

# Crear nuevo directorio de estado y copiar suscripciones
OLD_DIR=$(find "$INFERNO_STATE" -name "rx_subscriptions.toml" | xargs grep -l 'tx_hostname' 2>/dev/null | sort -r | head -1 | xargs dirname 2>/dev/null)
NEW_DIR="${INFERNO_STATE}/0000${IP_HEX}${NEW_PID_HEX}"
mkdir -p "$NEW_DIR"
[ -n "$OLD_DIR" ] && [ -f "${OLD_DIR}/rx_subscriptions.toml" ] && \
    cp "${OLD_DIR}/rx_subscriptions.toml" "${NEW_DIR}/rx_subscriptions.toml"

# Verificar que el hostname Dante está configurado
HOSTNAME=$(grep 'tx_hostname' "${NEW_DIR}/rx_subscriptions.toml" 2>/dev/null | grep -v '""' | head -1)
if [ -z "$HOSTNAME" ]; then
    echo "WARN: tx_hostname no configurado — arrancando CamillaDSP sin verificar flujo Dante"
    exec "$ENGINE" -p 1234 -a 0.0.0.0 -w
fi

# Esperar expiración del flujo anterior en P300 (4s keepalive + margen)
sleep 6

# Verificar que llega audio Dante (max 5 intentos de 2s)
FLOW_OK=0
for i in 1 2 3 4 5; do
    BYTES=$(arecord -D inferno_rx -f S32_LE -r 48000 -c 2 -d 2 2>/dev/null | wc -c)
    if [ "$BYTES" -gt 300000 ]; then
        FLOW_OK=1
        break
    fi
    sleep 2
done

if [ "$FLOW_OK" = "0" ]; then
    echo "WARN: No llegó audio Dante — arrancando igual (puede estar en silencio)"
fi

# Esperar expiración del flujo de prueba
sleep 6

exec "$ENGINE" -p 1234 -a 0.0.0.0 -w
STARTSCRIPT
  chmod +x "$start_script"

  # Reemplazar ruta del engine en el script
  sed -i "s|ENGINE=\"/root/camilladsp/engine/camilladsp\"|ENGINE=\"${INSTALL_BASE}/engine/camilladsp\"|" "$start_script"
  sed -i "s|CONFIG=\"/root/camilladsp/config/camilladsp.yml\"|CONFIG=\"${INSTALL_BASE}/config/camilladsp.yml\"|" "$start_script"

  log_ok "start_camilladsp.sh creado"

  # ── 10. Servicio camilladsp systemd (root, Restart=always) ───────────────
  sudo tee /etc/systemd/system/camilladsp.service > /dev/null << EOF
[Unit]
Description=CamillaDSP Audio Processor
After=network-online.target statime-inferno.service
Wants=network-online.target

[Service]
ExecStart=${start_script}
Restart=always
RestartSec=10
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
Restart=always
RestartSec=5
StandardOutput=null
StandardError=null

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

  if [ "$ARG_UPDATE" = "1" ]; then
    log_step "Modo actualización"
    if [ -f "${INSTALL_BASE}/scripts/stop_all.sh" ]; then
      bash "${INSTALL_BASE}/scripts/stop_all.sh" 2>/dev/null
      log_info "Servicios detenidos"
    fi
  fi

  # Liberar puertos y detener procesos anteriores para evitar el error "Text file busy" al copiar binarios
  if [ "$ARG_NO_SERVICE" != "1" ]; then
    stop_conflicting_services
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

  # Instalar Frontend Web
  install_web_frontend || true

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

  # ── Dante opcional ────────────────────────────────────────────────────────
  INSTALL_DANTE=0
  if [ "$ARG_UPDATE" != "1" ]; then
    if ask_dante; then
      INSTALL_DANTE=1
      install_dante || log_warn "Instalación Dante incompleta — ver mensajes anteriores"
    fi
  fi

  # Iniciar servicios
  if [ "$ARG_NO_SERVICE" != "1" ]; then
    if [ "$INSTALL_DANTE" = "1" ]; then
      log_step "Iniciando servicios con Dante..."
      sudo systemctl start camilladsp-web
      sudo systemctl start camilladsp
      sleep 5
      systemctl is-active --quiet camilladsp-web && log_ok "camilladsp-web activo" || log_warn "camilladsp-web no arrancó"
      systemctl is-active --quiet camilladsp      && log_ok "camilladsp activo"     || log_warn "camilladsp iniciando (arranca lento con Dante)"
    else
      log_step "Iniciando servicios..."
      bash "${INSTALL_BASE}/scripts/start_all.sh"
      sleep 3
    fi
  fi

  # Configurar arranque automático al inicio del sistema
  if [ "$ARG_NO_SERVICE" != "1" ] && [ "$ARG_UPDATE" != "1" ] && [ "$INSTALL_DANTE" != "1" ]; then
    log_step "Configurando autostart..."
    setup_autostart
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
  echo -e "    ${CYAN}CamillaGUI  → http://localhost:${GUI_HTTP_PORT}${RESET}"
  echo -e "    ${CYAN}Web Console → http://localhost:${WEB_GUI_PORT}${RESET}"
  if [ -n "$host_ip" ]; then
    echo -e "    ${CYAN}CamillaGUI  → http://${host_ip}:${GUI_HTTP_PORT}${RESET}"
    echo -e "    ${CYAN}Web Console → http://${host_ip}:${WEB_GUI_PORT}${RESET}"
  fi
  echo ""

  # Eliminar el directorio clonado del instalador
  if [ -n "$SCRIPT_DIR" ] && [ "$SCRIPT_DIR" != "/" ] && [ "$SCRIPT_DIR" != "$HOME" ] && [ "$SCRIPT_DIR" != "$INSTALL_BASE" ]; then
    log_step "Limpiando instalador..."
    rm -rf "$SCRIPT_DIR"
    log_ok "Directorio del instalador eliminado: $SCRIPT_DIR"
  fi
}

main "$@"