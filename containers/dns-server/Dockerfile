FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    bind9 \
    bind9-utils \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Configuration Bind9
COPY named.conf.options /etc/bind/named.conf.options
COPY named.conf.local   /etc/bind/named.conf.local
COPY corp.local.zone     /var/lib/bind/corp.local.zone

# Permissions pour les mises à jour dynamiques
RUN chown bind:bind /var/lib/bind/corp.local.zone && \
    chmod 664 /var/lib/bind/corp.local.zone && \
    mkdir -p /var/log/named && \
    chown bind:bind /var/log/named

# Clé TSIG pour nsupdate (sécurité minimale volontaire pour le hackathon)
COPY update-key.conf /etc/bind/update-key.conf

EXPOSE 53/tcp 53/udp

CMD ["named", "-g", "-c", "/etc/bind/named.conf", "-u", "bind"]
