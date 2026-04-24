# Opération GHOST PIPE — Déploiement Proxmox VE

## Pourquoi Proxmox plutôt que Docker ?

La version Docker est pratique pour un déploiement rapide, mais elle triche sur un point fondamental : les réseaux Docker bridge ne sont pas réellement isolés au niveau L2/L3 — un `iptables` côté hôte fait le travail, mais ce n'est pas de la vraie segmentation réseau. En passant sur Proxmox avec des VMs et des bridges dédiés, on obtient une isolation réseau réelle (chaque bridge est un domaine de broadcast séparé), un vrai pare-feu avec des règles inspectables par les étudiants, Suricata qui sniffe du trafic réseau réel (pas du trafic intra-namespace), et une architecture fidèle à ce qu'on trouverait en entreprise.

C'est aussi l'occasion de travailler des compétences SISR supplémentaires : configuration réseau de VMs, bridges Proxmox, interfaces pare-feu, et port mirroring.


---

## Architecture réseau

```
                        ┌─────────────────────────────────────────────────┐
                        │              PROXMOX VE (Hyperviseur)           │
                        │                                                 │
  ┌───────────────────────────────────────────────────────────────────┐   │
  │  vmbr0 — Management (10.0.0.0/24) — accès admin Proxmox         │   │
  └───────────────────────────────────────────────────────────────────┘   │
                        │                                                 │
  ┌─────────────────────┴─────────────────────────────────────────────┐   │
  │                                                                   │   │
  │  vmbr1 — NET-INTERNAL (172.20.0.0/24)                            │   │
  │  ┌──────────────┐  ┌──────────────┐                              │   │
  │  │  workstation  │  │  dns-server  │                              │   │
  │  │ 172.20.0.10   │  │ 172.20.0.53  │──┐                          │   │
  │  │  (pc-finance) │  │  (ns1.corp)  │  │                          │   │
  │  └──────────────┘  └──────────────┘  │                          │   │
  │                                       │                          │   │
  └───────────────────────────────────────│──────────────────────────┘   │
                                          │                              │
  ┌───────────────────────────────────────│──────────────────────────┐   │
  │                    ┌──────────────┐   │                          │   │
  │                    │   firewall   │◄──┘                          │   │
  │                    │  (OPNsense)  │                              │   │
  │                    │ int:172.20.0.1                               │   │
  │                    │ ext:172.30.0.1                               │   │
  │                    └──────┬───────┘                              │   │
  │                           │                                      │   │
  │  vmbr2 — NET-EXTERNAL (172.30.0.0/24)                           │   │
  │  ┌──────────────┐  ┌──────────────┐                              │   │
  │  │   attacker    │  │  dns-server  │                              │   │
  │  │ 172.30.0.10   │  │ 172.30.0.53  │                              │   │
  │  │  (kali-ext)   │  │  (2e NIC)    │                              │   │
  │  └──────────────┘  └──────────────┘                              │   │
  │                                                                   │   │
  │  ┌──────────────┐                                                │   │
  │  │ ids-suricata  │ ← port mirror sur vmbr2                      │   │
  │  │ 172.30.0.100  │   (ou bridge dédié vmbr3)                    │   │
  │  └──────────────┘                                                │   │
  └───────────────────────────────────────────────────────────────────┘   │
                        │                                                 │
                        └─────────────────────────────────────────────────┘
```

### Synthèse des réseaux

