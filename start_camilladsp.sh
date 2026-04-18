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

# Suscripciones gestionadas por Dante Controller (modo push desde P300)
# inferno_rx arranca siempre — Dante Controller asigna los canales desde su interfaz
# El archivo canónico se mantiene para referencia pero no bloquea el arranque
CANONICAL_SUBS="/root/camilladsp/config/dante_subscriptions.toml"
if [ -f "$CANONICAL_SUBS" ] && grep -q "tx_hostname" "$CANONICAL_SUBS" 2>/dev/null; then
    echo "Suscripciones previas en archivo canónico (gestionadas por Dante Controller)"
fi

# Leer PROCESS_ID actual — inferno lo incrementará al arrancar, así que pre-creamos
# el directorio con PROCESS_ID+1 para que inferno encuentre las suscripciones ya listas
current=$(awk '/pcm.inferno_rx/,/^\}/' "$ASOUNDRC" | grep 'PROCESS_ID' | grep -o '[0-9]*' | head -1)
if [ -z "$current" ]; then current=1000; fi
new=$((current + 1))
sed -i "/pcm\.inferno_rx/,/^\}/ s/PROCESS_ID \"$current\"/PROCESS_ID \"$new\"/" "$ASOUNDRC"
echo "PROCESS_ID: $current -> $new (inferno usará este al arrancar)"

# Limpiar directorios obsoletos — inferno creará el suyo al arrancar
# Las suscripciones las gestiona Dante Controller (modo push desde P300)
find "$STATE_BASE" -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
new_hex=$(printf "%04x" $new)
new_dir="${STATE_BASE}/${IP_HEX}${new_hex}"
mkdir -p "$new_dir"
echo "Directorio de estado pre-creado: $new_dir"

# Arrancar con inferno_rx — Dante Controller gestiona la asignación de canales
# inferno_rx queda a la escucha; el P300 iniciará el flujo al asignar en Dante Controller
echo "Arrancando CamillaDSP con inferno_rx (esperando asignación desde Dante Controller)"

# Esperar que hw:1,0 quede libre (max 15s)
for i in $(seq 1 5); do
    if ! grep -rl 'pcmC1D0' /proc/*/fd 2>/dev/null | grep -q .; then
        break
    fi
    echo "Esperando que hw:1,0 quede libre ($i)..."
    sleep 3
done

exec "$ENGINE" -p 1234 -a 0.0.0.0 "$CONFIG"
