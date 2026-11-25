# Guia Completo Passo a Passo — Construção Manual do Conjunto 2 (`LAB-GATEWAY`, `LAB-SERVICOS`, `LAB-CLIENTE`)

**Projeto:** Infraestrutura de Rede Corporativa — Cardeal Ltda. (Redes de Computadores — UFPel)  
**Objetivo deste documento:** Registrar **todos os passos, comandos executados, testes realizados, dúvidas e erros reais encontrados com suas respectivas soluções** durante a montagem manual do zero do Conjunto 2.

---

## Visão Geral do Ambiente Montado (Conjunto 2)

| Máquina Virtual | Hostname | Adaptador 1 (`enp0s3`) | Adaptador 2 (`enp0s8`) | IP LAN (`rede_lab`) | Porta SSH (Host) |
| :--- | :--- | :--- | :--- | :--- | :---: |
| **`LAB-GATEWAY`** | `GATEWAY` / `LAB-GATEWAY` | NAT (WAN / SSH) | Rede Interna `rede_lab` | `192.168.10.1/24` *(Estático)* | `2301` |
| **`LAB-SERVICOS`** | `LAB-SERVICOS` | NAT (Admin / SSH) | Rede Interna `rede_lab` | `192.168.10.2/24` *(Estático)* | `2302` |
| **`LAB-CLIENTE`** | `CLIENTE` / `LAB-CLIENTE` | NAT (Admin / SSH) | Rede Interna `rede_lab` | `192.168.10.52` / `.53` *(DHCP)* | `2303` |

- **Sistema Operacional base:** Ubuntu Server 26.04.1 LTS (sem interface gráfica, clonado da `VM-BASE`).
- **Credenciais da VM:** usuário `user` / senha `senha`.
- **Sub-rede LAN:** `192.168.10.0/24` (Máscara `255.255.255.0`, Broadcast `192.168.10.255`).
- **Domínio Interno:** `cardeal.local`.

---

## FASE 1: Criação das 3 VMs Limpas no VirtualBox (Executado no Notebook)

Partindo da `VM-BASE` desligada, clonamos 3 máquinas independentes com novos endereços MAC (`--mode all`), configuramos a 1ª placa em NAT com redirecionamento de porta SSH para o host (`127.0.0.1`) e a 2ª placa na rede interna isolada `rede_lab`:

```bash
# Clone 1 - Gateway (SSH na porta 2301)
VBoxManage clonevm "VM-BASE" --name "LAB-GATEWAY" --register --mode all
VBoxManage modifyvm "LAB-GATEWAY" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2301,,22"
VBoxManage modifyvm "LAB-GATEWAY" --nic2 intnet --intnet2 "rede_lab"

# Clone 2 - Serviços (SSH na porta 2302)
VBoxManage clonevm "VM-BASE" --name "LAB-SERVICOS" --register --mode all
VBoxManage modifyvm "LAB-SERVICOS" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2302,,22"
VBoxManage modifyvm "LAB-SERVICOS" --nic2 intnet --intnet2 "rede_lab"

# Clone 3 - Cliente (SSH na porta 2303)
VBoxManage clonevm "VM-BASE" --name "LAB-CLIENTE" --register --mode all
VBoxManage modifyvm "LAB-CLIENTE" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2303,,22"
VBoxManage modifyvm "LAB-CLIENTE" --nic2 intnet --intnet2 "rede_lab"
```

### Ativação do SSH na `LAB-GATEWAY`
1. Ligamos a `LAB-GATEWAY` no VirtualBox e instalamos o servidor SSH no console dela:
   ```bash
   sudo apt update && sudo apt install -y openssh-server
   ```
2. Conectamos a partir do notebook via SSH e ajustamos o hostname:
   ```bash
   ssh -p 2301 user@127.0.0.1
   sudo hostnamectl set-hostname LAB-GATEWAY
   ```

---

## FASE 2: Configuração Manual da `LAB-GATEWAY` (`192.168.10.1`)

