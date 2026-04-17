#!/bin/bash
# Arranque robusto de CamillaDSP con inferno_rx (Dante via Ethernet)
# - Auto-detecta IP de eth0
# - Auto-incrementa PROCESS_ID para evitar error 1102 del P300
# - Verifica que el flujo Dante esté establecido antes de arrancar

ASOUNDRC="/root/.asoundrc"
STATE_BASE="/root/.local/state/inferno_aoip"
SUBSCRIPTIONS_SRC=""

# Detectar IP de eth0 (Dante debe ir por Ethernet)
ETH_IP=$(ip -4 addr show eth0 2>/dev/null | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+' | head -1)
if [ -z "$ETH_IP" ]; then
    echo "ERROR: eth0 sin IP, abortando"
    exit 1
fi

# Calcular hex de IP para el directorio de estado de inferno
IP_HEX=$(python3 -c "
import socket, struct
ip = '$ETH_IP'
n = struct.unpack('>I', socket.inet_aton(ip))[0]
print('0000' + format(n, '08x'))
")

echo "Usando eth0 IP=$ETH_IP hex=$IP_HEX"

# Actualizar BIND_IP en .asoundrc si cambió
current_bind=$(grep 'BIND_IP "[0-9]' "$ASOUNDRC" | head -1 | grep -oP '\d+\.\d+\.\d+\.\d+')
if [ "$current_bind" != "$ETH_IP" ]; then
    sed -i "s/BIND_IP \"$current_bind\"/BIND_IP \"$ETH_IP\"/g" "$ASOUNDRC"
    echo "BIND_IP actualizado: $current_bind -> $ETH_IP"
fi

# Encontrar directorio de subscriptions con canales configurados
for d in "$STATE_BASE"/*/; do
    if grep -q "tx_hostname" "$d/rx_subscriptions.toml" 2>/dev/null; then
        SUBSCRIPTIONS_SRC="$d/rx_subscriptions.toml"
        break
    fi
done

if [ -z "$SUBSCRIPTIONS_SRC" ]; then
    echo "ERROR: no se encontraron rx_subscriptions con canales configurados"
    exit 1
fi
echo "Subscriptions: $SUBSCRIPTIONS_SRC"

# Leer PROCESS_ID actual del bloque inferno_rx
current=$(awk '/pcm.inferno_rx/,/^[}]/' "$ASOUNDRC" | grep 'PROCESS_ID "[0-9]' | grep -o '[0-9]*' | head -1)
if [ -z "$current" ]; then current=1000; fi
new=$((current + 1))

# Actualizar PROCESS_ID en .asoundrc (solo bloque inferno_rx)
sed -i "s/PROCESS_ID \"$current\"/PROCESS_ID \"$new\"/" "$ASOUNDRC"
echo "PROCESS_ID: $current -> $new"

# Crear directorio de estado para el nuevo PROCESS_ID
new_hex=$(printf "%04x" $new)
new_dir="${STATE_BASE}/${IP_HEX}${new_hex}"
mkdir -p "$new_dir"
cp "$SUBSCRIPTIONS_SRC" "$new_dir/rx_subscriptions.toml"

# Esperar que el P300 expire el flow anterior (keepalive timeout = 4s)
echo "Esperando expiracion de flow anterior en P300..."
sleep 6

# Verificar que el flujo Dante esté establecido antes de arrancar CamillaDSP
echo "Verificando flujo Dante..."
for i in $(seq 1 20); do
    bytes=$(RUST_LOG=error arecord -D inferno_rx -f S32_LE -r 48000 -c 2 -d 2 2>/dev/null | wc -c)
    if [ "$bytes" -gt 300000 ]; then
        echo "Flujo OK ($bytes bytes), esperando expiracion..."
        sleep 6
        break
    fi
    echo "Intento $i: $bytes bytes (esperando flujo...)"
    sleep 3
done

echo "Arrancando CamillaDSP (PROCESS_ID=$new, IP=$ETH_IP)"
exec /root/camilladsp/engine/camilladsp -p 1234 -a 0.0.0.0 -w
