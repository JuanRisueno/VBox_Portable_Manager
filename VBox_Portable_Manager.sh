#!/bin/bash
# =================================================================
#   VBOX PORTABLE MANAGER (Versión Inteligente)
#   Funcionalidades:
#   - Búsqueda Global y Recursiva
#   - Sincronización Stateless
#   - ACR con DETECCIÓN DE DUPLICADOS (Smart Skip)
# =================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=================================================${NC}"
echo -e "${YELLOW}   VBOX PORTABLE MANAGER                         ${NC}"
echo -e "${YELLOW}   Estado: Inteligencia Anti-Duplicados          ${NC}"
echo -e "${YELLOW}=================================================${NC}"

# 1. AUTO-DETECCIÓN INTELIGENTE
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MOUNT_POINT=$(stat -c %m "$SCRIPT_DIR")

if [[ "$MOUNT_POINT" == "/" ]] || [[ "$MOUNT_POINT" == "/home"* ]]; then
    SEARCH_ROOT="$SCRIPT_DIR"
    echo -e "⚠️  Script en disco de sistema. Escaneando solo: ${BLUE}$SEARCH_ROOT${NC}"
else
    SEARCH_ROOT="$MOUNT_POINT"
    echo -e "🔍 Escaneando volumen completo: ${BLUE}$SEARCH_ROOT${NC}"
fi

# 2. BÚSQUEDA DE MÁQUINAS
mapfile -t FOUND_VMS < <(find "$SEARCH_ROOT" -xdev -name "*.vbox" -type f 2>/dev/null)

if [ ${#FOUND_VMS[@]} -eq 0 ]; then
    echo; echo -e "${RED}❌ No tienes máquinas virtuales en este disco.${NC}"; echo
    exit 0
fi

echo -e "   📂 Máquinas detectadas: ${#FOUND_VMS[@]}"

# 3. LIMPIEZA DE SESIONES
echo "🧹 Purgando sesiones obsoletas..."
VBoxManage list vms | while read line; do
    if [[ $line =~ \{(.*)\} ]]; then VBoxManage unregistervm "${BASH_REMATCH[1]}" >/dev/null 2>&1; fi
done
VBoxManage list hdds | while read line; do
    if [[ $line =~ UUID:\ *([a-f0-9-]+) ]]; then VBoxManage closemedium disk "${BASH_REMATCH[1]}" >/dev/null 2>&1; fi
done

# 4. MOTOR DE PROCESAMIENTO
echo "🚀 Sincronizando..."
COUNT=0
RECOVERED=0

# Pre-cargamos la lista de lo que vamos a procesar para evitar duplicados en tiempo real
# (No es necesario en bash simple, lo haremos dinámico abajo)

for vbox_file in "${FOUND_VMS[@]}"; do
    vm_name=$(basename "$vbox_file" .vbox)
    vm_dir=$(dirname "$vbox_file")

    # FASE 0: Permisos
    if [ ! -w "$vbox_file" ]; then
        sudo chown -R $(id -u):$(id -g) "$vm_dir" >/dev/null 2>&1
        sudo chmod -R 775 "$vm_dir" >/dev/null 2>&1
    fi

    # FASE A: Reparación de Rutas
    REAL_VDI=$(find "$vm_dir" -maxdepth 1 -name "*.vdi" -type f -printf "%s\t%p\n" | sort -rn | head -1 | cut -f2-)
    if [ -n "$REAL_VDI" ]; then
        CURRENT_REF=$(grep ".vdi" "$vbox_file" | grep "location=" | head -1 | sed -n 's/.*location="\([^"]*\)".*/\1/p')
        if [ -n "$CURRENT_REF" ] && [ "$CURRENT_REF" != "$REAL_VDI" ]; then
             sed -i "s|location=\"$CURRENT_REF\"|location=\"$REAL_VDI\"|g" "$vbox_file"
        fi
    fi

    # FASE B: Intento de Registro
    OUT=$(VBoxManage registervm "$vbox_file" 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "  [+] ${GREEN}$vm_name${NC}"
        ((COUNT++))
    else
        # --- FASE C: LÓGICA DE RESCATE INTELIGENTE (ACR Smart) ---

        # 1. Definimos cómo se llamaría la versión arreglada
        NEW_NAME="${vm_name}_RECOVERED"

        # 2. CHECK INTELIGENTE: ¿Ya existe una máquina registrada con ese nombre?
        # Buscamos en la lista actual de VirtualBox si ya tenemos la versión _RECOVERED funcionando
        if VBoxManage list vms | grep -q "\"$NEW_NAME\""; then
            echo -e "  [i] ${BLUE}$vm_name${NC}: Detectada versión recuperada activa ($NEW_NAME). ${GREEN}Omitiendo duplicado.${NC}"
            # No hacemos nada, porque ya está arreglado de una ejecución anterior.
            continue
        fi

        # 3. Si no existe, procedemos a crearla
        if [ -n "$REAL_VDI" ]; then

            # Detectar Firmware y OS
            FIRMWARE="bios"
            if grep -i "Firmware type=\"EFI\"" "$vbox_file" >/dev/null 2>&1; then FIRMWARE="efi"; fi

            OSTYPE="Linux_64"
            if [[ "${vm_name,,}" == *"windows"* ]] || [[ "${vm_name,,}" == *"server"* ]] || [[ "${vm_name,,}" == *"w10"* ]] || [[ "${vm_name,,}" == *"w11"* ]]; then
                OSTYPE="Windows2019_64"
            fi

            # Reconstruir
            VBoxManage createvm --name "$NEW_NAME" --ostype "$OSTYPE" --register >/dev/null 2>&1
            VBoxManage modifyvm "$NEW_NAME" --memory 4096 --cpus 2 --firmware "$FIRMWARE" --graphicscontroller vboxsvga --usbehci on >/dev/null 2>&1
            VBoxManage storagectl "$NEW_NAME" --name "SATA" --add sata --controller IntelAHCI >/dev/null 2>&1
            VBoxManage internalcommands sethduuid "$REAL_VDI" >/dev/null 2>&1
            VBoxManage storageattach "$NEW_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$REAL_VDI" >/dev/null 2>&1

            if [ $? -eq 0 ]; then
                echo -e "  [+] ${GREEN}$vm_name${NC} (Reconstruida como $NEW_NAME)"
                ((COUNT++))
                ((RECOVERED++))
            else
                # Si falla, limpiamos
                VBoxManage unregistervm "$NEW_NAME" --delete >/dev/null 2>&1
                echo -e "  [!] ${RED}$vm_name${NC}: Error irrecuperable."
            fi
        fi
    fi
done

echo
echo -e "${GREEN}✨ OPERACIÓN COMPLETADA.${NC}"
echo -e "   ✅ Máquinas Listas: $COUNT"
if [ $RECOVERED -gt 0 ]; then
    echo -e "   🆕 Reconstrucciones Nuevas: $RECOVERED"
fi
echo
