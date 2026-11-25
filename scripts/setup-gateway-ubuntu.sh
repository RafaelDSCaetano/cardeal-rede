#!/usr/bin/env bash
# ==============================================================================
# PROJETO: Infraestrutura de Rede Corporativa - Cardeal Ltda.
# MAQUINA: VM 1 - Gateway (Hostname: GATEWAY) - Roteador / NAT / DHCP
# DISTRO ALVO: Ubuntu Server 26.04.1 LTS
# ==============================================================================

set -euo pipefail

echo "============================================================"
echo " [Cardeal Ltda] Configurando VM 1 - Gateway (GATEWAY)       "
echo "============================================================"

sudo hostnamectl set-hostname GATEWAY

WAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | sed -n '1p')
LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | sed -n '2p')

echo "[INFO] Interface WAN (NAT): $WAN_IF"
echo "[INFO] Interface LAN (rede_cardeal): $LAN_IF"

# 1. Configuracao de IP Estatico 192.168.10.1/24 via Netplan
sudo tee /etc/netplan/99-lan.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_IF:
      addresses:
        - 192.168.10.1/24
EOF

sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply

# 2. Habilitacao do Roteamento no Kernel (IP Forwarding)
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ipforward.conf
sudo sysctl --system

# 3. Regras de NAT (MASQUERADE) e Encaminhamento (iptables)
sudo iptables -t nat -F
sudo iptables -F FORWARD
sudo iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
sudo iptables -A FORWARD -i "$LAN_IF" -o "$WAN_IF" -j ACCEPT
sudo iptables -A FORWARD -i "$WAN_IF" -o "$LAN_IF" -m state --state RELATED,ESTABLISHED -j ACCEPT

# 4. Instalacao do DHCP Server e Persistencia do iptables
sudo systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive
sudo apt-get update -y
sudo apt-get --fix-broken install -y
sudo apt-get install -y isc-dhcp-server iptables-persistent net-tools curl ufw-
sudo netfilter-persistent save

# 5. Configuracao do Servidor DHCP (isc-dhcp-server)
sudo sed -i "s/^INTERFACESv4=.*/INTERFACESv4=\"$LAN_IF\"/" /etc/default/isc-dhcp-server

sudo tee /etc/dhcp/dhcpd.conf > /dev/null <<'EOF'
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet 192.168.10.0 netmask 255.255.255.0 {
    range 192.168.10.50 192.168.10.150;
    option subnet-mask 255.255.255.0;
    option broadcast-address 192.168.10.255;
    option routers 192.168.10.1;
    option domain-name-servers 192.168.10.2;
    option domain-name "cardeal.local";
}
EOF

sudo systemctl restart isc-dhcp-server
sudo systemctl enable isc-dhcp-server

echo "============================================================"
echo " [OK] VM 1 - Gateway (GATEWAY) configurada e operacional!   "
echo "============================================================"