| Bridge | Réseau | Rôle | VLAN (optionnel) |
|--------|--------|------|------------------|
| vmbr0 | 10.0.0.0/24 | Management Proxmox | — |
| vmbr1 | 172.20.0.0/24 | Réseau interne Corp Industries | 20 |
| vmbr2 | 172.30.0.0/24 | Réseau externe (Internet simulé) | 30 |
| vmbr3 | — (pas d'IP) | Segment miroir IDS (optionnel) | 99 |


---

## Inventaire des VMs

### VM 1 — Pare-feu OPNsense

| Paramètre | Valeur |
|-----------|--------|
| OS | OPNsense 24.x (FreeBSD) |
| vCPU | 2 |
| RAM | 2 Go |
| Disque | 16 Go |
| NIC 1 (vtnet0) | vmbr1 — 172.20.0.1/24 (LAN / interne) |
| NIC 2 (vtnet1) | vmbr2 — 172.30.0.1/24 (WAN / externe) |
| NIC 3 (vtnet2) | vmbr0 — 10.0.0.1/24 (management, optionnel) |

Le pare-feu est le point de passage obligé entre les deux réseaux. Sans lui, workstation et attacker sont dans des domaines de broadcast totalement séparés — aucune communication possible.

### VM 2 — Serveur DNS Bind9

| Paramètre | Valeur |
|-----------|--------|
| OS | Debian 12 ou Ubuntu 24.04 Server |
| vCPU | 1 |
| RAM | 512 Mo |
| Disque | 8 Go |
| NIC 1 (ens18) | vmbr1 — 172.20.0.53/24 (interne) |
| NIC 2 (ens19) | vmbr2 — 172.30.0.53/24 (externe) |

Le serveur DNS est double-homed : un pied dans chaque réseau. C'est réaliste — beaucoup de serveurs DNS d'entreprise ont une interface interne et une interface exposée. Ici, le DNS ne passe PAS par le firewall car il est directement raccordé aux deux bridges. C'est un choix d'architecture : on veut que les requêtes DNS fonctionnent indépendamment du firewall pour que les étudiants comprennent que le DNS bypass le pare-feu.

### VM 3 — Workstation (poste compromis)

| Paramètre | Valeur |
|-----------|--------|
| OS | Debian 12 ou Ubuntu 24.04 Desktop/Server |
| vCPU | 1 |
| RAM | 1 Go |
| Disque | 10 Go |
| NIC 1 (ens18) | vmbr1 — 172.20.0.10/24 |
| Gateway | 172.20.0.1 (firewall) |
| DNS | 172.20.0.53 |

### VM 4 — Attaquant

| Paramètre | Valeur |
|-----------|--------|
| OS | Kali Linux 2024.x ou Debian 12 |
| vCPU | 2 |
| RAM | 2 Go |
| Disque | 20 Go |
| NIC 1 (ens18) | vmbr2 — 172.30.0.10/24 |
| Gateway | 172.30.0.1 (firewall) |
| DNS | 172.30.0.53 |

### VM 5 — IDS Suricata

| Paramètre | Valeur |
|-----------|--------|
| OS | Debian 12 ou Ubuntu 24.04 Server |
| vCPU | 2 |
| RAM | 2 Go |
| Disque | 16 Go |
| NIC 1 (ens18) | vmbr2 — 172.30.0.100/24 (gestion + sniffing) |
| NIC 2 (ens19) | vmbr1 — sans IP (mode promiscuous, sniffing interne) |

**Alternative** : au lieu d'un NIC en promiscuous, on peut utiliser le port mirroring Proxmox (voir section dédiée).

### Récapitulatif des ressources

| Total | Valeur |
|-------|--------|
| vCPU | 8 |
| RAM | 7,5 Go |
| Disque | 70 Go |
| VMs | 5 |

Un Proxmox modeste (16 Go RAM, 4 cœurs, 128 Go SSD) suffit largement.


---

## Étape 1 — Création des bridges Proxmox

### Via l'interface web

Dans Proxmox → Datacenter → Node → System → Network, créer les bridges suivants.

**vmbr1** (réseau interne) : Type Linux Bridge, sans port physique associé (réseau virtuel interne uniquement), pas d'adresse IP sur le bridge (les VMs ont leurs propres IPs), cocher "Autostart".

**vmbr2** (réseau externe) : même configuration, réseau virtuel interne uniquement.

**vmbr3** (segment miroir IDS, optionnel) : même configuration, utilisé uniquement si on fait du port mirroring dédié.

### Via la ligne de commande

Éditer `/etc/network/interfaces` sur le nœud Proxmox :

```
# Bridge réseau interne
auto vmbr1
iface vmbr1 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
    post-up   echo 1 > /sys/class/net/vmbr1/bridge/nf_call_iptables || true
    post-down echo 0 > /sys/class/net/vmbr1/bridge/nf_call_iptables || true

# Bridge réseau externe
auto vmbr2
iface vmbr2 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0

# Bridge miroir IDS (optionnel)
auto vmbr3
iface vmbr3 inet manual
    bridge-ports none
    bridge-stp off
    bridge-fd 0
```

Appliquer avec `ifreload -a` ou redémarrer le nœud.

### Option VLAN (si trunk physique disponible)

Si le Proxmox dispose d'un trunk VLAN sur une interface physique (ex: `eno1`), on peut utiliser des bridges VLAN-aware à la place :

```
auto vmbr1
iface vmbr1 inet manual
    bridge-ports eno1.20
    bridge-stp off

auto vmbr2
iface vmbr2 inet manual
    bridge-ports eno1.30
    bridge-stp off
```

L'avantage : les VLANs sont de vrais VLANs portés par le switch physique en amont, ce qui est encore plus réaliste. Mais pour un lab isolé sur un seul serveur, les bridges sans port physique suffisent.


---

## Étape 2 — Installation et configuration des VMs

### 2.1 — Pare-feu OPNsense

**Création de la VM** :
```bash
qm create 100 \
  --name ghost-fw \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr1 \
  --net1 virtio,bridge=vmbr2 \
  --cdrom local:iso/OPNsense-24.7-dvd-amd64.iso \
  --scsihw virtio-scsi-single \
  --scsi0 local-lvm:16,iothread=1 \
  --boot order=scsi0\;ide2 \
  --ostype other
```

**Installation OPNsense** : L'installateur OPNsense est guidé. À l'étape de configuration des interfaces, assigner vtnet0 comme LAN (172.20.0.1/24) et vtnet1 comme WAN (172.30.0.1/24). Désactiver le blocage des réseaux privés sur l'interface WAN (sinon le réseau 172.30.0.0/24 sera bloqué par défaut car c'est un réseau RFC 1918). Désactiver le DHCP sur les deux interfaces — on travaille en IP statique.

