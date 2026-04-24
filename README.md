# Opération GHOST PIPE

Hackathon BTS SIO 2 — Exfiltration de données via DNS TXT records, inspiré du projet [DOOM over DNS](https://lesjoiesducode.fr/doom-enregistrements-dns) d'Adam Rice.

## Démarrage rapide

```bash
chmod +x start.sh
./start.sh
```

## Structure du projet

```
hackathon-dns-exfil/
├── docker-compose.yml          # Infrastructure complète
├── start.sh                    # Script de démarrage + validation
├── containers/
│   ├── dns-server/             # Bind9 avec zone corp.local
│   ├── workstation/            # Poste compromis + fichiers sensibles
│   │   └── data/               # 4 fichiers à exfiltrer
│   ├── attacker/               # Machine externe
│   └── ids/                    # Suricata IDS
│       └── suricata/rules/     # Règles (partiellement commentées)
├── corrections/                # Scripts de correction (formateur)
│   ├── phase1-inject.sh
│   ├── phase1-inject.py
│   ├── phase2-extract.sh
│   ├── phase2-extract.py
│   └── ghost-pipe-CORRECTION.rules
└── docs/
    ├── GHOST-PIPE-guide-pedagogique.md   # Guide formateur complet
    └── GHOST-PIPE-fiche-participant.md   # Fiche distribuée aux étudiants
```

## Prérequis

- Docker Engine 24+
- Docker Compose v2
- ~2 Go d'espace disque
- ~1 Go de RAM

## Licence

Usage pédagogique — BTS SIO — ORT Daniel Mayer, Montreuil.
