#!/bin/bash
# Arranque robusto de CamillaDSP
# - Si capture device = inferno_rx: auto-incrementa PROCESS_ID, espera flujo Dante
# - Si capture device = otro: arranca directamente

CONFIG="/root/camilladsp/config/camilladsp.yml"
ASOUNDRC="/root/.asoundrc"
STATE_BASE="/root/.local/state/inferno_aoip"
ENGINE="/root/camilladsp/engine/camilladsp"

# Matar instancias previas del engine (no del servicio web)
pkill -9 -x camilladsp 2>/dev/null || true
sleep 2

# Leer dispositivo de captura del YAML activo
CAPTURE_DEV=$(python3 -c "
import sys
try:
    with open('$CONFIG') as f:
        for line in f:
            l = line.strip()
            if l.startswith('device:'):
                print(l.split(':', 1)[1].strip().strip('\"'))
                sys.exit(0)
except: pass
print('')
" 2>/dev/null)

echo "Capture device: '$CAPTURE_DEV'"

# Si no es inferno_rx, arrancar directamente con config
if [ "$CAPTURE_DEV" != "inferno_rx" ]; then
    echo "No es Dante, arrancando directamente"
    exec "$ENGINE" -p 1234 -a 0.0.0.0 "$CONFIG"
fi

# --- Modo Dante (inferno_rx) ---

# La BIND_IP configurada por el usuario en .asoundrc es siempre la fuente de verdad.
# eth0 solo se usa como fallback si no hay nada guardado.
SAVED_BIND=$(grep -oP 'BIND_IP\s+"\K[^"]+' "$ASOUNDRC" | head -1)

if [ -n "$SAVED_BIND" ]; then
    ETH_IP="$SAVED_BIND"
    echo "Usando BIND_IP configurada: $ETH_IP"
else
    # Sin configuración guardada: buscar primera IP disponible (cualquier interfaz)
    ETH_IP=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | grep -v '^127\.' | head -1)
    if [ -n "$ETH_IP" ]; then
        echo "WARN: sin BIND_IP en .asoundrc, usando primera IP detectada: $ETH_IP"
        sed -i "s/BIND_IP \"[^\"]*\"/BIND_IP \"$ETH_IP\"/g" "$ASOUNDRC"
    else
        echo "WARN: sin IP disponible, arrancando con null"
        python3 -c "
import re; txt=open('$CONFIG').read()
txt=re.sub(r'(device:\s*)\"?inferno_\S+\"?',r'\1\"null\"',txt)
open('/tmp/camilladsp_nulldante.yml','w').write(txt)
"
        exec "$ENGINE" -p 1234 -a 0.0.0.0 /tmp/camilladsp_nulldante.yml
    fi
fi

