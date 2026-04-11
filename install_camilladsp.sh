#!/usr/bin/env bash
# ==============================================================
#  CamillaDSP — Instalador Automático
#  Engine  +  GUI Backend  +  Frontend
#
#  Uso:
#    bash install_camilladsp.sh              # instalación interactiva
#    bash install_camilladsp.sh --update     # actualizar sin preguntar
#    bash install_camilladsp.sh --uninstall  # desinstalar todo
#    bash install_camilladsp.sh --check      # solo verificar estado
#    bash install_camilladsp.sh --dir /ruta  # directorio personalizado
# ==============================================================

set -eo pipefail

SCRIPT_VERSION="1.0.0"

# ── Repositorios GitHub ───────────────────────────────────────
CAMILLADSP_REPO="HEnquist/camilladsp"
CAMILLAGUI_REPO="HEnquist/camillagui-backend"

# ── Puertos por defecto ───────────────────────────────────────
ENGINE_WS_PORT=1234
GUI_HTTP_PORT=5005

# ── Argumentos ───────────────────────────────────────────────
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
    --dir)        shift; ARG_DIR="$1" ;;
    -h|--help)
      echo "Uso: bash install_camilladsp.sh [opciones]"
      echo ""
      echo "Opciones:"
      echo "  --update        Actualizar a la última versión sin preguntar"
      echo "  --uninstall     Desinstalar CamillaDSP completamente"
      echo "  --check         Solo verificar el estado de la instalación"
      echo "  --dir <ruta>    Directorio de instalación personalizado"
      echo "  --no-service    No crear servicios del sistema (systemd/launchd)"
      echo ""
      echo "Ejemplos:"
      echo "  bash install_camilladsp.sh"
      echo "  bash install_camilladsp.sh --update"
      echo "  bash install_camilladsp.sh --dir /opt/camilladsp"
      exit 0
      ;;
  esac
done

# ══════════════════════════════════════════════════════════════
#  COLORES Y UTILIDADES
# ══════════════════════════════════════════════════════════════

if [ -t 1 ]; then
  RESET="\033[0m";  BOLD="\033[1m"
  RED="\033[91m";   GREEN="\033[92m"
  YELLOW="\033[93m"; BLUE="\033[94m"; CYAN="\033[96m"
else
  RESET=""; BOLD=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""
fi

log_info()  { echo -e "  ${BLUE}ℹ${RESET}  $*"; }
log_ok()    { echo -e "  ${GREEN}✔${RESET}  $*"; }
log_warn()  { echo -e "  ${YELLOW}⚠${RESET}  $*"; }
log_error() { echo -e "  ${RED}✖${RESET}  $*" >&2; }
log_step()  { echo -e "\n${CYAN}${BOLD}▶  $*${RESET}"; }
hr()        { echo -e "  ${CYAN}──────────────────────────────────────────────────────${RESET}"; }

get_local_ip() {
  local ip=""
  if command -v hostname &>/dev/null; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi
  if [ -z "$ip" ] && command -v ip &>/dev/null; then
    ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K[0-9.]+' | head -1)
  fi
  echo "$ip"
}

header() {
  echo -e ""
  echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════╗"
  echo -e "║         CamillaDSP  ─  Instalador Automático             ║"
  echo -e "║    Engine  +  GUI Backend  +  Frontend                   ║"
  printf  "║                                         v%-19s║\n" "$SCRIPT_VERSION"
  echo -e "╚══════════════════════════════════════════════════════════╝${RESET}"
  echo -e ""
}

ask() {
  # Uso: ask "¿Pregunta?" [s|n]   → retorna 0=sí 1=no
  local prompt="$1"
  local default="${2:-s}"
  local opts="[S/n]"
  [ "$default" = "n" ] && opts="[s/N]"
  while true; do
    printf "  ${YELLOW}?${RESET}  %s %s: " "$prompt" "$opts"
    read -r resp
    resp=$(echo "$resp" | tr '[:upper:]' '[:lower:]')
    [ -z "$resp" ] && resp="$default"
    case "$resp" in
      s|si|y|yes) return 0 ;;
      n|no)       return 1 ;;
      *) echo "     Responde s (sí) o n (no)." ;;
    esac
  done
}

ask_choice() {
  # Uso: ask_choice "Pregunta" "a:Opción A" "b:Opción B" ...
  # Retorna la letra elegida en $REPLY_CHOICE
  local prompt="$1"; shift
  echo -e "  ${YELLOW}?${RESET}  $prompt"
  local -a keys=()
  for item in "$@"; do
    local key="${item%%:*}"
    local desc="${item#*:}"
    keys+=("$key")
    echo -e "     [${BOLD}${key^^}${RESET}] $desc"
  done
  while true; do
    printf "     Opción: "
    read -r resp
    resp=$(echo "$resp" | tr '[:upper:]' '[:lower:]')
    for k in "${keys[@]}"; do
      [ "$resp" = "$k" ] && { REPLY_CHOICE="$resp"; return 0; }
    done
    echo "     Opción inválida. Elige: $(IFS=,; echo "${keys[*]^^}")"
  done
}

# ══════════════════════════════════════════════════════════════
#  DETECCIÓN DE SISTEMA
# ══════════════════════════════════════════════════════════════

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

# ══════════════════════════════════════════════════════════════
#  HERRAMIENTAS: DESCARGA Y JSON
# ══════════════════════════════════════════════════════════════

# Seleccionar herramienta de descarga
DOWNLOADER=""
if command -v curl &>/dev/null; then
  DOWNLOADER="curl"
elif command -v wget &>/dev/null; then
  DOWNLOADER="wget"
fi

download_file() {
  # Uso: download_file <url> <destino>
  local url="$1"
  local dest="$2"
  log_info "Descargando: $(basename "$dest")"
  case "$DOWNLOADER" in
    curl)
      curl -L --progress-bar \
           -H "User-Agent: CamillaDSP-Installer/$SCRIPT_VERSION" \
           -o "$dest" "$url"
      ;;
    wget)
      wget --progress=bar:force \
           --header="User-Agent: CamillaDSP-Installer/$SCRIPT_VERSION" \
           -O "$dest" "$url" 2>&1
      ;;
    *)
      log_error "Se necesita 'curl' o 'wget'. Instala uno de ellos y vuelve a intentar."
      return 1
      ;;
  esac
}

