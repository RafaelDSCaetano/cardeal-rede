# Guia de Comandos Úteis e Capturas — Projeto Cardeal Ltda.

### Script 1.1 — Clone 1: `Gateway` (Porta SSH `2301`, Rede Interna `rede_cardeal`)

Clona a `VM-BASE` gerando novos MACs, configura a Placa 1 em NAT com encaminhamento SSH (`2301 -> 22`) e a Placa 2 na rede interna.

```sh
VBoxManage clonevm "VM-BASE" --name "Gateway" --register --mode all
VBoxManage modifyvm "Gateway" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2301,,22"
VBoxManage modifyvm "Gateway" --nic2 intnet --intnet2 "rede_cardeal"
```

### Script 1.2 — Clone 2: `Servicos` (Porta SSH `2302`, Rede Interna `rede_cardeal`)

Clona a `VM-BASE` para o servidor de serviços corporativos com SSH na porta `2302`.

```sh
VBoxManage clonevm "VM-BASE" --name "Servicos" --register --mode all
VBoxManage modifyvm "Servicos" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2302,,22"
VBoxManage modifyvm "Servicos" --nic2 intnet --intnet2 "rede_cardeal"
```

### Script 1.3 — Clone 3: `Cliente` (Porta SSH `2303`, Rede Interna `rede_cardeal`)

Clona a `VM-BASE` para a estação cliente com SSH na porta `2303`.

```sh
VBoxManage clonevm "VM-BASE" --name "Cliente" --register --mode all
VBoxManage modifyvm "Cliente" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2303,,22"
VBoxManage modifyvm "Cliente" --nic2 intnet --intnet2 "rede_cardeal"
```

---

## Configuração da VM `Gateway` (`192.168.10.1`)

`ssh -p 2301 user@127.0.0.1`

### Script 2.1 — IP Estático da Interface LAN (`enp0s8`) via Netplan

Define o endereço fixo `192.168.10.1/24` na placa interna.

```sh
sudo nano /etc/netplan/99-lan.yaml
```

Conteúdo do arquivo `/etc/netplan/99-lan.yaml`:

```
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      addresses:
        - 192.168.10.1/24
```

Ajuste de permissão e aplicação:

```sh
sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply
```

### Script 2.2 — Ativação do Roteamento no Kernel (*IP Forwarding*)

Habilita permanentemente o encaminhamento de pacotes IPv4 entre a LAN e a WAN.

```sh
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ipforward.conf
sudo sysctl --system
```

### Script 2.3 — Regras de NAT (`MASQUERADE`) e Encaminhamento (`iptables`)

Aplica a tradução de endereços de saída na placa WAN (`enp0s3`) e libera o tráfego da LAN (`enp0s8`) e suas respostas.

```sh
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
sudo iptables -A FORWARD -i enp0s3 -o enp0s8 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

### Script 2.4 — Persistência das Regras de `iptables`

Instala o `iptables-persistent` sem prompts interativos e grava as regras atuais para sobreviverem a reinicializações.

```sh
sudo DEBIAN_FRONTEND=noninteractive apt update && sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
sudo netfilter-persistent save
```

---

## Configuração da VM `Servicos` (`192.168.10.2`)

> `ssh -p 2302 user@127.0.0.1`

### Script 3.1 — IP Estático da Interface LAN (`enp0s8`) via Netplan

Fixa o IP `192.168.10.2/24` na placa interna.

```sh
sudo nano /etc/netplan/99-lan.yaml
```

Conteúdo do arquivo `/etc/netplan/99-lan.yaml`:

```
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      addresses:
        - 192.168.10.2/24
```

Aplicação e teste de conectividade com o Gateway (`192.168.10.1`):

```sh
sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply
ping -c 3 192.168.10.1
```

### Script 3.2 — Instalação dos 4 Serviços Corporativos (DNS, Web, Samba, E-mail)

Pré-configura o Postfix via `debconf-set-selections` e instala todos os pacotes necessários de uma vez.

```sh
sudo debconf-set-selections <<< "postfix postfix/mailname string cardeal.local"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
sudo DEBIAN_FRONTEND=noninteractive apt install -y bind9 bind9utils apache2 samba postfix dovecot-imapd mailutils
```

### Script 3.3 — Configuração do Servidor DNS (`BIND9` — `cardeal.local`)

Configura opções/forwarders, declara a zona master `cardeal.local`, cria os registros (`SOA`, `NS`, `MX`, `A`), valida e testa a resolução.

```sh
# Opções globais e forwarders
sudo tee /etc/bind/named.conf.options <<'EOF'
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

# Declaração da zona autoritativa
sudo tee /etc/bind/named.conf.local <<'EOF'
zone "cardeal.local" {
    type master;
    file "/etc/bind/db.cardeal.local";
};
EOF

