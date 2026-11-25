#!/bin/bash
# gateway/iptables-nat.sh - Regras de roteamento e NAT do Gateway Cardeal Ltda.
WAN_IF="enp0s3"  # Ajuste para a placa ligada a Internet (NAT)
LAN_IF="enp0s8"  # Ajuste para a placa ligada a rede_cardeal

# Habilita IP Forwarding no kernel
echo 1 > /proc/sys/net/ipv4/ip_forward

# Limpa regras anteriores
iptables -t nat -F
iptables -F FORWARD

# Masquerading de pacotes saindo para a Internet
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE

# Regras de encaminhamento entre LAN e WAN
iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT
iptables -A FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT
