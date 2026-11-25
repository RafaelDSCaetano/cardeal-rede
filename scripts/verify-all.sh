#!/usr/bin/env bash
# ==============================================================================
# SCRIPT DE DIAGNOSTICO E VERIFICACAO COMPLETA (Rodar na VM 3 - Cliente)
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================================${NC}"
echo -e "${BLUE}   DIAGNOSTICO DA INFRAESTRUTURA - CARDEAL LTDA (VM 3)      ${NC}"
echo -e "${BLUE}============================================================${NC}\n"

PASS=0
FAIL=0

test_cmd() {
    local desc="$1"
    local cmd="$2"
    echo -n "Testando: $desc ... "
    if eval "$cmd" > /dev/null 2>&1; then
        echo -e "${GREEN}[OK]${NC}"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}[FALHA]${NC}"
        FAIL=$((FAIL + 1))
    fi
}

# 1. CAMADA DE REDE (IP e Conectividade)
echo -e "${YELLOW}--- [1] CAMADA DE REDE (IPv4, Gateway e Internet) ---${NC}"
MY_IP=$(ip -4 -br addr show enp0s8 2>/dev/null | awk '{print $3}' || ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.10\.\d+')
echo "IP LAN do Cliente (enp0s8): $MY_IP"

test_cmd "Ping para o Gateway (192.168.10.1)" "ping -c 2 -W 2 192.168.10.1"
test_cmd "Ping para o Servidor de Servicos (192.168.10.2)" "ping -c 2 -W 2 192.168.10.2"
test_cmd "Conectividade externa via NAT/Gateway (HTTP example.com)" "curl -s -I --max-time 5 http://example.com | grep -q 'HTTP/'"

# 2. CAMADA DE TRANSPORTE (Portas Abertas na VM 2)
echo -e "\n${YELLOW}--- [2] CAMADA DE TRANSPORTE (Portas TCP/UDP nos Servidores) ---${NC}"
test_cmd "Porta UDP 53 (DNS) aberta na VM 2" "nc -z -u -w 2 192.168.10.2 53"
test_cmd "Porta TCP 80 (HTTP) aberta na VM 2" "nc -z -w 2 192.168.10.2 80"
test_cmd "Porta TCP 25 (SMTP) aberta na VM 2" "nc -z -w 2 192.168.10.2 25"
test_cmd "Porta TCP 143 (IMAP) aberta na VM 2" "nc -z -w 2 192.168.10.2 143"
test_cmd "Porta TCP 445 (SMB) aberta na VM 2" "nc -z -w 2 192.168.10.2 445"

# 3. CAMADA DE APLICACAO (Servicos e Protocolos)
echo -e "\n${YELLOW}--- [3] CAMADA DE APLICACAO (DNS, Web, SMB, E-mail) ---${NC}"

# DNS
test_cmd "Resolucao DNS: www.cardeal.local -> 192.168.10.2" "dig @192.168.10.2 www.cardeal.local +short | grep -q '192.168.10.2'"
test_cmd "Resolucao DNS: mail.cardeal.local -> 192.168.10.2" "dig @192.168.10.2 mail.cardeal.local +short | grep -q '192.168.10.2'"
test_cmd "Resolucao DNS: Registro MX de cardeal.local" "dig @192.168.10.2 cardeal.local MX +short | grep -q 'mail.cardeal.local'"

# Web HTTP
test_cmd "Requisicao HTTP: curl http://www.cardeal.local/ (Codigo 200)" "curl -s -o /dev/null -w '%{http_code}' http://www.cardeal.local/ | grep -q '200'"

# SMB / Samba
test_cmd "Listagem de compartilhamento SMB (//192.168.10.2/projetos)" "smbclient -L //192.168.10.2 -N | grep -qi 'projetos'"

# E-mail SMTP
test_cmd "Envio de e-mail SMTP via swaks (maria@cardeal.local -> joao@cardeal.local)" "swaks --to joao@cardeal.local --from maria@cardeal.local --server 192.168.10.2 --body 'Teste diagnostico automatizado' --suppress-data --timeout 5"

# RESUMO FINAL
echo -e "\n${BLUE}============================================================${NC}"
echo -e "RESULTADO DO DIAGNOSTICO: ${GREEN}$PASS sucessos${NC} / ${RED}$FAIL falhas${NC}"
if [ "$FAIL" -eq 0 ]; then
    echo -e "${GREEN}>>> TODOS OS SERVICOS ESTAO OPERANDO PERFEITAMENTE! <<<${NC}"
else
    echo -e "${YELLOW}>>> Verifique os servicos que falharam acima. <<<${NC}"
fi
echo -e "${BLUE}============================================================${NC}"
