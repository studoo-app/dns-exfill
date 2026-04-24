FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    dnsutils \
    bind9-utils \
    iputils-ping \
    net-tools \
    iproute2 \
    nmap \
    curl \
    vim \
    nano \
    python3 \
    python3-pip \
    file \
    xxd \
    openssl \
    hashdeep \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Répertoire de travail pour la reconstruction
RUN mkdir -p /home/attacker/loot

# Message d'accueil
RUN echo '\n\
══════════════════════════════════════════════════\n\
  GHOST PIPE — Machine externe (attaquant)\n\
  Hostname : kali-ext\n\
══════════════════════════════════════════════════\n\
  Serveur DNS cible : 172.30.0.53\n\
  Zone cible         : corp.local\n\
  Répertoire loot    : /home/attacker/loot/\n\
══════════════════════════════════════════════════\n\
' >> /etc/bash.bashrc

WORKDIR /home/attacker
CMD ["/bin/bash"]