### 2.1. Verificação das placas e IP Estático via Netplan
Conferimos os nomes das placas (`ip -br link` $\rightarrow$ `enp0s3` e `enp0s8`) e criamos `/etc/netplan/99-lan.yaml`:

```bash
sudo nano /etc/netplan/99-lan.yaml
```
Conteúdo:
```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      addresses:
        - 192.168.10.1/24
```
Aplicação e verificação:
```bash
sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply
ip -br addr show enp0s8
```

### 2.2. Habilitação do Roteamento no Kernel (*IP Forwarding*)
```bash
echo "net.ipv4.ip_forward=1" | sudo tee /etc/sysctl.d/99-ipforward.conf
sudo sysctl --system
cat /proc/sys/net/ipv4/ip_forward   # Retornou: 1
```

### 2.3. Configuração do NAT (`MASQUERADE`) e Regras de `FORWARD` no `iptables`
```bash
sudo iptables -t nat -A POSTROUTING -o enp0s3 -j MASQUERADE
sudo iptables -A FORWARD -i enp0s8 -o enp0s3 -j ACCEPT
sudo iptables -A FORWARD -i enp0s3 -o enp0s8 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

---

### ⚠️ Erros e Dúvidas Encontrados na Fase 2 (e como foram resolvidos)

#### ❌ Erro 1: Trava do `apt` pelo `unattended-upgr` (PID 2516)
- **Sintoma:** Ao rodar `sudo DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent`, o terminal ficou preso em loop exibindo:
  > `Aguardando por trava de cache: Não foi possível obter a trava /var/lib/dpkg/lock-frontend. Ela está sendo mantida pelo processo 2516 (unattended-upgr)`
- **Causa:** O serviço de atualizações automáticas em segundo plano do Ubuntu iniciou sozinho logo após o boot.
- **Solução aplicada:**
  ```bash
  sudo systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service
  sudo kill -9 2516 2>/dev/null || true
  ```

#### ❌ Erro 2: Trava residual do processo filho `/usr/bin/dpkg` (PID 15655)
- **Sintoma:** Ao tentar executar `sudo dpkg --configure -a`, retornou:
  > `dpkg: erro: trava do banco de dados do dpkg foi travado pelo processo /usr/bin/dpkg com pid 15655`
- **Causa:** O `unattended-upgr` morto no passo anterior havia deixado um processo filho do `dpkg` ainda vivo segurando a trava.
- **Solução aplicada:**
  ```bash
  sudo kill -9 15655
  sudo dpkg --configure -a
  ```

#### ❌ Erro 3: Dependências desencontradas (`linux-generic` e conflito `ufw` × `iptables-persistent`)
- **Sintoma:** Ao tentar instalar `iptables-persistent` e `isc-dhcp-server`, o `apt` acusou:
  > `linux-generic : Depende: linux-headers-generic (= 7.0.0-44.44) mas 7.0.0-30.30 está para ser instalado`  
  > `ufw : Quebra: iptables-persistent mas 1.0.24 está para ser instalado`
- **Causa:** A atualização de kernel do `unattended-upgrades` havia sido interrompida no meio, e o pacote `ufw` (firewall padrão do Ubuntu) entra em conflito direto com o `iptables-persistent`.
- **Solução aplicada:** Reparar as dependências primeiro e remover o `ufw` (usando `ufw-`) durante a instalação:
  ```bash
  sudo DEBIAN_FRONTEND=noninteractive apt --fix-broken install -y
  sudo DEBIAN_FRONTEND=noninteractive apt install -y isc-dhcp-server iptables-persistent ufw-
  sudo netfilter-persistent save
  ```

---

### 2.4. Configuração do Servidor DHCP (`isc-dhcp-server`)
1. Definimos a placa de escuta em `/etc/default/isc-dhcp-server`:
   ```text
   INTERFACESv4="enp0s8"
   ```
2. Configuramos o escopo em `/etc/dhcp/dhcpd.conf`:
   ```text
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
   ```
3. Reiniciamos, habilitamos e verificamos:
   ```bash
   sudo systemctl restart isc-dhcp-server
   sudo systemctl enable isc-dhcp-server
   sudo systemctl status isc-dhcp-server
   ```

#### ❓ Dúvida 4: Terminal "preso" no `systemctl status` e sem destaque verde
- **Dúvida:** Ao ver a saída do `systemctl status isc-dhcp-server`, o terminal parecia travado sem aceitar novos comandos e a linha `active (running)` não estava colorida em verde.
- **Explicação / Solução:** O serviço estava funcionando perfeitamente (`Active: active (running)` e `Listening on LPF/enp0s8/08:00:27:43:a8:bd/192.168.10.0/24`). O terminal apenas havia aberto o paginador `less` para rolagem do log — bastou pressionar a tecla **`q`** para retornar ao prompt.

---

## FASE 3: Configuração Manual da `LAB-SERVICOS` (`192.168.10.2`)

### 3.1. Preparação, SSH e IP Estático
No console da `LAB-SERVICOS` (já parando preventivamente o `unattended-upgrades`):
```bash
sudo systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
sudo apt update && sudo apt install -y openssh-server
```
Acesso via SSH pelo notebook (`ssh -p 2302 user@127.0.0.1`), hostname e IP estático via Netplan:
```bash
sudo hostnamectl set-hostname LAB-SERVICOS