**Règles de pare-feu initiales** :

Sur l'interface LAN (172.20.0.0/24 → 172.30.0.0/24), créer les règles suivantes dans l'ordre :

Règle 1 : Autoriser DNS. Protocole UDP+TCP, source LAN net, destination any, port destination 53, action Pass. Cette règle autorise les requêtes DNS de la workstation vers le serveur DNS (même si le DNS est double-homed et ne passe pas par le firewall pour les requêtes directes, cette règle est là pour la cohérence).

Règle 2 : Autoriser ICMP (ping). Protocole ICMP, source LAN net, destination any, action Pass. Utile pour le debug.

Règle 3 : Bloquer tout le reste. Protocole any, source LAN net, destination any, action Block, log activé. C'est la règle par défaut mais on la rend explicite pour que les étudiants la voient.

Sur l'interface WAN (172.30.0.0/24 → 172.20.0.0/24), mêmes règles en miroir :

Règle 1 : Autoriser DNS (UDP+TCP, port 53). Règle 2 : Autoriser ICMP. Règle 3 : Bloquer tout le reste.

**Point pédagogique important** : Le serveur DNS étant double-homed (connecté directement aux deux bridges), les requêtes DNS entre workstation et DNS-server ne traversent PAS le firewall. De même, les requêtes DNS entre attacker et DNS-server ne traversent PAS le firewall. Le firewall contrôle uniquement le trafic qui doit transiter entre vmbr1 et vmbr2 via le routage — typiquement si la workstation essayait de joindre l'attaquant directement (172.30.0.10), ça passerait par le firewall et serait bloqué. C'est exactement le scénario réaliste : le DNS bypass le contrôle périmétrique, ce qui est le fondement de l'exfiltration DNS.


### 2.2 — Serveur DNS Bind9

