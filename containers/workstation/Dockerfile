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
    && rm -rf /var/lib/apt/lists/*

# Fichiers sensibles à exfiltrer
COPY data/ /home/employe/documents/
RUN chmod -R 644 /home/employe/documents/*

# Message d'accueil
RUN echo '\n\
══════════════════════════════════════════════════\n\
  GHOST PIPE — Poste pc-finance.corp.local\n\
  Utilisateur : m.dupont (Comptabilité)\n\
══════════════════════════════════════════════════\n\
  Fichiers sensibles : /home/employe/documents/\n\
  Serveur DNS interne : 172.20.0.53\n\
══════════════════════════════════════════════════\n\
' >> /etc/bash.bashrc

WORKDIR /home/employe
CMD ["/bin/bash"]