sudo tee /etc/netplan/99-lan.yaml <<'EOF'
network:
  version: 2
  renderer: networkd
  ethernets:
    enp0s8:
      addresses:
        - 192.168.10.2/24
EOF

sudo chmod 600 /etc/netplan/99-lan.yaml
sudo netplan apply
ping -c 3 192.168.10.1   # Confirmou conectividade na LAN (0% packet loss)
```

### 3.2. Instalação dos 4 Serviços Corporativos
```bash
sudo debconf-set-selections <<< "postfix postfix/mailname string cardeal.local"
sudo debconf-set-selections <<< "postfix postfix/main_mailer_type string 'Internet Site'"
sudo DEBIAN_FRONTEND=noninteractive apt install -y bind9 bind9utils apache2 samba postfix dovecot-imapd mailutils
```

### 3.3. Configuração do DNS (`BIND9` — Porta UDP/TCP 53)
```bash
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

sudo tee /etc/bind/named.conf.local <<'EOF'
zone "cardeal.local" {
    type master;
    file "/etc/bind/db.cardeal.local";
};
EOF

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

sudo named-checkzone cardeal.local /etc/bind/db.cardeal.local
sudo systemctl restart named
dig @127.0.0.1 www.cardeal.local +short   # Retornou: 192.168.10.2
```

### 3.4. Configuração do Servidor Web (`Apache2` — Porta TCP 80)
```bash
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
curl -I http://127.0.0.1   # Retornou: HTTP/1.1 200 OK
```

### 3.5. Configuração do Compartilhamento de Arquivos (`Samba / SMB` — Porta TCP 445)
```bash
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

### 3.6. Configuração do Correio Eletrônico (`Postfix` SMTP 25 + `Dovecot` IMAP 143)
```bash
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
```

### 3.7. Validação das 5 Portas na `LAB-SERVICOS`
```bash
ss -tulnp | grep -E ':(53|80|25|143|445)\b'
```
Todas as 5 portas (`53`, `80`, `25`, `143`, `445`) apareceram ativas e escutando.

---

## FASE 4: Configuração Manual da `LAB-CLIENTE` e Testes Ponta a Ponta

### 4.1. Preparação, SSH e Ferramentas de Cliente
No console da `LAB-CLIENTE`:
```bash
sudo systemctl stop unattended-upgrades apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
sudo apt update && sudo apt install -y openssh-server
```
Via SSH pelo notebook (`ssh -p 2303 user@127.0.0.1`):
```bash
sudo hostnamectl set-hostname LAB-CLIENTE
sudo debconf-set-selections <<< "wireshark-common wireshark-common/install-setuid boolean true"
sudo DEBIAN_FRONTEND=noninteractive apt install -y curl dnsutils smbclient swaks tshark isc-dhcp-client
```

