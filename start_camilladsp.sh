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

# La BIND_IP del .asoundrc es la fuente de verdad. Puede ser una IP o un nombre de interfaz.
# inferno acepta ambos; usamos el nombre de interfaz para que el multicast mDNS
# salga por la interfaz correcta independientemente del enrutamiento del kernel.
SAVED_BIND=$(grep -oP 'BIND_IP\s+"\K[^"]+' "$ASOUNDRC" | head -1)

resolve_iface_to_ip() {
    # Si el argumento ya es una IP, devolverla; si es un nombre de interfaz, resolver su IP
    local val="$1"
    if echo "$val" | grep -qP '^\d+\.\d+\.\d+\.\d+$'; then
        echo "$val"
    else
        ip -4 addr show dev "$val" 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1
    fi
}

if [ -n "$SAVED_BIND" ]; then
    DANTE_IFACE_OR_IP="$SAVED_BIND"
    ETH_IP=$(resolve_iface_to_ip "$SAVED_BIND")
    echo "Usando BIND_IP configurada: $SAVED_BIND (IP: $ETH_IP)"
    if [ -z "$ETH_IP" ]; then
        echo "WARN: interfaz '$SAVED_BIND' sin IP, arrancando con null"
        python3 -c "
import re; txt=open('$CONFIG').read()
txt=re.sub(r'(device:\s*)\"?inferno_\S+\"?',r'\1\"null\"',txt)
open('/tmp/camilladsp_nulldante.yml','w').write(txt)
"
        exec "$ENGINE" -p 1234 -a 0.0.0.0 /tmp/camilladsp_nulldante.yml
    fi
else
    # Sin configuración: detectar primera interfaz disponible y guardar su nombre
    DANTE_IFACE_OR_IP=$(ip -4 addr show 2>/dev/null | awk '/^[0-9]+:/{iface=$2; sub(/:$/,"",iface)} /inet / && iface!="lo"{print iface; exit}')
    ETH_IP=$(resolve_iface_to_ip "$DANTE_IFACE_OR_IP")
    if [ -n "$ETH_IP" ]; then
        echo "WARN: sin BIND_IP en .asoundrc, usando interfaz detectada: $DANTE_IFACE_OR_IP ($ETH_IP)"
        sed -i "/pcm\.inferno_rx/,/^\}/ s/BIND_IP \"[^\"]*\"/BIND_IP \"$DANTE_IFACE_OR_IP\"/" "$ASOUNDRC"
        sed -i "/pcm\.inferno_tx/,/^\}/ s/BIND_IP \"[^\"]*\"/BIND_IP \"$DANTE_IFACE_OR_IP\"/" "$ASOUNDRC"
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

echo "Dante: interfaz=$DANTE_IFACE_OR_IP IP=$ETH_IP hex=$IP_HEX"

echo "Interfaz Dante: $DANTE_IFACE_OR_IP ($ETH_IP)"

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
