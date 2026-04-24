#!/bin/bash
echo "══════════════════════════════════════════════════"
echo "  GHOST PIPE — IDS Suricata"
echo "  Surveillance du trafic DNS"
echo "══════════════════════════════════════════════════"

# Détection automatique de l'interface
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$IFACE" ]; then
    IFACE="eth0"
fi

echo "[*] Interface de capture : $IFACE"
echo "[*] Règles : /var/lib/suricata/rules/ghost-pipe.rules"
echo "[*] Logs   : /var/log/suricata/"
echo ""
echo "Commandes utiles :"
echo "  tail -f /var/log/suricata/fast.log     # Alertes en temps réel"
echo "  tail -f /var/log/suricata/eve.json     # Logs JSON détaillés"
echo "  jq 'select(.alert)' /var/log/suricata/eve.json  # Filtrer alertes"
echo "══════════════════════════════════════════════════"

# Lancement de Suricata en mode IDS
exec suricata -c /etc/suricata/suricata.yaml -i "$IFACE" --set "af-packet.0.interface=$IFACE" -v
