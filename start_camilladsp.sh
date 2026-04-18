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

# Detectar IP de eth0; si no hay, usar la última BIND_IP configurada en .asoundrc
ETH_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1)
SAVED_BIND=$(grep -oP 'BIND_IP\s+"\K[^"]+' "$ASOUNDRC" | head -1)

if [ -z "$ETH_IP" ]; then
    if [ -n "$SAVED_BIND" ]; then
        echo "WARN: eth0 sin IP, usando BIND_IP guardado: $SAVED_BIND"
        ETH_IP="$SAVED_BIND"
    else
        echo "WARN: eth0 sin IP y sin BIND_IP en .asoundrc, arrancando con null"
        python3 -c "
import re; txt=open('$CONFIG').read()
txt=re.sub(r'(device:\s*)\"?inferno_\S+\"?',r'\1\"null\"',txt)
open('/tmp/camilladsp_nulldante.yml','w').write(txt)
"
        exec "$ENGINE" -p 1234 -a 0.0.0.0 /tmp/camilladsp_nulldante.yml
    fi
else
    # Actualizar BIND_IP en .asoundrc si la IP de eth0 cambió
    if [ "$SAVED_BIND" != "$ETH_IP" ]; then
        sed -i "s/BIND_IP \"$SAVED_BIND\"/BIND_IP \"$ETH_IP\"/g" "$ASOUNDRC"
        echo "BIND_IP actualizado: $SAVED_BIND -> $ETH_IP"
    fi
fi

# Calcular hex de IP para directorio de estado inferno
IP_HEX=$(python3 -c "
import socket, struct
n = struct.unpack('>I', socket.inet_aton('$ETH_IP'))[0]
print('0000' + format(n, '08x'))
")

echo "Dante: IP=$ETH_IP hex=$IP_HEX"

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

# Generar config con device inferno reemplazado por null
TMPCONFIG="/tmp/camilladsp_nulldante.yml"
python3 -c "
import re
txt = open('$CONFIG').read()
txt = re.sub(r'(device:\s*)\"?inferno_\S+\"?', r'\1\"null\"', txt)
open('$TMPCONFIG', 'w').write(txt)
"
echo "Arrancando CamillaDSP con null en lugar de Dante (PROCESS_ID=$new, IP=$ETH_IP)"
echo "Cuando haya flujo Dante, recargar el preset desde la UI"

# Esperar que hw:1,0 quede libre verificando via /proc (max 15s)
for i in $(seq 1 5); do
    if ! grep -rl 'pcmC1D0' /proc/*/fd 2>/dev/null | grep -q .; then
        break
    fi
    echo "Esperando que hw:1,0 quede libre ($i)..."
    sleep 3
done

exec "$ENGINE" -p 1234 -a 0.0.0.0 "$TMPCONFIG"