# Calcular hex de IP para directorio de estado inferno
IP_HEX=$(python3 -c "
import socket, struct
n = struct.unpack('>I', socket.inet_aton('$ETH_IP'))[0]
print('0000' + format(n, '08x'))
")

echo "Dante: IP=$ETH_IP hex=$IP_HEX"

# Si hay otras interfaces en la misma subred que BIND_IP, bajarlas para que
# el kernel no las use en lugar de la interfaz Dante elegida
DANTE_IFACE=$(ip -4 addr show | awk -v ip="$ETH_IP" '
    /^[0-9]+:/ { iface=$2; sub(/:$/, "", iface) }
    /inet / { if (index($2, ip"/") == 1) print iface }
')
BIND_PREFIX=$(echo "$ETH_IP" | cut -d. -f1-3)
if [ -n "$DANTE_IFACE" ]; then
    echo "Interfaz Dante: $DANTE_IFACE ($ETH_IP)"
    ip -4 addr show | awk '/^[0-9]+:/{iface=$2; sub(/:$/,"",iface)} /inet /{print iface, $2}' | \
    while read iface cidr; do
        [ "$iface" = "$DANTE_IFACE" ] && continue
        [ "$iface" = "lo" ] && continue
        iface_prefix=$(echo "$cidr" | cut -d. -f1-3)
        if [ "$iface_prefix" = "$BIND_PREFIX" ]; then
            ip link set "$iface" down 2>/dev/null && echo "Interfaz $iface bajada (conflicto de subred con $DANTE_IFACE)"
        fi
    done
fi

# Buscar el directorio más reciente con suscripciones configuradas (tx_hostname)
SUBSCRIPTIONS_SRC=""
while IFS= read -r d; do
    if grep -q "tx_hostname" "$d/rx_subscriptions.toml" 2>/dev/null; then
        SUBSCRIPTIONS_SRC="$d/rx_subscriptions.toml"
        break
    fi
done < <(ls -dt "$STATE_BASE"/*/ 2>/dev/null)

if [ -z "$SUBSCRIPTIONS_SRC" ]; then
    echo "WARN: no hay rx_subscriptions configuradas, arrancando con null"
    python3 -c "
import re; txt=open('$CONFIG').read()
txt=re.sub(r'(device:\s*)\"?inferno_\S+\"?',r'\1\"null\"',txt)
open('/tmp/camilladsp_nulldante.yml','w').write(txt)
"
    exec "$ENGINE" -p 1234 -a 0.0.0.0 /tmp/camilladsp_nulldante.yml
fi
echo "Subscriptions: $SUBSCRIPTIONS_SRC"

# Leer PROCESS_ID actual del bloque inferno_rx
current=$(awk '/pcm.inferno_rx/,/^\}/' "$ASOUNDRC" | grep 'PROCESS_ID' | grep -o '[0-9]*' | head -1)
if [ -z "$current" ]; then current=1000; fi
new=$((current + 1))

# Actualizar PROCESS_ID en .asoundrc
sed -i "/pcm\.inferno_rx/,/^\}/ s/PROCESS_ID \"$current\"/PROCESS_ID \"$new\"/" "$ASOUNDRC"
echo "PROCESS_ID: $current -> $new"

# Crear directorio de estado para el nuevo PROCESS_ID y limpiar obsoletos
new_hex=$(printf "%04x" $new)
new_dir="${STATE_BASE}/${IP_HEX}${new_hex}"
mkdir -p "$new_dir"
cp "$SUBSCRIPTIONS_SRC" "$new_dir/rx_subscriptions.toml"

# Borrar todos los directorios excepto el recién creado
find "$STATE_BASE" -mindepth 1 -maxdepth 1 -type d ! -path "$new_dir" -exec rm -rf {} + 2>/dev/null || true
echo "Directorios inferno limpiados, activo: $new_dir"

# Verificar si hay flujo Dante disponible (max 8s)
# El plugin inferno_rx necesita ~2s para resolver mDNS y abrir el stream.
# Si "Recording WAVE" aparece en stderr, el dispositivo abrió correctamente.
DANTE_FLUJO=0
echo "Verificando flujo Dante..."
for i in 1 2 3 4; do
    err=$(timeout 2 arecord -D inferno_rx -r 48000 -f S32_LE -c 2 -d 1 /dev/null 2>&1)
    if echo "$err" | grep -q "Recording WAVE"; then
        DANTE_FLUJO=1
        break
    fi
    echo "Intento $i: sin flujo Dante aún, esperando..."
    sleep 2
done

if [ "$DANTE_FLUJO" -eq 1 ]; then
    echo "Flujo Dante detectado, arrancando CamillaDSP con inferno_rx (PROCESS_ID=$new)"
    # Esperar que hw:1,0 quede libre (max 15s)
    for i in $(seq 1 5); do
        if ! grep -rl 'pcmC1D0' /proc/*/fd 2>/dev/null | grep -q .; then
            break
        fi
        echo "Esperando que hw:1,0 quede libre ($i)..."
        sleep 3
    done
    exec "$ENGINE" -p 1234 -a 0.0.0.0 "$CONFIG"
fi

# Sin flujo Dante: arrancar con null para que el engine quede activo
TMPCONFIG="/tmp/camilladsp_nulldante.yml"
python3 -c "
import re
txt = open('$CONFIG').read()
txt = re.sub(r'(device:\s*)\"?inferno_\S+\"?', r'\1\"null\"', txt)
open('$TMPCONFIG', 'w').write(txt)
"
echo "Sin flujo Dante, arrancando con null (PROCESS_ID=$new). Recargar preset cuando haya flujo."

# Esperar que hw:1,0 quede libre (max 15s)
for i in $(seq 1 5); do
    if ! grep -rl 'pcmC1D0' /proc/*/fd 2>/dev/null | grep -q .; then
        break
    fi
    echo "Esperando que hw:1,0 quede libre ($i)..."
    sleep 3
done

exec "$ENGINE" -p 1234 -a 0.0.0.0 "$TMPCONFIG"