**Création de la VM** :
```bash
qm create 101 \
  --name ghost-dns \
  --memory 512 \
  --cores 1 \
  --net0 virtio,bridge=vmbr1 \
  --net1 virtio,bridge=vmbr2 \
  --cdrom local:iso/debian-12-amd64-netinst.iso \
  --scsihw virtio-scsi-single \
  --scsi0 local-lvm:8,iothread=1 \
  --boot order=scsi0\;ide2 \
  --ostype l26
```

**Configuration réseau** (`/etc/network/interfaces`) :

```
auto lo
iface lo inet loopback

# Interface interne (vmbr1)
auto ens18
iface ens18 inet static
    address 172.20.0.53/24

# Interface externe (vmbr2)
auto ens19
iface ens19 inet static
    address 172.30.0.53/24
```

Pas de gateway par défaut — le serveur DNS n'a pas besoin de sortir vers Internet. Il répond aux requêtes sur ses deux interfaces.

**Installation Bind9** :

```bash
apt update && apt install -y bind9 bind9-utils dnsutils
```

Les fichiers de configuration sont les mêmes que la version Docker. Copier `named.conf.options`, `named.conf.local`, `update-key.conf` et `corp.local.zone` depuis l'archive du projet dans `/etc/bind/`. Le fichier de zone va dans `/var/lib/bind/corp.local.zone`. Adapter les permissions :

```bash
cp corp.local.zone /var/lib/bind/
chown bind:bind /var/lib/bind/corp.local.zone
chmod 664 /var/lib/bind/corp.local.zone
systemctl restart named
systemctl enable named
```

**Vérification** :

```bash
# Depuis le serveur DNS lui-même
dig @127.0.0.1 A pc-finance.corp.local +short
# Doit retourner 172.20.0.10

dig @127.0.0.1 TXT corp.local +short
# Doit retourner "v=spf1 mx ~all"
```


### 2.3 — Workstation (poste compromis)

**Création de la VM** :
```bash
qm create 102 \
  --name ghost-workstation \
  --memory 1024 \
  --cores 1 \
  --net0 virtio,bridge=vmbr1 \
  --cdrom local:iso/debian-12-amd64-netinst.iso \
  --scsihw virtio-scsi-single \
  --scsi0 local-lvm:10,iothread=1 \
  --boot order=scsi0\;ide2 \
  --ostype l26
```

**Configuration réseau** (`/etc/network/interfaces`) :

```
auto lo
iface lo inet loopback

auto ens18
iface ens18 inet static
    address 172.20.0.10/24
    gateway 172.20.0.1
    dns-nameservers 172.20.0.53
    dns-search corp.local
```

**Paquets et fichiers** :

```bash
apt update && apt install -y dnsutils bind9-utils python3 vim nano \
    nmap net-tools iputils-ping file openssl
```

Créer le répertoire `/home/employe/documents/` et y placer les 4 fichiers sensibles de l'archive (`memo-confidentiel.txt`, `credentials.csv`, `serveur-prod.key`, `dump-clients-prod.sql`).


### 2.4 — Attaquant

**Création de la VM** :
```bash
qm create 103 \
  --name ghost-attacker \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr2 \
  --cdrom local:iso/kali-linux-2024.4-installer-amd64.iso \
  --scsihw virtio-scsi-single \
  --scsi0 local-lvm:20,iothread=1 \
  --boot order=scsi0\;ide2 \
  --ostype l26
```

Si tu préfères une Debian légère plutôt qu'une Kali complète, c'est tout aussi fonctionnel — on n'a besoin que de `dnsutils`, `python3`, et des outils classiques.

**Configuration réseau** :

```
auto ens18
iface ens18 inet static
    address 172.30.0.10/24
    gateway 172.30.0.1
    dns-nameservers 172.30.0.53
    dns-search corp.local
```


### 2.5 — IDS Suricata