github_api_get() {
  # Obtiene JSON de la API de GitHub y lo guarda en $GH_JSON
  local repo="$1"
  local url="https://api.github.com/repos/${repo}/releases/latest"
  
  if [ "$DOWNLOADER" = "curl" ]; then
    GH_JSON=$(curl -s \
      -H "User-Agent: CamillaDSP-Installer/$SCRIPT_VERSION" \
      -H "Accept: application/vnd.github.v3+json" \
      "$url") || { log_error "Error al consultar GitHub API."; return 1; }
  else
    GH_JSON=$(wget -q -O- \
      --header="User-Agent: CamillaDSP-Installer/$SCRIPT_VERSION" \
      --header="Accept: application/vnd.github.v3+json" \
      "$url") || { log_error "Error al consultar GitHub API."; return 1; }
  fi
  [ -z "$GH_JSON" ] && { log_error "Respuesta vacía de GitHub API."; return 1; }
}

# Parser JSON — usa jq si está disponible, Python como fallback
json_get() {
  # Uso: json_get <json_string> <campo>  → imprime el valor
  local json="$1"
  local field="$2"
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r ".$field // empty"
  elif command -v python3 &>/dev/null; then
    python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('$field',''))" "$json"
  elif command -v python &>/dev/null; then
    python -c "import json,sys; d=json.loads(sys.argv[1]); print(d.get('$field',''))" "$json"
  else
    echo "$json" | grep -oP "\"${field}\"\\s*:\\s*\"\\K[^\"]*" | head -1
  fi
}

json_array_urls() {
  # Extrae los browser_download_url y name de assets[] → líneas "nombre|url"
  local json="$1"
  if command -v jq &>/dev/null; then
    echo "$json" | jq -r '.assets[] | "\(.name)|\(.browser_download_url)"'
  elif command -v python3 &>/dev/null; then
    python3 - "$json" <<'PYEOF'
import json, sys
try:
    data = json.loads(sys.argv[1])
    for a in data.get("assets", []):
        print(f"{a['name']}|{a['browser_download_url']}")
except Exception as e:
    sys.exit(1)
PYEOF
  elif command -v python &>/dev/null; then
    python - "$json" <<'PYEOF'
import json, sys
try:
    data = json.loads(sys.argv[1])
    for a in data.get("assets", []):
        print("{0}|{1}".format(a["name"], a["browser_download_url"]))
except Exception:
    sys.exit(1)
PYEOF
  else
    # Fallback básico con grep
    echo "$json" | grep -oP '"name":\s*"\K[^"]+' | paste - \
      <(echo "$json" | grep -oP '"browser_download_url":\s*"\K[^"]+') -d '|'
  fi
}

# ══════════════════════════════════════════════════════════════
#  SELECCIÓN DE ASSETS
# ══════════════════════════════════════════════════════════════

find_engine_asset() {
  # Busca el asset del engine para $OS_NAME / $ARCH
  # Retorna "nombre|url" en $FOUND_ASSET
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

  # Preferir el binario "plain" sin sufijo de audio backend
  # Patrón: camilladsp-{os}-{arch}.ext
  while IFS= read -r line; do
    local name="${line%%|*}"
    local lower_name
    lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    # Coincidencia exacta OS + ARCH sin audio backend
    if echo "$lower_name" | grep -qE "camilladsp-${os_key}-${ARCH}${ext//./\\.}"; then
      FOUND_ASSET="$line"
      return 0
    fi
  done <<< "$assets_list"

  # Segundo intento: solo OS + ARCH (puede tener backend de audio)
  while IFS= read -r line; do
    local name="${line%%|*}"
    local lower_name
    lower_name=$(echo "$name" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_name" | grep -q "$os_key" && \
       echo "$lower_name" | grep -q "$ARCH"  && \
       echo "$lower_name" | grep -q "${ext}"; then
      FOUND_ASSET="$line"
      return 0
    fi
  done <<< "$assets_list"

  return 1
}

find_gui_asset() {
  # Busca el bundle de la GUI para $OS_NAME / $ARCH
  # Retorna "nombre|url" en $FOUND_ASSET
  FOUND_ASSET=""
  local assets_list="$1"
  local os_key
  case "$OS_NAME" in
    linux)   os_key="linux" ;;
    darwin)  os_key="macos" ;;
    windows) os_key="windows" ;;
    *)       os_key="$OS_NAME" ;;
  esac

  # Buscar bundle_{os}_{arch}
  while IFS= read -r line; do
    local lower_name
    lower_name=$(echo "${line%%|*}" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_name" | grep -q "bundle_${os_key}_${ARCH}"; then
      FOUND_ASSET="$line"
      return 0
    fi
  done <<< "$assets_list"

  # Fallback: cualquier bundle para este OS
  while IFS= read -r line; do
    local lower_name
    lower_name=$(echo "${line%%|*}" | tr '[:upper:]' '[:lower:]')
    if echo "$lower_name" | grep -q "bundle" && \
       echo "$lower_name" | grep -q "$os_key"; then
      FOUND_ASSET="$line"
      return 0
    fi
  done <<< "$assets_list"

  return 1
}

# ══════════════════════════════════════════════════════════════
#  DETECCIÓN DE VERSIONES INSTALADAS
# ══════════════════════════════════════════════════════════════

detect_engine_version() {
  INSTALLED_ENGINE_PATH=""
  INSTALLED_ENGINE_VER=""
  local binary
  [ "$OS_NAME" = "windows" ] && binary="camilladsp.exe" || binary="camilladsp"
  local candidates=(
    "${INSTALL_BASE}/engine/${binary}"
    "$HOME/.local/bin/${binary}"
    "/usr/local/bin/${binary}"
    "/usr/bin/${binary}"
  )
  for path in "${candidates[@]}"; do
    if [ -x "$path" ]; then
      INSTALLED_ENGINE_PATH="$path"
      INSTALLED_ENGINE_VER=$("$path" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
      [ -z "$INSTALLED_ENGINE_VER" ] && INSTALLED_ENGINE_VER="desconocida"
      return 0
    fi
  done
  # Buscar en PATH
  if command -v camilladsp &>/dev/null; then
    INSTALLED_ENGINE_PATH=$(command -v camilladsp)
    INSTALLED_ENGINE_VER=$(camilladsp --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    [ -z "$INSTALLED_ENGINE_VER" ] && INSTALLED_ENGINE_VER="desconocida"
    return 0
  fi
  return 1
}

detect_gui_version() {
  INSTALLED_GUI_PATH=""
  INSTALLED_GUI_VER=""
  local candidates=(
    "${INSTALL_BASE}/gui"
    "$HOME/camillagui"
    "$HOME/.local/share/camillagui"
  )
  for path in "${candidates[@]}"; do
    if [ -f "${path}/main.py" ]; then
      INSTALLED_GUI_PATH="$path"
      if [ -f "${path}/VERSION" ]; then
        INSTALLED_GUI_VER=$(cat "${path}/VERSION")
      else
        INSTALLED_GUI_VER="desconocida"
      fi
      return 0
    fi
  done
  return 1
}

# ══════════════════════════════════════════════════════════════
#  EXTRACCIÓN DE ARCHIVOS
# ══════════════════════════════════════════════════════════════

extract_archive() {
  local archive="$1"
  local dest="$2"
  mkdir -p "$dest"
  case "$archive" in
    *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest" ;;
    *.tar.xz)        tar -xJf "$archive" -C "$dest" ;;
    *.zip)           unzip -q "$archive" -d "$dest" ;;
    *)
      log_error "Formato no soportado: $(basename "$archive")"
      return 1
      ;;
  esac
}