# Arquivo de zona com registros NS, MX e A
sudo tee /etc/bind/db.cardeal.local <<'EOF'
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

# Validação, reinício e teste local
sudo named-checkzone cardeal.local /etc/bind/db.cardeal.local
sudo systemctl restart named
dig @127.0.0.1 www.cardeal.local +short
```

### Script 3.4 — Configuração do Servidor Web (`Apache2` — `www.cardeal.local`)

Cria a página institucional HTML, configura e ativa o *VirtualHost* `cardeal.conf` e testa o retorno HTTP.

```sh
# Página HTML institucional
sudo mkdir -p /var/www/cardeal
sudo tee /var/www/cardeal/index.html <<'EOF'
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="utf-8"><title>Cardeal Ltda.</title></head>
<body>
  <h1>Cardeal Ltda. - Intranet Corporativa</h1>
  <p>Servidor Web Apache operacional em www.cardeal.local (192.168.10.2).</p>
</body>
</html>
EOF

# VirtualHost e ativação do site
sudo tee /etc/apache2/sites-available/cardeal.conf <<'EOF'
<VirtualHost *:80>
    ServerName www.cardeal.local
    ServerAlias cardeal.local
    DocumentRoot /var/www/cardeal
</VirtualHost>
EOF

sudo a2dissite 000-default.conf
sudo a2ensite cardeal.conf
sudo systemctl restart apache2

# Teste HTTP local
curl -I http://127.0.0.1
```

### Script 3.5 — Configuração do Servidor de Arquivos (`Samba / SMB`)

Cria as pastas `/srv/samba/projetos` e `/srv/samba/producao`, adiciona os compartilhamentos ao `smb.conf` e reinicia o `smbd`.

```sh
sudo mkdir -p /srv/samba/projetos /srv/samba/producao
sudo chmod -R 0777 /srv/samba

sudo tee -a /etc/samba/smb.conf <<'EOF'

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

sudo systemctl restart smbd
```

### Script 3.6 — Configuração do Correio Eletrônico (`Postfix` SMTP \+ `Dovecot` IMAP)

Configura o Postfix para o domínio `cardeal.local`, cria os usuários `joao` e `maria` com caixas `Maildir`, ajusta o Dovecot e verifica todas as 5 portas ativas.

```sh
# Parâmetros do Postfix
sudo postconf -e "myhostname = mail.cardeal.local"
sudo postconf -e "mydomain = cardeal.local"
sudo postconf -e "myorigin = /etc/mailname"
sudo postconf -e "mydestination = cardeal.local, mail.cardeal.local, localhost.localdomain, localhost"
sudo postconf -e "mynetworks = 127.0.0.0/8 192.168.10.0/24"
sudo postconf -e "home_mailbox = Maildir/"
sudo postconf -e "inet_interfaces = all"
sudo postconf -e "inet_protocols = ipv4"

# Criação de usuários e caixas Maildir
for u in joao maria; do
    sudo useradd -m -s /bin/bash "$u" 2>/dev/null || true
    echo "$u:cardeal123" | sudo chpasswd
    sudo mkdir -p "/home/$u/Maildir"
    sudo chown -R "$u:$u" "/home/$u/Maildir"
done

# Ajustes do Dovecot e reinício dos serviços
sudo sed -i 's|#mail_location =.*|mail_location = maildir:~/Maildir|' /etc/dovecot/conf.d/10-mail.conf
sudo sed -i 's|disable_plaintext_auth = yes|disable_plaintext_auth = no|' /etc/dovecot/conf.d/10-auth.conf
sudo systemctl restart postfix dovecot

# Verificação das 5 portas (DNS 53, HTTP 80, SMTP 25, IMAP 143, SMB 445)
ss -tulnp | grep -E ':(53|80|25|143|445)\b'
```

---

## Configuração e Testes da VM `Cliente` (DHCP)

> `ssh -p 2303 user@127.0.0.1`

### Script 4.1 — Instalação das Ferramentas de Cliente e Análise

Instala `curl`, `dnsutils`, `smbclient`, `swaks`, `tshark` e `isc-dhcp-client`.

```sh
sudo debconf-set-selections <<< "wireshark-common wireshark-common/install-setuid boolean true"
sudo DEBIAN_FRONTEND=noninteractive apt install -y curl dnsutils smbclient swaks tshark isc-dhcp-client
```

### Script 4.2 — Ativação do DHCP na Placa Interna (`enp0s8`) com Prioridade de Rota

Configura a placa `enp0s8` para receber IP via DHCP com `route-metric: 50` (priorizando o Gateway `192.168.10.1`) e verifica o IP obtido.

```sh
sudo tee /etc/netplan/99-lan.yaml <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      dhcp4: true
      dhcp4-overrides:
        route-metric: 50
