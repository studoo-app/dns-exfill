#!/bin/bash
# ==========================================================================
#  GHOST PIPE — Script de démarrage et validation
# ==========================================================================

set -e

echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║       OPÉRATION GHOST PIPE — DNS Exfiltration       ║"
echo "  ║            Hackathon BTS SIO 2 — 2026               ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""

# ── Build et démarrage ──────────────────────────────────────────────────────
echo "[1/3] Construction des images Docker..."
docker compose build --quiet

echo "[2/3] Démarrage de l'infrastructure..."
docker compose up -d

echo "[3/3] Attente du démarrage des services (10s)..."
sleep 10

# ── Validation ──────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════"
echo "  VALIDATION DE L'INFRASTRUCTURE"
echo "══════════════════════════════════════════════════"

ERRORS=0

# Test DNS résolution interne
echo -n "  [DNS]  Résolution interne (workstation → DNS)........... "
RESULT=$(docker exec ghost-workstation dig +short A pc-finance.corp.local @172.20.0.53 2>/dev/null)
if [ "$RESULT" = "172.20.0.10" ]; then
    echo "✅"
else
    echo "❌ (obtenu: $RESULT)"
    ERRORS=$((ERRORS + 1))
fi

# Test DNS résolution externe
echo -n "  [DNS]  Résolution externe (attacker → DNS).............. "
RESULT=$(docker exec ghost-attacker dig +short A ns1.corp.local @172.30.0.53 2>/dev/null)
if [ "$RESULT" = "172.20.0.53" ]; then
    echo "✅"
else
    echo "❌ (obtenu: $RESULT)"
    ERRORS=$((ERRORS + 1))
fi

# Test TXT record légitime
echo -n "  [DNS]  Requête TXT légitime (SPF)...................... "
RESULT=$(docker exec ghost-attacker dig +short TXT corp.local @172.30.0.53 2>/dev/null | head -1)
if echo "$RESULT" | grep -q "spf1"; then
    echo "✅"
else
    echo "❌ (obtenu: $RESULT)"
    ERRORS=$((ERRORS + 1))
fi

# Test nsupdate (mise à jour dynamique)
echo -n "  [DNS]  Mise à jour dynamique (nsupdate)................ "
docker exec ghost-workstation bash -c 'echo -e "server 172.20.0.53\nzone corp.local\nupdate add test-validation.corp.local. 60 TXT \"ghost-pipe-ok\"\nsend" | nsupdate' 2>/dev/null
sleep 2
RESULT=$(docker exec ghost-workstation dig +short TXT test-validation.corp.local @172.20.0.53 2>/dev/null | tr -d '"')
if [ "$RESULT" = "ghost-pipe-ok" ]; then
    echo "✅"
    # Nettoyage
    docker exec ghost-workstation bash -c 'echo -e "server 172.20.0.53\nzone corp.local\nupdate delete test-validation.corp.local. TXT\nsend" | nsupdate' 2>/dev/null
else
    echo "❌ (obtenu: $RESULT)"
    ERRORS=$((ERRORS + 1))
fi

# Test Suricata
echo -n "  [IDS]  Suricata en fonctionnement...................... "
SURICATA_PID=$(docker exec ghost-ids pgrep suricata 2>/dev/null || echo "")
if [ -n "$SURICATA_PID" ]; then
    echo "✅ (PID: $SURICATA_PID)"
else
    echo "❌ (non démarré)"
    ERRORS=$((ERRORS + 1))
fi

# Test isolation réseau
echo -n "  [NET]  Isolation workstation ↛ attacker................ "
docker exec ghost-workstation ping -c 1 -W 2 172.30.0.10 > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "✅ (isolé)"
else
    echo "⚠️  (pas isolé — normal avec Docker bridge)"
fi

# Test fichiers sensibles
echo -n "  [DATA] Fichiers sensibles présents..................... "
NB_FILES=$(docker exec ghost-workstation ls /home/employe/documents/ 2>/dev/null | wc -l)
if [ "$NB_FILES" -ge 3 ]; then
    echo "✅ ($NB_FILES fichiers)"
else
    echo "❌ ($NB_FILES fichiers)"
    ERRORS=$((ERRORS + 1))
fi

echo ""
echo "══════════════════════════════════════════════════"
if [ $ERRORS -eq 0 ]; then
    echo "  ✅ INFRASTRUCTURE OPÉRATIONNELLE"
else
    echo "  ⚠️  $ERRORS ERREUR(S) DÉTECTÉE(S)"
fi
echo "══════════════════════════════════════════════════"
echo ""
echo "  Accès aux machines :"
echo "    docker exec -it ghost-workstation bash   # Poste compromis"
echo "    docker exec -it ghost-attacker bash      # Machine attaquant"
echo "    docker exec -it ghost-dns bash           # Serveur DNS"
echo "    docker exec -it ghost-ids bash           # IDS Suricata"
echo ""
echo "  Logs Suricata :"
echo "    docker exec ghost-ids tail -f /var/log/suricata/fast.log"
echo "    docker exec ghost-ids tail -f /var/log/suricata/eve.json"
echo ""
echo "  Arrêt : docker compose down -v"
echo "══════════════════════════════════════════════════"