# ══════════════════════════════════════════════════════════════
#  INSTALACIÓN DEL ENGINE
# ══════════════════════════════════════════════════════════════

install_engine() {
  log_step "CamillaDSP Engine"

  [ -z "$DOWNLOADER" ] && {
    log_error "Se requiere 'curl' o 'wget'. Instala uno y vuelve a intentar."
    return 1
  }

  local engine_dir="${INSTALL_BASE}/engine"
  [ -d "$engine_dir" ] && {
    log_info "Limpiando instalación previa del engine..."
    rm -rf "$engine_dir"
  }

  log_info "Consultando GitHub para la última versión del engine..."
  github_api_get "$CAMILLADSP_REPO" || return 1

  local tag version
  tag=$(json_get "$GH_JSON" "tag_name")
  version="${tag#v}"
  log_info "Última versión disponible: ${GREEN}${tag}${RESET}"

  local assets_list
  assets_list=$(json_array_urls "$GH_JSON")

  FOUND_ASSET=""
  find_engine_asset "$assets_list" || {
    log_error "No se encontró paquete para ${OS_NAME}/${ARCH}."
    log_error "Descarga manual: https://github.com/HEnquist/camilladsp/releases"
    return 1
  }

  local asset_name="${FOUND_ASSET%%|*}"
  local asset_url="${FOUND_ASSET##*|}"
  log_info "Asset seleccionado: ${BOLD}${asset_name}${RESET}"

  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  local archive="${tmpdir}/${asset_name}"
  download_file "$asset_url" "$archive" || return 1

  local extract_dir="${tmpdir}/extracted"
  log_info "Extrayendo archivos..."
  extract_archive "$archive" "$extract_dir" || return 1

  # Buscar el binario dentro del archivo extraído
  local binary="camilladsp"
  [ "$OS_NAME" = "windows" ] && binary="camilladsp.exe"
  local src_binary
  src_binary=$(find "$extract_dir" -name "$binary" -type f | head -1)
  if [ -z "$src_binary" ]; then
    src_binary=$(find "$extract_dir" -name "camilladsp*" -type f | head -1)
  fi
  [ -z "$src_binary" ] && {
    log_error "No se encontró el binario dentro del archivo descargado."
    return 1
  }

  local engine_dir="${INSTALL_BASE}/engine"
  mkdir -p "$engine_dir"
  cp "$src_binary" "${engine_dir}/${binary}"
  chmod +x "${engine_dir}/${binary}"
  echo "$version" > "${engine_dir}/VERSION"
  log_ok "Engine instalado: ${engine_dir}/${binary}"

  # Crear symlink en ~/.local/bin
  if [ "$OS_NAME" != "windows" ]; then
    local local_bin="$HOME/.local/bin"
    mkdir -p "$local_bin"
    local symlink="${local_bin}/${binary}"
    [ -L "$symlink" ] && rm -f "$symlink"
    ln -sf "${engine_dir}/${binary}" "$symlink" \
      && log_ok "Symlink creado: ${symlink}" \
      || log_warn "No se pudo crear symlink. Agrega '${engine_dir}' al PATH."
  fi

  # Configuración por defecto
  local config_dir="${INSTALL_BASE}/config"
  mkdir -p "$config_dir"
  local config_file="${config_dir}/camilladsp.yml"
  if [ ! -f "$config_file" ]; then
    create_default_engine_config "$config_file"
    log_ok "Configuración por defecto: ${config_file}"
  else
    log_info "Configuración existente preservada: ${config_file}"
  fi

  return 0
}

create_default_engine_config() {
  local config_file="$1"
  local device_type="Alsa"
  local device_name='"hw:0,0"'
  case "$OS_NAME" in
    darwin)  device_type="CoreAudio"; device_name='""' ;;
    windows) device_type="Wasapi";    device_name='""' ;;
  esac
  cat > "$config_file" << EOF
---
# Configuración básica de CamillaDSP
# Documentación: https://github.com/HEnquist/camilladsp

devices:
  samplerate: 44100
  chunksize: 1024
  capture:
    type: ${device_type}
    channels: 2
    device: ${device_name}
    format: S32LE
  playback:
    type: ${device_type}
    channels: 2
    device: ${device_name}
    format: S32LE

filters: {}
pipeline: []
EOF
}

# ══════════════════════════════════════════════════════════════
#  INSTALACIÓN DE LA GUI
# ══════════════════════════════════════════════════════════════

