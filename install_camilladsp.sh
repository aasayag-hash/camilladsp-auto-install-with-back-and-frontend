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

# Desmutear ALSA
unmute_alsa() {
  log_step "Desmuteando tarjetas de sonido ALSA (prevención de seguridad de Linux)..."
  if command -v amixer >/dev/null 2>&1; then
    for card in $(aplay -l 2>/dev/null | grep '^card' | awk '{print $2}' | sed 's/://g' | sort -u); do
      amixer -c $card sset Master playback 100% unmute >/dev/null 2>&1 || true
      amixer -c $card sset PCM playback 100% unmute >/dev/null 2>&1 || true
      amixer -c $card sset Speaker playback 100% unmute >/dev/null 2>&1 || true
      amixer -c $card sset Front playback 100% unmute >/dev/null 2>&1 || true
      # Activar captura de Linea pero silenciar la reproducción (anula el hardware loopback/monitoring)
      amixer -c $card sset Line capture 100% unmute >/dev/null 2>&1 || true
      amixer -c $card sset Line playback 0% mute >/dev/null 2>&1 || true
    done
    log_ok "Tarjetas desmuteadas y loopback deshabilitado."
  else
    log_warn "Comando amixer no encontrado. ALSA podría seguir en silencio."
  fi
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
  setsid "\$@" >> "\$LOGS/\$name.log" 2>&1 &
  local new_pid=\$!
  echo \$new_pid > \$pid_file
  sleep 2

  if kill -0 "\$new_pid" 2>/dev/null; then
    echo "  [OK] \$name iniciado (PID \$new_pid)"
  else
    echo "  [ERROR] \$name no pudo iniciar"
  fi
}

echo "Iniciando CamillaDSP..."
start_svc engine \$ENGINE -p ${ENGINE_WS_PORT} -a 0.0.0.0 -w
sleep 2
start_svc gui \$GUI --config ${INSTALL_BASE}/gui/config/camillagui.yml
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

  # Iniciar servicios
  if [ "$ARG_NO_SERVICE" != "1" ]; then
    log_step "Iniciando servicios..."
    bash "${INSTALL_BASE}/scripts/start_all.sh"
    sleep 3
  fi

  # Configurar arranque automático al inicio del sistema
  if [ "$ARG_NO_SERVICE" != "1" ] && [ "$ARG_UPDATE" != "1" ]; then
    log_step "Configurando autostart..."
    setup_autostart
  fi

  # Asegurar de que ningún dispositivo o tarjeta de sonido USB inicia muteado desde Linux nativamente
  unmute_alsa

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