EOF

sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply
ip -br addr show enp0s8
```

### Script 4.3 — Ajuste de Resolução DNS Local (Domínio `.local`)

Desativa o `systemd-resolved` (evitando conflito mDNS com `.local`), aponta o `/etc/resolv.conf` diretamente para o BIND9 (`192.168.10.2`) e ajusta o `/etc/nsswitch.conf`.

```sh
sudo systemctl disable --now systemd-resolved
sudo rm -f /etc/resolv.conf
printf "nameserver 192.168.10.2\nsearch cardeal.local\n" | sudo tee /etc/resolv.conf
sudo sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
```

### Script 4.4 — Bateria de Testes Ponta a Ponta na `Cliente`

Valida todos os serviços (DNS, Web, SMB, E-mail e saída externa via Gateway/NAT).

```sh
# DNS
dig www.cardeal.local +short
dig cardeal.local MX +short

# Web (HTTP)
curl http://www.cardeal.local

# Arquivos (SMB)
smbclient -L //192.168.10.2 -N

# E-mail (SMTP)
swaks --to joao@cardeal.local --from maria@cardeal.local --server mail.cardeal.local --body "Teste manual do laboratorio!"

# Internet externa via Gateway/NAT
ip route get 8.8.8.8
curl -I --max-time 5 http://example.com
```

---

## Capturas com `tshark` e Abertura no Wireshark

> **Onde rodar:** Scripts 5.1 a 5.5 dentro da VM `Cliente`; Scripts 5.6 e 5.7 no terminal do notebook físico.

### Script 5.1 — Preparação Única para Capturar sem `sudo`

Adiciona o usuário `user` ao grupo `wireshark`, cria `/tmp/caps` com dono `user` e ativa o grupo na sessão atual.

```sh
sudo usermod -aG wireshark user
mkdir -p /tmp/caps
sudo chown -R user:user /tmp/caps
newgrp wireshark
```

### Script 5.2 — Captura do DHCP (UDP Portas 67 e 68 — Ciclo DORA)

Grava 6 segundos de tráfego DHCP enquanto renova o IP da `enp0s8` e exibe os pacotes capturados.

```sh
tshark -i enp0s8 -f "udp port 67 or udp port 68" -a duration:6 -w /tmp/caps/dhcp.pcapng &
sleep 1
sudo dhclient -r enp0s8 && sudo dhclient -v enp0s8
wait
tshark -r /tmp/caps/dhcp.pcapng
```

### Script 5.3 — Captura do DNS (UDP Porta 53 — Consulta e Resposta)

Grava a consulta `A` para `www.cardeal.local` e a resposta do servidor `192.168.10.2`.

```sh
tshark -i enp0s8 -f "udp port 53" -a duration:6 -w /tmp/caps/dns.pcapng &
sleep 1
dig @192.168.10.2 www.cardeal.local +short
wait
tshark -r /tmp/caps/dns.pcapng
```

### Script 5.4 — Captura do HTTP (TCP Porta 80 — Handshake \+ `GET`)

Grava o *Three-Way Handshake* TCP, a requisição `GET / HTTP/1.1` (`Host: www.cardeal.local`) e a resposta `200 OK`.

```sh
tshark -i enp0s8 -f "tcp port 80" -a duration:6 -w /tmp/caps/http.pcapng &
sleep 1
curl -s http://www.cardeal.local/ > /dev/null
wait
tshark -r /tmp/caps/http.pcapng
```

### Script 5.5 — Captura do E-mail (TCP Porta 25 — SMTP)

Grava a abertura TCP e toda a conversa SMTP de envio de `maria@cardeal.local` para `joao@cardeal.local`.

```sh
tshark -i enp0s8 -f "tcp port 25" -a duration:6 -w /tmp/caps/email.pcapng &
sleep 1
swaks --to joao@cardeal.local --from maria@cardeal.local --server mail.cardeal.local --body "Captura manual SMTP" --suppress-data
wait
tshark -r /tmp/caps/email.pcapng
```

### Script 5.6 — Transferência das Capturas para o Notebook (`scp`)

> **Onde rodar:** Terminal do notebook físico.

```sh
scp -P 2303 user@127.0.0.1:/tmp/caps/*.pcapng ~/RedesComputadores/wireshark/
```

```sh
wireshark ~/RedesComputadores/wireshark/dhcp.pcapng
wireshark ~/RedesComputadores/wireshark/dns.pcapng
wireshark ~/RedesComputadores/wireshark/http.pcapng
wireshark ~/RedesComputadores/wireshark/email.pcapng
```