install_gui() {
  log_step "CamillaDSP GUI (Backend + Frontend)"

  local gui_dir="${INSTALL_BASE}/gui"
  [ -d "$gui_dir" ] && {
    log_info "Limpiando instalación previa de la GUI..."
    rm -rf "$gui_dir"
  }

  # Verificar Python
  local python_exec=""
  for cmd in python3 python; do
    if command -v "$cmd" &>/dev/null; then
      local ver
      ver=$("$cmd" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
      local major="${ver%%.*}"
      local minor="${ver##*.}"
      if [ "${major:-0}" -eq 3 ] && [ "${minor:-0}" -ge 8 ]; then
        python_exec="$cmd"
        break
      fi
    fi
  done
  [ -z "$python_exec" ] && {
    log_error "Python 3.8+ es requerido para la GUI. Instala desde https://python.org"
    return 1
  }
  log_info "Python encontrado: ${python_exec} ($($python_exec --version 2>&1))"

  log_info "Consultando GitHub para la última versión de la GUI..."
  github_api_get "$CAMILLAGUI_REPO" || return 1

  local tag version
  tag=$(json_get "$GH_JSON" "tag_name")
  version="${tag#v}"
  local zipball_url
  zipball_url=$(json_get "$GH_JSON" "zipball_url")
  log_info "Última versión disponible: ${GREEN}${tag}${RESET}"

  local assets_list
  assets_list=$(json_array_urls "$GH_JSON")

  local gui_dir="${INSTALL_BASE}/gui"
  local asset_name asset_url use_zipball=0

  FOUND_ASSET=""
  if find_gui_asset "$assets_list"; then
    asset_name="${FOUND_ASSET%%|*}"
    asset_url="${FOUND_ASSET##*|}"
    log_info "Asset seleccionado: ${BOLD}${asset_name}${RESET}"
  else
    log_warn "No se encontró bundle para ${OS_NAME}/${ARCH}. Usando código fuente..."
    asset_name="camillagui-backend-${version}.zip"
    asset_url="$zipball_url"
    use_zipball=1
  fi

  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' RETURN

  local archive="${tmpdir}/${asset_name}"
  download_file "$asset_url" "$archive" || return 1

  local extract_dir="${tmpdir}/extracted"
  log_info "Extrayendo archivos..."
  extract_archive "$archive" "$extract_dir" || return 1

  # El zipball de GitHub envuelve en un subdirectorio (HEnquist-camillagui-backend-xxxx/)
  local src_dir="$extract_dir"
  if [ ! -f "${extract_dir}/main.py" ]; then
    local subdir
    subdir=$(find "$extract_dir" -maxdepth 1 -mindepth 1 -type d | head -1)
    [ -n "$subdir" ] && src_dir="$subdir"
  fi

  # Respaldar configuración existente
  local config_backup=""
  if [ -d "${gui_dir}/config" ]; then
    config_backup="${tmpdir}/config_backup"
    cp -r "${gui_dir}/config" "$config_backup"
    log_info "Configuración de GUI respaldada."
  fi

  # Instalar archivos
  cp -r "$src_dir" "$gui_dir"

  # Si usamos zipball, intentar descargar el frontend por separado
  if [ "$use_zipball" = "1" ]; then
    local frontend_url=""
    while IFS= read -r line; do
      local lower_name
      lower_name=$(echo "${line%%|*}" | tr '[:upper:]' '[:lower:]')
      if [ "$lower_name" = "camillagui.zip" ]; then
        frontend_url="${line##*|}"
        break
      fi
    done <<< "$assets_list"
    if [ -n "$frontend_url" ]; then
      log_info "Descargando frontend (camillagui.zip)..."
      local fe_archive="${tmpdir}/camillagui.zip"
      download_file "$frontend_url" "$fe_archive" && \
        extract_archive "$fe_archive" "${gui_dir}/static" && \
        log_ok "Frontend instalado."
    fi
  fi

  # Restaurar configuración
  if [ -n "$config_backup" ] && [ -d "$config_backup" ]; then
    [ -d "${gui_dir}/config" ] && rm -rf "${gui_dir}/config"
    cp -r "$config_backup" "${gui_dir}/config"
    log_ok "Configuración de GUI restaurada."
  fi

  log_ok "GUI instalada: ${gui_dir}"

  # Instalar dependencias Python
  local req_file="${gui_dir}/requirements.txt"
  if [ -f "$req_file" ]; then
    log_info "Instalando dependencias Python..."
    if $python_exec -m pip install -r "$req_file" --quiet; then
      log_ok "Dependencias Python instaladas."
    else
      log_warn "Algunos paquetes no se instalaron. Revisa manualmente:"
      log_warn "  $python_exec -m pip install -r $req_file"
    fi
  fi

  # Crear configuración de la GUI
  setup_gui_config "$gui_dir"

  # Guardar versión
  echo "$version" > "${gui_dir}/VERSION"
  return 0
}

setup_gui_config() {
  local gui_dir="$1"
  local config_dir="${gui_dir}/config"
  mkdir -p "$config_dir"
  local cfg="${config_dir}/camillagui.yml"
  [ -f "$cfg" ] && return 0
  local engine_cfg="${INSTALL_BASE}/config/camilladsp.yml"
  local coeff_dir="${INSTALL_BASE}/coeffs"
  mkdir -p "$coeff_dir"
  cat > "$cfg" << EOF
---
# Configuración de CamillaDSP GUI
# Generado por install_camilladsp.sh

camilla_host: "localhost"
camilla_port: ${ENGINE_WS_PORT}

port: ${GUI_HTTP_PORT}
ssl_certificate: null
ssl_private_key: null

config_dir:     "${INSTALL_BASE}/config"
coeff_dir:      "${coeff_dir}"
default_config: "${engine_cfg}"

update_config: false
hide_capture_samplerate: false
supported_capture_types: null
supported_playback_types: null
EOF
  log_ok "Configuración GUI: ${cfg}"
}

# ══════════════════════════════════════════════════════════════
#  SCRIPTS DE INICIO / PARADA
# ══════════════════════════════════════════════════════════════

create_scripts() {
  log_step "Creando scripts de inicio/parada"
  local scripts_dir="${INSTALL_BASE}/scripts"
  local logs_dir="${INSTALL_BASE}/logs"
  local pids_dir="${INSTALL_BASE}/pids"
  mkdir -p "$scripts_dir" "$logs_dir" "$pids_dir"

  local engine_bin="${INSTALL_BASE}/engine/camilladsp"
  local config_file="${INSTALL_BASE}/config/camilladsp.yml"
  local gui_dir="${INSTALL_BASE}/gui"
  local gui_bin="${gui_dir}/camillagui_backend"

  # ── start_all.sh ─────────────────────────────────────────
  cat > "${scripts_dir}/start_all.sh" << SCRIPT
#!/usr/bin/env bash
PIDS="${pids_dir}"
LOGS="${logs_dir}"

start_svc() {
  local name="\$1"; shift
  local pid_file="\${PIDS}/\${name}.pid"
  if [ -f "\$pid_file" ] && kill -0 "\$(cat "\$pid_file")" 2>/dev/null; then
    echo "  [WARN] \$name ya está corriendo (PID \$(cat "\$pid_file"))"
    return
  fi
  "\$@" >> "\${LOGS}/\${name}.log" 2>&1 &
  echo \$! > "\$pid_file"
  echo "  [OK]   \$name iniciado (PID \$!)"
}

echo "Iniciando CamillaDSP..."
start_svc engine  "${engine_bin}" "${config_file}" -p ${ENGINE_WS_PORT}
sleep 1
start_svc gui  "${gui_bin}" --config "${gui_dir}/config/camillagui.yml"
echo ""
echo "  Abre tu navegador en: http://localhost:${GUI_HTTP_PORT}"
echo "  Logs en: ${logs_dir}/"
SCRIPT

  # ── stop_all.sh ──────────────────────────────────────────
  cat > "${scripts_dir}/stop_all.sh" << SCRIPT
#!/usr/bin/env bash
PIDS="${pids_dir}"

stop_svc() {
  local pid_file="\${PIDS}/\$1.pid"
  [ -f "\$pid_file" ] || { echo "  [-]  \$1: sin PID guardado"; return; }
  local pid; pid=\$(cat "\$pid_file")
  if kill -0 "\$pid" 2>/dev/null; then
    kill "\$pid" && echo "  [OK] \$1 detenido (PID \$pid)"
  else
    echo "  [-]  \$1 ya estaba detenido"
  fi
  rm -f "\$pid_file"
}

echo "Deteniendo CamillaDSP..."
stop_svc gui
stop_svc engine
echo "Listo."
SCRIPT

  # ── status.sh ────────────────────────────────────────────
  cat > "${scripts_dir}/status.sh" << SCRIPT
#!/usr/bin/env bash
PIDS="${pids_dir}"

check_svc() {
  local pid_file="\${PIDS}/\$1.pid"
  if [ -f "\$pid_file" ] && kill -0 "\$(cat "\$pid_file")" 2>/dev/null; then
    echo "  [ON]  \$1  CORRIENDO  (PID \$(cat "\$pid_file"))"
  else
    echo "  [OFF] \$1  DETENIDO"
  fi
}

echo ""
echo "Estado de CamillaDSP:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_svc engine
check_svc gui

if command -v systemctl &>/dev/null; then
  echo ""
  echo "Servicios systemd:"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if systemctl --user is-active camilladsp-engine &>/dev/null; then
    echo "  [ON]  systemd: camilladsp-engine.service"
  else
    echo "  [OFF] systemd: camilladsp-engine.service"
  fi
  if systemctl --user is-active camilladsp-gui &>/dev/null; then
    echo "  [ON]  systemd: camilladsp-gui.service"
  else
    echo "  [OFF] systemd: camilladsp-gui.service"
  fi
fi
echo ""
SCRIPT

  chmod +x "${scripts_dir}/start_all.sh" \
           "${scripts_dir}/stop_all.sh"  \
           "${scripts_dir}/status.sh"

  log_ok "Scripts creados: ${scripts_dir}/"
  log_info "  start_all.sh  → inicia Engine + GUI"
  log_info "  stop_all.sh   → detiene los servicios"
  log_info "  status.sh     → muestra el estado"
}

# ══════════════════════════════════════════════════════════════
#  SERVICIOS DEL SISTEMA
# ══════════════════════════════════════════════════════════════

create_system_services() {
  case "$OS_NAME" in
    linux)  create_systemd ;;
    darwin) create_launchd ;;
    *)      log_warn "Servicios del sistema no soportados en ${OS_NAME}." ;;
  esac
}

