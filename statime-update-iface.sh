#!/bin/bash
# Actualiza la interfaz en statime-inferno.toml según la BIND_IP guardada en .asoundrc
ASOUNDRC="/root/.asoundrc"
TOML="/etc/statime-inferno.toml"

# Leer BIND_IP guardada
BIND_IP=$(grep -oP 'BIND_IP\s+"\K[^"]+' "$ASOUNDRC" | head -1)

if [ -z "$BIND_IP" ]; then
    echo "[statime-pre] sin BIND_IP en .asoundrc, se usa interfaz actual del toml"
    exit 0
fi

# Buscar qué interfaz tiene esa IP
IFACE=$(ip -4 addr show | awk -v ip="$BIND_IP" '
    /^[0-9]+:/ { iface=$2; sub(/:$/, "", iface) }
    /inet / { if (index($2, ip"/") == 1) print iface }
')

if [ -z "$IFACE" ]; then
    echo "[statime-pre] IP $BIND_IP no encontrada en ninguna interfaz, sin cambios"
    exit 0
fi

# Actualizar toml si la interfaz cambió
CURRENT=$(grep -oP 'interface\s*=\s*"\K[^"]+' "$TOML" | head -1)
if [ "$CURRENT" != "$IFACE" ]; then
    sed -i "s/interface = \"$CURRENT\"/interface = \"$IFACE\"/" "$TOML"
    echo "[statime-pre] interfaz actualizada: $CURRENT -> $IFACE (IP=$BIND_IP)"
else
    echo "[statime-pre] interfaz ya correcta: $IFACE"
fi
