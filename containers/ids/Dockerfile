FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    software-properties-common \
    && add-apt-repository ppa:oisf/suricata-stable \
    && apt-get update && apt-get install -y \
    suricata \
    jq \
    vim \
    nano \
    && rm -rf /var/lib/apt/lists/*

# Configuration Suricata personnalisée
COPY suricata/suricata.yaml /etc/suricata/suricata.yaml
COPY suricata/rules/ghost-pipe.rules /var/lib/suricata/rules/ghost-pipe.rules

# Répertoire de logs
RUN mkdir -p /var/log/suricata

# Script de démarrage
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]