create_systemd() {
  log_step "Configurando servicios systemd (usuario)"
  local svc_dir="$HOME/.config/systemd/user"
  mkdir -p "$svc_dir"

  local engine_bin="${INSTALL_BASE}/engine/camilladsp"
  local config_file="${INSTALL_BASE}/config/camilladsp.yml"
  local gui_dir="${INSTALL_BASE}/gui"
  local gui_bin="${gui_dir}/camillagui_backend"
  local logs_dir="${INSTALL_BASE}/logs"

  cat > "${svc_dir}/camilladsp-engine.service" << EOF
[Unit]
Description=CamillaDSP Engine
After=sound.target

[Service]
Type=simple
ExecStart=${engine_bin} ${config_file} -p ${ENGINE_WS_PORT}
Restart=on-failure
RestartSec=5
StandardOutput=append:${logs_dir}/engine.log
StandardError=append:${logs_dir}/engine.log

[Install]
WantedBy=default.target
EOF

  cat > "${svc_dir}/camilladsp-gui.service" << EOF
[Unit]
Description=CamillaDSP GUI Backend
After=network.target camilladsp-engine.service

[Service]
Type=simple
WorkingDirectory=${gui_dir}
ExecStart=${gui_bin} --config ${gui_dir}/config/camillagui.yml
Restart=on-failure
RestartSec=5
StandardOutput=append:${logs_dir}/gui.log
StandardError=append:${logs_dir}/gui.log

[Install]
WantedBy=default.target
EOF

  systemctl --user daemon-reload 2>/dev/null && \
    log_ok "Servicios systemd creados y recargados." || \
    log_warn "Ejecuta: systemctl --user daemon-reload"

  log_info "Para inicio automático al arranque:"
  log_info "  systemctl --user enable camilladsp-engine.service"
  log_info "  systemctl --user enable camilladsp-gui.service"
}

create_launchd() {
  log_step "Configurando LaunchAgents (macOS)"
  local agents_dir="$HOME/Library/LaunchAgents"
  mkdir -p "$agents_dir"

  local engine_bin="${INSTALL_BASE}/engine/camilladsp"
  local config_file="${INSTALL_BASE}/config/camilladsp.yml"
  local gui_dir="${INSTALL_BASE}/gui"
  local gui_bin="${gui_dir}/camillagui_backend"
  local logs_dir="${INSTALL_BASE}/logs"

  cat > "${agents_dir}/com.camilladsp.engine.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.camilladsp.engine</string>
  <key>ProgramArguments</key>
  <array>
    <string>${engine_bin}</string>
    <string>${config_file}</string>
    <string>-p</string><string>${ENGINE_WS_PORT}</string>
  </array>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>${logs_dir}/engine.log</string>
  <key>StandardErrorPath</key><string>${logs_dir}/engine.log</string>
</dict>
</plist>
EOF

  cat > "${agents_dir}/com.camilladsp.gui.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.camilladsp.gui</string>
  <key>ProgramArguments</key>
  <array>
    <string>${gui_bin}</string>
    <string>--config</string>
    <string>${gui_dir}/config/camillagui.yml</string>
  </array>
  <key>WorkingDirectory</key><string>${gui_dir}</string>
  <key>RunAtLoad</key><false/>
  <key>KeepAlive</key><false/>
  <key>StandardOutPath</key><string>${logs_dir}/gui.log</string>
  <key>StandardErrorPath</key><string>${logs_dir}/gui.log</string>
</dict>
</plist>
EOF

  log_ok "Plists LaunchAgent creados."
  log_info "Para cargar:"
  log_info "  launchctl load ${agents_dir}/com.camilladsp.engine.plist"
  log_info "  launchctl load ${agents_dir}/com.camilladsp.gui.plist"
}

# ══════════════════════════════════════════════════════════════
#  VERIFICACIÓN
# ══════════════════════════════════════════════════════════════

is_port_open() {
  local port="$1"
  (echo >/dev/tcp/localhost/"$port") &>/dev/null 2>&1
}