**Création de la VM** :
```bash
qm create 104 \
  --name ghost-ids \
  --memory 2048 \
  --cores 2 \
  --net0 virtio,bridge=vmbr2 \
  --net1 virtio,bridge=vmbr1 \
  --cdrom local:iso/debian-12-amd64-netinst.iso \
  --scsihw virtio-scsi-single \
  --scsi0 local-lvm:16,iothread=1 \
  --boot order=scsi0\;ide2 \
  --ostype l26
```

**Configuration réseau** :

```
auto lo
iface lo inet loopback

# Interface de gestion + sniffing réseau externe
auto ens18
iface ens18 inet static
    address 172.30.0.100/24
    gateway 172.30.0.1

# Interface de sniffing réseau interne (pas d'IP, mode promiscuous)
auto ens19
iface ens19 inet manual
    up ip link set ens19 promisc on
    down ip link set ens19 promisc off
```

**Installation Suricata** :

```bash
apt update && apt install -y software-properties-common
add-apt-repository ppa:oisf/suricata-stable
apt update && apt install -y suricata jq
```

Ou sur Debian 12 sans PPA :

```bash
apt update && apt install -y suricata suricata-oinkmaster jq
```

Copier la configuration `suricata.yaml` et les règles `ghost-pipe.rules` depuis l'archive. Adapter le fichier suricata.yaml pour écouter sur les deux interfaces :

```yaml
af-packet:
  - interface: ens18
    cluster-id: 98
    cluster-type: cluster_flow
    defrag: yes
  - interface: ens19
    cluster-id: 99
    cluster-type: cluster_flow
    defrag: yes
```

Démarrage :

```bash
systemctl enable suricata
systemctl start suricata
```


---

## Étape 3 — Port mirroring pour Suricata (optionnel mais recommandé)

### Option A — Mode promiscuous sur les bridges

C'est la méthode la plus simple. Sur l'hôte Proxmox, on configure les bridges pour autoriser le mode promiscuous :

```bash
# Sur le nœud Proxmox
echo 1 > /sys/class/net/vmbr1/bridge/nf_call_iptables
echo 1 > /sys/class/net/vmbr2/bridge/nf_call_iptables
```

Et dans la configuration de la VM Suricata (fichier `/etc/pve/qemu-server/104.conf`), ajouter le tag `firewall=0` sur les NICs pour désactiver le filtrage Proxmox :

```
net0: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr2,firewall=0
net1: virtio=XX:XX:XX:XX:XX:XX,bridge=vmbr1,firewall=0
```

Le mode promiscuous sur ens19 (configuré dans `/etc/network/interfaces` plus haut) permet alors à Suricata de voir tout le trafic du bridge vmbr1, pas seulement celui destiné à sa propre MAC.

### Option B — Port mirroring avec tc (traffic control)

Plus élégant : on duplique le trafic depuis les bridges vers un bridge dédié IDS (vmbr3). Sur l'hôte Proxmox :

```bash
# Miroir du trafic vmbr1 vers vmbr3
tc qdisc add dev vmbr1 handle ffff: ingress
tc filter add dev vmbr1 parent ffff: protocol all u32 match u32 0 0 \
    action mirred egress mirror dev vmbr3

# Miroir du trafic vmbr2 vers vmbr3
tc qdisc add dev vmbr2 handle ffff: ingress
tc filter add dev vmbr2 parent ffff: protocol all u32 match u32 0 0 \
    action mirred egress mirror dev vmbr3
```

La VM Suricata aurait alors un NIC supplémentaire sur vmbr3 dédié au sniffing. L'avantage : Suricata voit TOUT le trafic des deux réseaux sans être dans le chemin de données.

Pour rendre le mirroring persistant, créer un script `/etc/network/if-up.d/mirror-ids` :

```bash
#!/bin/bash
# Port mirroring pour IDS Suricata
if [ "$IFACE" = "vmbr1" ] || [ "$IFACE" = "vmbr2" ]; then
    tc qdisc add dev "$IFACE" handle ffff: ingress 2>/dev/null
    tc filter add dev "$IFACE" parent ffff: protocol all u32 match u32 0 0 \
        action mirred egress mirror dev vmbr3 2>/dev/null
fi
```