### 4.2. Ativação do DHCP na Placa Interna (`enp0s8`) com Prioridade de Rota
```bash
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
ip -br addr show enp0s8   # Recebeu IP dinâmico na faixa 192.168.10.50-150
```

### 4.3. Ajuste do DNS Local (Resolução de `.local`)
> **Contexto (Erro 5 prevenido):** No Ubuntu, `curl http://www.cardeal.local` falhava com `curl: (6) Could not resolve host: www.cardeal.local` porque o `systemd-resolved` intercepta nomes `.local` como mDNS (RFC 6762) e a placa NAT (`enp0s3`) concorria com o DNS da LAN.

**Solução aplicada na `LAB-CLIENTE`:**
```bash
sudo systemctl disable --now systemd-resolved
sudo rm -f /etc/resolv.conf
printf "nameserver 192.168.10.2\nsearch cardeal.local\n" | sudo tee /etc/resolv.conf
sudo sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf
```

### 4.4. Testes de Validação Ponta a Ponta
Todos os 5 testes foram executados e aprovados na `LAB-CLIENTE`:
```bash
# 1. DNS
dig www.cardeal.local +short         # -> 192.168.10.2
dig cardeal.local MX +short          # -> 10 mail.cardeal.local.

# 2. Web (HTTP)
curl http://www.cardeal.local        # -> HTML da Cardeal Ltda.

# 3. Arquivos (SMB)
smbclient -L //192.168.10.2 -N       # -> Listou 'projetos' e 'producao'

# 4. E-mail (SMTP)
swaks --to joao@cardeal.local --from maria@cardeal.local --server mail.cardeal.local --body "Teste manual do laboratorio!"

# 5. Internet externa via Gateway/NAT
ip route get 8.8.8.8                 # -> via 192.168.10.1 dev enp0s8
curl -I --max-time 5 http://example.com   # -> HTTP/1.1 200 OK
```

> **Nota sobre Teste de Roteamento na Rede da UFPel (`WUFPEL-Anglo`):**  
> Ao testar a perda/retorno de conectividade com `ping -I enp0s8 -c 3 8.8.8.8`, o comando retornou `100% packet loss` mesmo com `ip_forward=1`. Verificamos que o `iptables` estava traduzindo os pacotes corretamente (`MASQUERADE` e `FORWARD` com contadores crescentes) e que `curl -I http://example.com` respondia `HTTP/1.1 200 OK` (`Via: 1.1 WUFPEL-Anglo`). Concluiu-se que o firewall da rede Wi-Fi da universidade bloqueia ICMP externo, sendo o `curl -I http://example.com` o teste ideal para demonstrar o funcionamento (e o bloqueio ao definir `ip_forward=0`) do Gateway.

---

## FASE 5: Capturas Manuais com `tshark` / Wireshark

### ⚠️ Erros e Ajustes Encontrados na Fase 5

#### ❌ Erro 6: `tshark: The file "/tmp/caps/dhcp.pcapng" doesn't exist`
- **Causa:** Ao iniciar `sudo tshark ... &` em segundo plano antes de autenticar a senha do `sudo` (ou sem permissão na pasta `/tmp/caps`), o processo suspendeu esperando entrada no terminal sem criar o arquivo.
- **Solução:** Pré-autenticar o `sudo` (`sudo -v`) ou eliminar a necessidade de `sudo` no `tshark`, além de usar `-a duration:6` + `wait` para encerramento automático limpo sem depender de `pkill`.