verify_installation() {
  log_step "Verificación de la instalación"
  local all_ok=0
  local binary="camilladsp"
  [ "$OS_NAME" = "windows" ] && binary="camilladsp.exe"

  # Engine
  local engine_bin="${INSTALL_BASE}/engine/${binary}"
  if [ -x "$engine_bin" ]; then
    local ver
    ver=$("$engine_bin" --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    log_ok "Engine instalado  v${ver:-?}  →  ${engine_bin}"
  else
    log_error "Engine NO encontrado: ${engine_bin}"
    all_ok=1
  fi

  # GUI
  if [ -f "${INSTALL_BASE}/gui/main.py" ]; then
    local ver=""
    [ -f "${INSTALL_BASE}/gui/VERSION" ] && ver=$(cat "${INSTALL_BASE}/gui/VERSION")
    log_ok "GUI instalada     v${ver:-?}  →  ${INSTALL_BASE}/gui"
  else
    log_error "GUI NO encontrada: ${INSTALL_BASE}/gui"
    all_ok=1
  fi

  # Configuración
  if [ -f "${INSTALL_BASE}/config/camilladsp.yml" ]; then
    log_ok "Configuración     →  ${INSTALL_BASE}/config/camilladsp.yml"
  else
    log_warn "Configuración no encontrada."
  fi

  # Servicios
  echo ""
  log_info "Estado de servicios:"
  if is_port_open "$ENGINE_WS_PORT"; then
    log_ok "  Engine  CORRIENDO  (ws://localhost:${ENGINE_WS_PORT})"
  else
    log_warn "  Engine  DETENIDO   (puerto ${ENGINE_WS_PORT} no responde)"
    log_info "  Para iniciar: ${INSTALL_BASE}/scripts/start_all.sh"
  fi
  if is_port_open "$GUI_HTTP_PORT"; then
    log_ok "  GUI     CORRIENDO  →  http://localhost:${GUI_HTTP_PORT}"
  else
    log_warn "  GUI     DETENIDA   (puerto ${GUI_HTTP_PORT} no responde)"
  fi

  hr
  [ "$all_ok" -eq 0 ] && log_ok "Instalación sin errores." || \
    log_error "La instalación tiene problemas. Revisa los mensajes anteriores."
  return "$all_ok"
}

# ══════════════════════════════════════════════════════════════
#  DESINSTALACIÓN
# ══════════════════════════════════════════════════════════════

uninstall_all() {
  log_step "Desinstalando CamillaDSP"

  if [ ! -d "$INSTALL_BASE" ]; then
    log_warn "No se encontró instalación en: ${INSTALL_BASE}"
    return 1
  fi

  ask "¿Eliminar toda la instalación en '${INSTALL_BASE}'?" "n" || {
    log_info "Desinstalación cancelada."
    return 0
  }

  ask "¿Conservar archivos de configuración?" "s" && KEEP_CFG=1 || KEEP_CFG=0

  # Detener servicios
  stop_services_for_uninstall

  # Respaldar config
  if [ "$KEEP_CFG" = "1" ] && [ -d "${INSTALL_BASE}/config" ]; then
    local backup="$HOME/camilladsp_config_backup"
    cp -r "${INSTALL_BASE}/config" "$backup"
    log_ok "Configuración respaldada en: ${backup}"
  fi

  rm -rf "$INSTALL_BASE"
  log_ok "Directorio eliminado: ${INSTALL_BASE}"

  # Eliminar symlink
  local sym="$HOME/.local/bin/camilladsp"
  [ -L "$sym" ] && rm -f "$sym" && log_ok "Symlink eliminado: ${sym}"

  # Eliminar servicios del sistema
  if [ "$OS_NAME" = "linux" ]; then
    local svc_dir="$HOME/.config/systemd/user"
    for svc in camilladsp-engine.service camilladsp-gui.service; do
      systemctl --user disable "$svc" 2>/dev/null || true
      rm -f "${svc_dir}/${svc}"
    done
    systemctl --user daemon-reload 2>/dev/null || true
    log_ok "Servicios systemd eliminados."
  elif [ "$OS_NAME" = "darwin" ]; then
    local agents="$HOME/Library/LaunchAgents"
    for plist in com.camilladsp.engine.plist com.camilladsp.gui.plist; do
      launchctl unload "${agents}/${plist}" 2>/dev/null || true
      rm -f "${agents}/${plist}"
    done
    log_ok "Plists LaunchAgent eliminados."
  fi

  log_ok "CamillaDSP desinstalado correctamente."
}

stop_services_for_uninstall() {
  local stop_script="${INSTALL_BASE}/scripts/stop_all.sh"
  [ -x "$stop_script" ] && bash "$stop_script" 2>/dev/null || true
  if [ "$OS_NAME" = "linux" ]; then
    systemctl --user stop camilladsp-gui.service   2>/dev/null || true
    systemctl --user stop camilladsp-engine.service 2>/dev/null || true
  elif [ "$OS_NAME" = "darwin" ]; then
    local agents="$HOME/Library/LaunchAgents"
    launchctl unload "${agents}/com.camilladsp.gui.plist"    2>/dev/null || true
    launchctl unload "${agents}/com.camilladsp.engine.plist" 2>/dev/null || true
  fi
}

# ══════════════════════════════════════════════════════════════
#  GENERACIÓN DEL README
# ══════════════════════════════════════════════════════════════

generate_readme() {
  log_step "Generando README_INSTALACION.md"

  local readme_path
  readme_path="$(pwd)/README_INSTALACION.md"

  local engine_ver="N/A"
  detect_engine_version && engine_ver="${INSTALLED_ENGINE_VER}" || true
  local gui_ver="N/A"
  detect_gui_version    && gui_ver="${INSTALLED_GUI_VER}" || true

  local now; now=$(date '+%Y-%m-%d %H:%M')
  local os_display="Linux"
  [ "$OS_NAME" = "darwin" ]  && os_display="macOS"
  [ "$OS_NAME" = "windows" ] && os_display="Windows"

  local start_script="${INSTALL_BASE}/scripts/start_all.sh"
  local stop_script="${INSTALL_BASE}/scripts/stop_all.sh"
  local binary="camilladsp"

  cat > "$readme_path" << HEREDOC
# CamillaDSP — Guía de Instalación y Uso

> **Generado automáticamente** por \`install_camilladsp.sh\` v${SCRIPT_VERSION}
> Fecha: ${now} | Sistema: ${os_display} (${ARCH})

---

## ¿Qué es CamillaDSP?

**CamillaDSP** es un motor de procesamiento de señal de audio (DSP) de alto rendimiento:
- Filtros paramétricos (ecualizador PEQ)
- Compresores dinámicos
- Crossovers de orden alto
- Convolución FIR/IIR (corrección de sala)
- Mezcla y enrutamiento de canales

La **GUI web** permite configurar y controlar el engine desde cualquier navegador.

---

## Componentes instalados

| Componente          | Versión       | Ruta                             |
|---------------------|---------------|----------------------------------|
| CamillaDSP Engine   | ${engine_ver} | \`${INSTALL_BASE}/engine\`       |
| GUI Backend+Frontend| ${gui_ver}    | \`${INSTALL_BASE}/gui\`          |
| Configuración       | —             | \`${INSTALL_BASE}/config\`       |
| Scripts             | —             | \`${INSTALL_BASE}/scripts\`      |
| Logs                | —             | \`${INSTALL_BASE}/logs\`         |

---

## Cómo descargar

### Opción 1 — Instalador automático (recomendado)

\`\`\`bash
# Clonar el repositorio
git clone https://github.com/aasayag-hash/camilladsp-EQ-comp-GUI.git
cd camilladsp-EQ-comp-GUI

# Ejecutar el instalador
bash install_camilladsp.sh
\`\`\`

### Opción 2 — Descarga manual

| Componente | URL |
|---|---|
| Engine     | https://github.com/HEnquist/camilladsp/releases |
| GUI        | https://github.com/HEnquist/camillagui-backend/releases |

**Archivos por sistema operativo:**

| Sistema             | Archivo Engine                          | Archivo GUI                        |
|---------------------|-----------------------------------------|------------------------------------|
| Linux x86-64        | \`camilladsp-linux-amd64.tar.gz\`       | \`bundle_linux_amd64.tar.gz\`      |
| Linux ARM64         | \`camilladsp-linux-aarch64.tar.gz\`     | \`bundle_linux_aarch64.tar.gz\`    |
| macOS Apple Silicon | \`camilladsp-macos-aarch64.tar.gz\`     | \`bundle_macos_aarch64.tar.gz\`    |
| macOS Intel         | \`camilladsp-macos-amd64.tar.gz\`       | \`bundle_macos_amd64.tar.gz\`      |
| Windows 64-bit      | \`camilladsp-windows-amd64.zip\`        | \`bundle_windows_amd64.zip\`       |

---

## Cómo instalar

### Instalación automática

\`\`\`bash
bash install_camilladsp.sh
\`\`\`

**Requisitos:**
- \`curl\` o \`wget\`
- Python 3.8+ (para la GUI)
- \`tar\` / \`unzip\`
- Conexión a internet

**El instalador hace automáticamente:**
1. Detecta el OS y la arquitectura del procesador
2. Consulta GitHub y descarga la última versión
3. Si hay versión instalada, pregunta si actualizar o mantener
4. Instala el engine y la GUI
5. Instala dependencias Python
6. Crea archivos de configuración por defecto
7. Genera scripts de inicio/parada
8. Opcionalmente configura servicios del sistema (systemd / launchd)
9. Verifica que todo esté correcto

---

## Cómo iniciar los servicios

### Inicio rápido

\`\`\`bash
${start_script}
\`\`\`

### Inicio manual paso a paso

\`\`\`bash
# Paso 1 — Iniciar el Engine
${INSTALL_BASE}/engine/${binary} \\
    ${INSTALL_BASE}/config/camilladsp.yml \\
    -p ${ENGINE_WS_PORT}

# Paso 2 — Iniciar la GUI (en otra terminal)
cd ${INSTALL_BASE}/gui
python3 main.py
\`\`\`

### Inicio automático al arranque del sistema

**Linux (systemd):**
\`\`\`bash
# Habilitar para inicio automático
systemctl --user enable camilladsp-engine.service
systemctl --user enable camilladsp-gui.service

# Iniciar ahora
systemctl --user start camilladsp-engine.service
systemctl --user start camilladsp-gui.service

# Ver estado
systemctl --user status camilladsp-engine.service
systemctl --user status camilladsp-gui.service
\`\`\`

**macOS (LaunchAgent):**
\`\`\`bash
launchctl load ~/Library/LaunchAgents/com.camilladsp.engine.plist
launchctl load ~/Library/LaunchAgents/com.camilladsp.gui.plist
\`\`\`

---

## Dónde abrir la interfaz gráfica

Con los servicios en marcha, abre el navegador en:

\`\`\`
http://localhost:${GUI_HTTP_PORT}
\`\`\`

> Si accedes desde otro equipo en la misma red, cambia \`localhost\`
> por la IP del servidor. Ejemplo: \`http://192.168.1.10:${GUI_HTTP_PORT}\`

### Puertos utilizados

| Servicio          | Protocolo | Puerto | Dirección                          |
|-------------------|-----------|--------|------------------------------------|
| CamillaDSP Engine | WebSocket | ${ENGINE_WS_PORT}  | \`ws://localhost:${ENGINE_WS_PORT}\`  |
| GUI (interfaz)    | HTTP      | ${GUI_HTTP_PORT}  | \`http://localhost:${GUI_HTTP_PORT}\` |

---

## Cómo parar los servicios

\`\`\`bash
${stop_script}
\`\`\`

O con systemctl (Linux):
\`\`\`bash
systemctl --user stop camilladsp-gui.service
systemctl --user stop camilladsp-engine.service
\`\`\`

---

## Cómo actualizar

\`\`\`bash
bash install_camilladsp.sh --update
\`\`\`

Detecta la versión instalada, descarga la más reciente y la reemplaza conservando la configuración.

---

## Cómo desinstalar

\`\`\`bash
bash install_camilladsp.sh --uninstall
\`\`\`

El proceso:
1. Pregunta si conservar la configuración
2. Detiene los servicios activos
3. Elimina los archivos instalados
4. Elimina los servicios del sistema (systemd / launchd)
5. Elimina los enlaces simbólicos del PATH

---

## Estructura de archivos

\`\`\`
${INSTALL_BASE}/
├── engine/
│   ├── camilladsp          ← binario del engine
│   └── VERSION
├── gui/
│   ├── main.py             ← entrada de la GUI
│   ├── requirements.txt
│   ├── config/
│   │   └── camillagui.yml  ← configuración de la GUI
│   └── ...
├── config/
│   └── camilladsp.yml      ← configuración del engine
├── coeffs/                 ← filtros de convolución (.wav, .txt)
├── logs/
│   ├── engine.log
│   └── gui.log
├── pids/                   ← archivos PID de los procesos
└── scripts/
    ├── start_all.sh
    ├── stop_all.sh
    └── status.sh
\`\`\`

---

## Verificar el estado

\`\`\`bash
bash install_camilladsp.sh --check
\`\`\`

---

## Solución de problemas

### La GUI no carga en el navegador

\`\`\`bash
# Ver estado de los servicios
${INSTALL_BASE}/scripts/status.sh

# Ver logs
tail -50 ${INSTALL_BASE}/logs/gui.log
tail -50 ${INSTALL_BASE}/logs/engine.log

# Verificar que el puerto ${GUI_HTTP_PORT} esté libre
ss -tlnp | grep ${GUI_HTTP_PORT}
\`\`\`

### La GUI no conecta con el Engine

Edita \`${INSTALL_BASE}/gui/config/camillagui.yml\` y verifica:
- \`camilla_host: "localhost"\`
- \`camilla_port: ${ENGINE_WS_PORT}\`

### Error de permisos de audio (Linux)

\`\`\`bash
sudo usermod -aG audio \$USER
# Cerrar sesión y volver a entrar
\`\`\`

---

## Recursos

| Recurso                  | URL |
|--------------------------|-----|
| CamillaDSP (engine)      | https://github.com/HEnquist/camilladsp |
| CamillaGUI (interfaz)    | https://github.com/HEnquist/camillagui-backend |
| Documentación oficial    | https://henquist.github.io/camilladsp/ |
| Wiki                     | https://github.com/HEnquist/camilladsp/wiki |
| Discusiones / soporte    | https://github.com/HEnquist/camilladsp/discussions |

---

*Generado por \`install_camilladsp.sh\` v${SCRIPT_VERSION} — ${now}*
HEREDOC

  log_ok "Documentación generada: ${readme_path}"
}

# ══════════════════════════════════════════════════════════════
#  FLUJO PRINCIPAL
# ══════════════════════════════════════════════════════════════

main() {
  header

  detect_system
  get_install_base

  log_info "Sistema detectado: ${BOLD}$(uname -s) $(uname -r) ($(uname -m)) → ${OS_NAME}/${ARCH}${RESET}"
  log_info "Directorio de instalación: ${BOLD}${INSTALL_BASE}${RESET}"
  hr

  # ── Modo solo verificación ────────────────────────────────
  if [ "$ARG_CHECK" = "1" ]; then
    verify_installation
    exit $?
  fi

  # ── Modo desinstalación ───────────────────────────────────
  if [ "$ARG_UNINSTALL" = "1" ]; then
    uninstall_all
    exit 0
  fi

  # ── Detectar instalaciones previas ───────────────────────
  DO_ENGINE=1
  DO_GUI=1
  ENGINE_INSTALLED=0
  GUI_INSTALLED=0

  if detect_engine_version; then
    ENGINE_INSTALLED=1
    log_warn "Engine ya instalado: ${BOLD}v${INSTALLED_ENGINE_VER}${RESET}  (${INSTALLED_ENGINE_PATH})"
    if [ "$ARG_UPDATE" = "1" ]; then
      log_info "Modo --update: el engine se actualizará."
    else
      ask_choice "¿Qué hacer con el engine?" \
        "a:Actualizar a la última versión" \
        "m:Mantener versión actual"        \
        "d:Desinstalar solo el engine"
      case "$REPLY_CHOICE" in
        m) DO_ENGINE=0; log_info "Engine: se mantiene la versión actual." ;;
        d) rm -rf "${INSTALL_BASE}/engine"; log_ok "Engine desinstalado."; DO_ENGINE=0 ;;
      esac
    fi
  fi

  if detect_gui_version; then
    GUI_INSTALLED=1
    log_warn "GUI ya instalada: ${BOLD}v${INSTALLED_GUI_VER}${RESET}  (${INSTALLED_GUI_PATH})"
    if [ "$ARG_UPDATE" = "1" ]; then
      log_info "Modo --update: la GUI se actualizará."
    else
      ask_choice "¿Qué hacer con la GUI?" \
        "a:Actualizar a la última versión" \
        "m:Mantener versión actual"        \
        "d:Desinstalar solo la GUI"
      case "$REPLY_CHOICE" in
        m) DO_GUI=0; log_info "GUI: se mantiene la versión actual." ;;
        d) rm -rf "${INSTALL_BASE}/gui"; log_ok "GUI desinstalada."; DO_GUI=0 ;;
      esac
    fi
  fi

  if [ "$ARG_UPDATE" = "1" ] && [ "$ENGINE_INSTALLED" = "0" ] && [ "$GUI_INSTALLED" = "0" ]; then
    log_info "No se detectó instalación previa. Se realizará una instalación nueva."
  fi

  # ── Instalación ───────────────────────────────────────────
  ENGINE_OK=0
  GUI_OK=0
  
  [ "$DO_ENGINE" = "1" ] && { install_engine && ENGINE_OK=1; }
  [ "$DO_GUI"    = "1" ] && { install_gui    && GUI_OK=1; }

  if [ "$ENGINE_OK" = "0" ] && [ "$GUI_OK" = "0" ] && \
     [ "$DO_ENGINE" = "1" ] && [ "$DO_GUI" = "1" ]; then
    log_error "La instalación falló. Ningún componente se instaló."
    exit 1
  fi

  # ── Scripts de inicio/parada ──────────────────────────────
  create_scripts

  # ── Servicios del sistema ─────────────────────────────────
  if [ "$ARG_NO_SERVICE" = "0" ] && [ "$OS_NAME" != "windows" ]; then
    if ask "¿Crear servicios del sistema para inicio automático?" "n"; then
      create_system_services
    fi
  fi

  # ── Verificación ──────────────────────────────────────────
  echo ""
  verify_installation || true

  # ── Iniciar servicios ─────────────────────────────────────
  if [ "$ENGINE_OK" = "1" ] || [ "$GUI_OK" = "1" ]; then
    echo ""
    bash "${INSTALL_BASE}/scripts/start_all.sh"
    log_info "Esperando que los servicios inicien..."
    sleep 4
    local local_ip
    local_ip=$(get_local_ip)
    if is_port_open "$GUI_HTTP_PORT"; then
      echo -e "  ${GREEN}✔${RESET}  GUI disponible"
      echo -e "  ${CYAN}  →  http://localhost:${GUI_HTTP_PORT}${RESET}"
      [ -n "$local_ip" ] && echo -e "  ${CYAN}  →  http://${local_ip}:${GUI_HTTP_PORT}${RESET}"
    else
      log_warn "La GUI aún no responde. Puede tardar unos segundos más."
      log_info "Intenta abrir: http://localhost:${GUI_HTTP_PORT}"
    fi
  fi

  # ── Generar README ────────────────────────────────────────
  generate_readme

  # ── Resumen final ─────────────────────────────────────────
  echo ""
  hr
  echo -e "\n  ${GREEN}${BOLD}✔  Instalación completada${RESET}\n"
  
  local local_ip
  local_ip=$(get_local_ip)
  
  echo -e "  ${GREEN}Todo listo. Abre en tu navegador:${RESET}"
  echo -e "\n  ${CYAN}  →  http://localhost:${GUI_HTTP_PORT}${RESET}"
  if [ -n "$local_ip" ]; then
    echo -e "  ${CYAN}  →  http://${local_ip}:${GUI_HTTP_PORT}${RESET}"
  fi
  echo ""
  echo -e "  Directorio: ${BOLD}${INSTALL_BASE}${RESET}"
  echo -e "  Docs:       ${BOLD}$(pwd)/README_INSTALACION.md${RESET}"
  echo -e "  Detener:    ${INSTALL_BASE}/scripts/stop_all.sh"
  echo ""
}

main