### Option C — Suricata directement dans OPNsense

OPNsense intègre Suricata nativement via le plugin `os-suricata`. C'est l'option la plus simple si on ne veut pas de VM dédiée. Dans OPNsense : Services → Intrusion Detection → Administration. Activer sur les interfaces LAN et WAN, ajouter les règles custom `ghost-pipe.rules`. L'inconvénient : les étudiants n'ont pas un accès shell direct pour manipuler les règles et lire les logs aussi facilement. L'interface web d'OPNsense est bien faite mais c'est moins formateur que du CLI brut.


---

## Étape 4 — Validation de l'infrastructure

### Tests de connectivité

```bash
# Depuis workstation → DNS (doit fonctionner)
ping -c 2 172.20.0.53

# Depuis workstation → attacker (doit échouer — bloqué par le FW)
ping -c 2 172.30.0.10

# Depuis attacker → DNS (doit fonctionner)
ping -c 2 172.30.0.53

# Depuis attacker → workstation (doit échouer — bloqué par le FW)
ping -c 2 172.20.0.10
```

### Tests DNS

```bash
# Depuis workstation
dig A pc-finance.corp.local @172.20.0.53 +short
# → 172.20.0.10

# Depuis attacker
dig TXT corp.local @172.30.0.53 +short
# → "v=spf1 mx ~all"

# Transfert de zone (doit fonctionner — vulnérabilité volontaire)
dig AXFR corp.local @172.30.0.53
```

### Test nsupdate

```bash
# Depuis workstation
nsupdate << EOF
server 172.20.0.53
zone corp.local
update add test-proxmox.corp.local. 60 TXT "validation-ok"
send
EOF

# Vérification depuis attacker
dig +short TXT test-proxmox.corp.local @172.30.0.53
# → "validation-ok"
```

### Test Suricata

```bash
# Sur la VM IDS
tail -f /var/log/suricata/fast.log

# Depuis attacker, déclencher une alerte
dig AXFR corp.local @172.30.0.53
# → L'alerte AXFR doit apparaître dans fast.log
```

### Test du pare-feu

```bash
# Depuis workstation, tenter un SSH vers attacker (doit être bloqué)
ssh 172.30.0.10
# → timeout

# Vérifier dans les logs OPNsense
# Firewall → Log Files → Live View → filtrer sur "Block"
```


---

## Différences pédagogiques avec la version Docker

### Ce que la version Proxmox apporte en plus

L'isolation réseau est réelle. En Docker, un conteneur sur `net-internal` peut potentiellement atteindre `net-external` via des routes par défaut de l'hôte. En Proxmox avec des bridges séparés, c'est physiquement impossible sans le firewall ou le DNS double-homed.

Le pare-feu est un vrai composant inspectable. Les étudiants peuvent se connecter à l'interface web OPNsense, voir les règles, observer les logs en temps réel, et constater que le trafic DNS passe AUTOUR du firewall (via le DNS double-homed) plutôt qu'à travers. C'est la leçon centrale du hackathon : le DNS est un canal latéral qui échappe au contrôle périmétrique.

Suricata fonctionne en conditions réelles. Le trafic capturé est du vrai trafic Ethernet, pas du trafic virtuel entre namespaces. Les timestamps, les tailles de paquets, les retransmissions TCP — tout est réaliste. Les étudiants peuvent même faire des captures PCAP avec tcpdump sur la VM IDS pour analyse dans Wireshark.

La topologie est visible. On peut dessiner le schéma réseau au tableau, montrer que chaque VM est un "serveur" avec sa propre IP, ses propres interfaces, et que les bridges Proxmox sont des "switchs virtuels". C'est beaucoup plus concret que d'expliquer des namespaces Docker.

### Ce qu'on perd

Le déploiement est plus long : environ 1h-1h30 de setup contre 5 minutes en Docker. Ce n'est pas faisable en live le jour du hackathon — il faut préparer la veille.

