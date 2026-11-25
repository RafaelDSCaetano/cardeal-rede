#!/usr/bin/env bash
# ==============================================================================
# PROJETO: Infraestrutura de Rede Corporativa - Cardeal Ltda.
# MAQUINA: VM 2 - Servicos (Hostname: SERVICOS) - DNS, Web, SMB, E-mail
# DISTRO ALVO: Ubuntu Server 26.04.1 LTS
# ==============================================================================

set -euo pipefail

echo "============================================================"
echo " [Cardeal Ltda] Configurando VM 2 - Servicos (SERVICOS)     "
echo "============================================================"

sudo hostnamectl set-hostname SERVICOS

LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | sed -n '2p')
[ -z "$LAN_IF" ] && LAN_IF="enp0s8"

# 1. Configuracao de IP Estatico 192.168.10.2/24 via Netplan
sudo tee /etc/netplan/99-lan.yaml > /dev/null <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $LAN_IF:
      addresses:
        - 192.168.10.2/24
EOF

sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply

# 2. Instalacao dos 4 Servicos Corporativos
sudo systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<< "postfix postfix/mailname string cardeal.local"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
sudo apt-get update -y
sudo apt-get install -y bind9 bind9utils apache2 samba postfix dovecot-imapd mailutils net-tools curl

# 3. DNS (BIND9 - cardeal.local)
sudo tee /etc/bind/named.conf.options > /dev/null <<'EOF'
options {
    directory "/var/cache/bind";
    recursion yes;
    allow-query { any; };
    forwarders {
        192.168.10.1;
        8.8.8.8;
    };
    dnssec-validation no;
    listen-on { any; };
    listen-on-v6 { any; };
};
EOF

sudo tee /etc/bind/named.conf.local > /dev/null <<'EOF'
zone "cardeal.local" {
    type master;
    file "/etc/bind/db.cardeal.local";
};
EOF

sudo tee /etc/bind/db.cardeal.local > /dev/null <<'EOF'
$TTL    604800
@       IN      SOA     ns1.cardeal.local. admin.cardeal.local. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.cardeal.local.
@       IN      MX  10  mail.cardeal.local.

ns1     IN      A       192.168.10.2
gateway IN      A       192.168.10.1
www     IN      A       192.168.10.2
mail    IN      A       192.168.10.2
EOF

sudo named-checkzone cardeal.local /etc/bind/db.cardeal.local
sudo systemctl restart named
sudo systemctl enable named

# 4. Servidor Web (Apache2 - www.cardeal.local)
sudo mkdir -p /var/www/cardeal
sudo tee /var/www/cardeal/index.html > /dev/null <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><title>Cardeal Ltda.</title></head>
<body>
  <h1>Cardeal Ltda. - Intranet Corporativa</h1>
  <p>Servidor Web Apache operacional em www.cardeal.local (192.168.10.2).</p>
</body>
</html>
EOF

sudo tee /etc/apache2/sites-available/cardeal.conf > /dev/null <<'EOF'
<VirtualHost *:80>
    ServerName www.cardeal.local
    ServerAlias cardeal.local
    DocumentRoot /var/www/cardeal
</VirtualHost>
EOF

sudo a2dissite 000-default.conf || true
sudo a2ensite cardeal.conf
sudo systemctl restart apache2
sudo systemctl enable apache2

# 5. Servidor de Arquivos (Samba / SMB)
sudo mkdir -p /srv/samba/projetos /srv/samba/producao
sudo chmod -R 0777 /srv/samba

if ! grep -q "\[projetos\]" /etc/samba/smb.conf; then
sudo tee -a /etc/samba/smb.conf > /dev/null <<'EOF'

[projetos]
   comment = Projetos Cardeal Ltda
   path = /srv/samba/projetos
   browseable = yes
   read only = no
   guest ok = yes

[producao]
   comment = Controle de Producao
   path = /srv/samba/producao
   browseable = yes
   read only = no
   guest ok = yes
EOF
fi

sudo systemctl restart smbd
sudo systemctl enable smbd

# 6. Correio Eletronico (Postfix SMTP + Dovecot IMAP)
sudo postconf -e "myhostname = mail.cardeal.local"
sudo postconf -e "mydomain = cardeal.local"
sudo postconf -e "myorigin = /etc/mailname"
sudo postconf -e "mydestination = cardeal.local, mail.cardeal.local, localhost.localdomain, localhost"
sudo postconf -e "mynetworks = 127.0.0.0/8 192.168.10.0/24"
sudo postconf -e "home_mailbox = Maildir/"
sudo postconf -e "inet_interfaces = all"
sudo postconf -e "inet_protocols = ipv4"

for u in joao maria; do
    sudo useradd -m -s /bin/bash "$u" 2>/dev/null || true
    echo "$u:cardeal123" | sudo chpasswd
    sudo mkdir -p "/home/$u/Maildir"
    sudo chown -R "$u:$u" "/home/$u/Maildir"
done

sudo sed -i 's|#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
sudo sed -i 's|disable_plaintext_auth = yes|disable_plaintext_auth = no|' /etc/dovecot/conf.d/10-auth.conf
sudo systemctl restart postfix dovecot
sudo systemctl enable postfix dovecot

echo "============================================================"
echo " [OK] VM 2 - Servicos (SERVICOS) configurada e operacional! "
echo "============================================================"