#### ❌ Erro 7: `tshark: You don't have permission to read the file "/tmp/caps/dhcp.pcapng"` (e como rodar `tshark` sem `sudo`)
- **Causa:** Arquivos gravados com `sudo tshark` ficam com dono `root:root` e permissão `600`, impedindo leitura e cópia via `scp` pelo usuário `user`.
- **Solução definitiva aplicada na `LAB-CLIENTE`:** Adicionar `user` ao grupo `wireshark` e transferir a posse da pasta `/tmp/caps`:
  ```bash
  sudo usermod -aG wireshark user
  mkdir -p /tmp/caps
  sudo chown -R user:user /tmp/caps
  newgrp wireshark
  ```

---

### Execução das 4 Capturas Limpas (sem `sudo` no `tshark`)

```bash
# 1. DHCP (Ciclo DORA - UDP 67/68)
tshark -i enp0s8 -f "udp port 67 or udp port 68" -a duration:6 -w /tmp/caps/dhcp.pcapng &
sleep 1
sudo dhclient -r enp0s8 && sudo dhclient -v enp0s8
wait
tshark -r /tmp/caps/dhcp.pcapng

# 2. DNS (Consulta e Resposta - UDP 53)
tshark -i enp0s8 -f "udp port 53" -a duration:6 -w /tmp/caps/dns.pcapng &
sleep 1
dig @192.168.10.2 www.cardeal.local +short
wait
tshark -r /tmp/caps/dns.pcapng

# 3. HTTP (Handshake TCP + GET / - TCP 80)
tshark -i enp0s8 -f "tcp port 80" -a duration:6 -w /tmp/caps/http.pcapng &
sleep 1
curl -s http://www.cardeal.local/ > /dev/null
wait
tshark -r /tmp/caps/http.pcapng

# 4. E-mail SMTP (TCP 25)
tshark -i enp0s8 -f "tcp port 25" -a duration:6 -w /tmp/caps/email.pcapng &
sleep 1
swaks --to joao@cardeal.local --from maria@cardeal.local --server mail.cardeal.local --body "Captura manual SMTP" --suppress-data
wait
tshark -r /tmp/caps/email.pcapng
```

### Transferência das Capturas para o Notebook (via `scp`)
No terminal do notebook físico:
```bash
scp -P 2303 user@127.0.0.1:/tmp/caps/*.pcapng ~/RedesComputadores/wireshark/
```

### Resumo das Evidências Reais Obtidas no Conjunto 2
1. **`dhcp.pcapng` (5 pacotes):** `Release` (`192.168.10.52` $\rightarrow$ `.1`), `Discover` (`0.0.0.0` $\rightarrow$ `255.255.255.255`, MAC `08:00:27:e1:45:53`), `Offer` (`192.168.10.1` $\rightarrow$ `192.168.10.53`), `Request` (`0.0.0.0` $\rightarrow$ `255.255.255.255`) e `ACK` (`192.168.10.1` $\rightarrow$ `192.168.10.53`).
2. **`dns.pcapng` (2 pacotes):** Query `53363+ A? www.cardeal.local.` (`192.168.10.52:34607` $\rightarrow$ `192.168.10.2:53`) e resposta autoritativa `A 192.168.10.2`.
3. **`http.pcapng` (10 pacotes):** Handshake TCP (`SYN`, `SYN-ACK`, `ACK` na porta `57774` $\rightarrow$ `80`), `GET / HTTP/1.1` com **`Host: www.cardeal.local`** (`http://www.cardeal.local/`), `HTTP/1.1 200 OK` e encerramento `FIN/ACK`.
4. **`email.pcapng` (22 pacotes):** Handshake TCP iniciado pelo cliente (`192.168.10.52:40460` $\rightarrow$ `192.168.10.2:25`), banner `220 mail.cardeal.local ESMTP Postfix (Ubuntu)`, `EHLO CLIENTE`, `MAIL FROM:<maria@cardeal.local>`, `RCPT TO:<joao@cardeal.local>`, `DATA`, confirmação `250 2.0.0 Ok: queued as A592AE113B` e `QUIT`.
