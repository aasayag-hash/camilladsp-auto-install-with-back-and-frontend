#!/bin/bash
# Arranque robusto de CamillaDSP
# - Si capture device = inferno_rx: auto-incrementa PROCESS_ID, espera flujo Dante
# - Si capture device = otro: arranca directamente

CONFIG="/root/camilladsp/config/camilladsp.yml"
ASOUNDRC="/root/.asoundrc"
STATE_BASE="/root/.local/state/inferno_aoip"
ENGINE="/root/camilladsp/engine/camilladsp"

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
        echo "WARN: eth0 sin IP y sin BIND_IP en .asoundrc, arrancando en modo espera"
        exec "$ENGINE" -p 1234 -a 0.0.0.0 -w
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
    echo "WARN: no hay rx_subscriptions configuradas, arrancando sin suscripciones Dante"
    exec "$ENGINE" -p 1234 -a 0.0.0.0 "$CONFIG"
fi
echo "Subscriptions: $SUBSCRIPTIONS_SRC"

# Leer PROCESS_ID actual del bloque inferno_rx
current=$(awk '/pcm.inferno_rx/,/^\}/' "$ASOUNDRC" | grep 'PROCESS_ID' | grep -o '[0-9]*' | head -1)
if [ -z "$current" ]; then current=1000; fi
new=$((current + 1))

# Actualizar PROCESS_ID en .asoundrc
sed -i "/pcm\.inferno_rx/,/^\}/ s/PROCESS_ID \"$current\"/PROCESS_ID \"$new\"/" "$ASOUNDRC"
echo "PROCESS_ID: $current -> $new"

# Crear directorio de estado para el nuevo PROCESS_ID
new_hex=$(printf "%04x" $new)
new_dir="${STATE_BASE}/${IP_HEX}${new_hex}"
mkdir -p "$new_dir"
cp "$SUBSCRIPTIONS_SRC" "$new_dir/rx_subscriptions.toml"

# Esperar que el P300 expire el flow anterior (keepalive timeout ~4s)
echo "Esperando expiracion de flow anterior en P300..."
sleep 6

# Verificar flujo Dante (hasta 60s)
echo "Verificando flujo Dante..."
DANTE_OK=0
for i in $(seq 1 5); do
    bytes=$(RUST_LOG=error arecord -D inferno_rx -f S32_LE -r 48000 -c 2 -d 2 2>/dev/null | wc -c)
    if [ "$bytes" -gt 300000 ]; then
        echo "Flujo OK ($bytes bytes)"
        sleep 6
        DANTE_OK=1
        break
    fi
    echo "Intento $i: $bytes bytes"
    sleep 3
done

if [ "$DANTE_OK" -eq 1 ]; then
    echo "Arrancando CamillaDSP Dante con config (PROCESS_ID=$new, IP=$ETH_IP)"
    exec "$ENGINE" -p 1234 -a 0.0.0.0 "$CONFIG"
else
    # Sin flujo Dante: cargar preset fallback si existe, sino modo espera
    FALLBACK="/root/camilladsp/config/presets/maya44usb.yml"
    if [ -f "$FALLBACK" ]; then
        echo "Sin flujo Dante, cargando preset fallback: maya44usb"
        exec "$ENGINE" -p 1234 -a 0.0.0.0 "$FALLBACK"
    else
        echo "Sin flujo Dante y sin fallback, arrancando en modo espera"
        exec "$ENGINE" -p 1234 -a 0.0.0.0 -w
    fi
fi
