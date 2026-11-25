#!/usr/bin/env bash
# ==============================================================================
# PROJETO CARDEAL LTDA - CLONAGEM E CONFIGURACAO DAS 3 VMS (CONJUNTO 2)
# Executar no terminal do notebook físico (fora das VMs)
# ==============================================================================

set -euo pipefail

BASE_VM="VM-BASE"
INT_NET="rede_cardeal"

echo "============================================================"
echo " [Cardeal Ltda] Clonando e Configurando VMs a partir de $BASE_VM"
echo "============================================================"

if ! VBoxManage showvminfo "$BASE_VM" &>/dev/null; then
    echo "[ERRO] Maquina '$BASE_VM' nao encontrada no VirtualBox!"
    VBoxManage list vms
    exit 1
fi

VM_STATE=$(VBoxManage showvminfo "$BASE_VM" --machinereadable | grep -E '^VMState=' | cut -d'=' -f2 | tr -d '"')
if [ "$VM_STATE" != "poweroff" ]; then
    echo "[INFO] Desligando $BASE_VM para clonagem segura..."
    VBoxManage controlvm "$BASE_VM" poweroff 2>/dev/null || true
    sleep 3
fi

echo -e "\n--- [1/3] Criando VM Gateway (SSH: 2301) ---"
VBoxManage clonevm "$BASE_VM" --name "Gateway" --register --mode all
VBoxManage modifyvm "Gateway" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2301,,22"
VBoxManage modifyvm "Gateway" --nic2 intnet --intnet2 "$INT_NET"

echo -e "\n--- [2/3] Criando VM Servicos (SSH: 2302) ---"
VBoxManage clonevm "$BASE_VM" --name "Servicos" --register --mode all
VBoxManage modifyvm "Servicos" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2302,,22"
VBoxManage modifyvm "Servicos" --nic2 intnet --intnet2 "$INT_NET"

echo -e "\n--- [3/3] Criando VM Cliente (SSH: 2303) ---"
VBoxManage clonevm "$BASE_VM" --name "Cliente" --register --mode all
VBoxManage modifyvm "Cliente" --nic1 nat --natpf1 "ssh,tcp,127.0.0.1,2303,,22"
VBoxManage modifyvm "Cliente" --nic2 intnet --intnet2 "$INT_NET"

echo -e "\n============================================================"
echo " CLONAGEM CONCLUIDA COM SUCESSO! (Rede Interna: $INT_NET)"
echo "   - Gateway:  ssh -p 2301 user@127.0.0.1"
echo "   - Servicos: ssh -p 2302 user@127.0.0.1"
echo "   - Cliente:  ssh -p 2303 user@127.0.0.1"
echo "============================================================"