La reproductibilité est moindre. Docker garantit un environnement identique à chaque `docker compose up`. Proxmox dépend de l'installation manuelle de chaque VM. Pour mitiger ça, on peut utiliser des templates Proxmox (voir section suivante).

Le coût matériel est plus élevé. Un serveur Proxmox dédié ou un PC suffisamment puissant est nécessaire, contre n'importe quel laptop avec Docker.


---

## Templates et automatisation (gain de temps)

### Créer des templates Proxmox

Après avoir configuré et validé chaque VM, la convertir en template pour duplication rapide :

```bash
# Arrêter la VM
qm shutdown 102

# Convertir en template
qm template 102
```

Pour instancier un nouveau lab :

```bash
# Cloner depuis le template (full clone)
qm clone 102 202 --name ghost-workstation-equipe2 --full true
```

### Script de déploiement automatisé

Pour déployer un lab par équipe (si plusieurs Proxmox ou si assez de ressources pour plusieurs instances parallèles) :

```bash
#!/bin/bash
# deploy-team.sh <team_number>
TEAM=$1
BASE_VMID=$((100 + TEAM * 10))
INTERNAL_NET="172.2${TEAM}.0"
EXTERNAL_NET="172.3${TEAM}.0"

echo "Déploiement équipe $TEAM (VMIDs $BASE_VMID-$((BASE_VMID+4)))"

qm clone 100 $BASE_VMID       --name "ghost-fw-team${TEAM}" --full true
qm clone 101 $((BASE_VMID+1)) --name "ghost-dns-team${TEAM}" --full true
qm clone 102 $((BASE_VMID+2)) --name "ghost-ws-team${TEAM}" --full true
qm clone 103 $((BASE_VMID+3)) --name "ghost-atk-team${TEAM}" --full true
qm clone 104 $((BASE_VMID+4)) --name "ghost-ids-team${TEAM}" --full true

echo "Équipe $TEAM déployée. Adapter les IPs manuellement."
```

### Cloud-init (pour aller plus loin)

Si on veut automatiser aussi la configuration réseau, on peut préparer des images cloud-init Debian/Ubuntu et les paramétrer via Proxmox :

```bash
qm set 102 --cicustom "network=local:snippets/workstation-network.yaml"
qm set 102 --ipconfig0 ip=172.20.0.10/24,gw=172.20.0.1
qm set 102 --nameserver 172.20.0.53
qm set 102 --searchdomain corp.local
```


---

## Variante avancée — Ajout d'un proxy DNS

Pour un scénario encore plus réaliste, on peut ajouter un serveur DNS cache/relais (ex : Unbound) dans la DMZ externe qui relaie les requêtes vers le DNS autoritaire interne. Le trafic DNS de l'attaquant passerait alors par ce relais, ce qui ajoute une couche de complexité à l'exfiltration (les réponses sont cachées, les TTL impactent la fraîcheur des données) et rend la détection plus difficile (les requêtes viennent du relais, pas de l'attaquant directement).


---

## Checklist de déploiement

- [ ] Bridges vmbr1, vmbr2 (et vmbr3) créés sur Proxmox
- [ ] ISO OPNsense, Debian 12 et Kali téléchargés dans le stockage local
- [ ] VM OPNsense installée, interfaces LAN/WAN configurées
- [ ] Règles firewall configurées (DNS autorisé, reste bloqué)
- [ ] VM DNS installée, Bind9 configuré avec la zone corp.local
- [ ] nsupdate fonctionnel depuis la workstation
- [ ] VM Workstation installée, fichiers sensibles en place
- [ ] VM Attaquant installée, outils DNS disponibles
- [ ] VM Suricata installée, règles ghost-pipe.rules chargées
- [ ] Mode promiscuous ou port mirroring configuré
- [ ] Tests de connectivité validés (ping, dig, nsupdate)
- [ ] Tests d'isolation validés (workstation ne peut pas joindre attacker)
- [ ] Alertes Suricata fonctionnelles (test AXFR)
- [ ] Templates Proxmox créés pour duplication rapide
