#!/usr/bin/env bash
# ==============================================================================
# PROJETO: Infraestrutura de Rede Corporativa - Cardeal Ltda.
# MAQUINA: VM 3 - Cliente (Hostname: CLIENTE) - Estacao da LAN e Capturas
# DISTRO ALVO: Ubuntu Server 26.04.1 LTS
# ==============================================================================

set -euo pipefail

echo "============================================================"
echo " [Cardeal Ltda] Configurando VM 3 - Cliente (CLIENTE)       "
echo "============================================================"

sudo hostnamectl set-hostname CLIENTE

LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | sed -n '2p')
[ -z "$LAN_IF" ] && LAN_IF="enp0s8"

# 1. Instalacao das ferramentas clientes e tshark
sudo systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< "wireshark-common wireshark-common/install-setuid boolean true"
sudo apt-get update -y
sudo apt-get install -y curl dnsutils smbclient swaks tshark tcpdump net-tools isc-dhcp-client

# 2. Ativacao de DHCP na placa interna com prioridade de rota para o Gateway
sudo tee /etc/netplan/99-lan.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_IF:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 50
EOF

sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply

# 3. Configuracao do DNS para o BIND9 (192.168.10.2) evitando conflito mDNS (.local)
sudo systemctl disable --now systemd-resolved || true
sudo rm -f /etc/resolv.conf
printf "nameserver 192.168.10.2\nsearch cardeal.local\n" | sudo tee /etc/resolv.conf > /dev/null
sudo sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf

# 4. Permissao para capturar pacotes com tshark sem sudo
sudo usermod -aG wireshark "${SUDO_USER:-user}" || true

echo -e "\n[INFO] Enderecos IP atribuidos:"
ip -br addr show

echo "============================================================"
echo " [OK] VM 3 - Cliente (CLIENTE) configurada e operacional!   "
echo "============================================================"
