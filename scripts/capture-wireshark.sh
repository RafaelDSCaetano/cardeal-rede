#!/usr/bin/env bash
# ==============================================================================
# AUTOMACAO DAS 4 CAPTURAS WIRESHARK / TSHARK (VM 3 - CLIENTE)
# ==============================================================================

set -euo pipefail

LAN_IF=$(ip -o link show | awk -F': ' '{print $2}' | grep -E '^en|^eth' | sed -n '2p')
[ -z "$LAN_IF" ] && LAN_IF="enp0s8"

OUTPUT_DIR="/tmp/caps"
mkdir -p "$OUTPUT_DIR"

echo "============================================================"
echo " INICIANDO CAPTURAS WIRESHARK NA INTERFACE: $LAN_IF"
echo "============================================================"

# 1. CAPTURA DHCP (Ciclo DORA)
echo -e "\n[1/4] Capturando DHCP (UDP 67/68)..."
tshark -i "$LAN_IF" -f "udp port 67 or udp port 68" -a duration:6 -w "$OUTPUT_DIR/dhcp.pcapng" &
sleep 1
sudo dhclient -r "$LAN_IF" && sudo dhclient -v "$LAN_IF"
wait

# 2. CAPTURA DNS (www.cardeal.local)
echo -e "\n[2/4] Capturando DNS (UDP 53)..."
tshark -i "$LAN_IF" -f "udp port 53" -a duration:6 -w "$OUTPUT_DIR/dns.pcapng" &
sleep 1
dig @192.168.10.2 www.cardeal.local +short
wait

# 3. CAPTURA HTTP (TCP Handshake + GET http://www.cardeal.local/)
echo -e "\n[3/4] Capturando HTTP (TCP 80)..."
tshark -i "$LAN_IF" -f "tcp port 80" -a duration:6 -w "$OUTPUT_DIR/http.pcapng" &
sleep 1
curl -s http://www.cardeal.local/ > /dev/null
wait

# 4. CAPTURA E-MAIL SMTP (TCP 25)
echo -e "\n[4/4] Capturando E-mail SMTP (TCP 25)..."
tshark -i "$LAN_IF" -f "tcp port 25" -a duration:6 -w "$OUTPUT_DIR/email.pcapng" &
sleep 1
swaks --to joao@cardeal.local --from maria@cardeal.local --server mail.cardeal.local --body "Captura manual SMTP" --suppress-data
wait

echo -e "\n============================================================"
echo " TODAS AS 4 CAPTURAS CONCLUIDAS EM $OUTPUT_DIR:"
ls -lh "$OUTPUT_DIR"/*.pcapng
echo "============================================================"
