#!/bin/bash
# =================================================================
#   VBOX PORTABLE MANAGER
#   Herramienta de sincronización y reparación automatizada para VirtualBox.
#
#   Funcionalidades:
#   - Detección Dinámica de Puntos de Montaje
#   - Reescritura de Rutas Absolutas
#   - Normalización de Permisos de Sistema
#   - Resolución de Conflictos de UUID
#   - Regeneración Automática de Configuración (ACR)
# =================================================================

# Paleta de colores para logs
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Cabecera de ejecución
echo -e "${YELLOW}=================================================${NC}"
echo -e "${YELLOW}   VBOX PORTABLE MANAGER                         ${NC}"
echo -e "${YELLOW}   Estado: Sincronización y Reconstrucción       ${NC}"
echo -e "${YELLOW}=================================================${NC}"

# 1. AUTO-DETECCIÓN DE ENTORNO
echo "🔍 Escaneando medio de almacenamiento..."
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

if [ -d "$SCRIPT_DIR/VirtualBox_VMs" ]; then
    SSD_MOUNT="$SCRIPT_DIR"
else
    FOUND_PATH=$(find /media /run/media /mnt -maxdepth 4 -type d -name "VirtualBox_VMs" 2>/dev/null | head -n 1)
    if [ -n "$FOUND_PATH" ]; then
        SSD_MOUNT=$(dirname "$FOUND_PATH")
    else
        echo -e "${RED}❌ ERROR CRÍTICO: No se encuentra el directorio 'VirtualBox_VMs'.${NC}"; exit 1
    fi
fi
SSD_VMS_DIR="$SSD_MOUNT/VirtualBox_VMs"
echo -e "   📂 Directorio Activo: ${BLUE}$SSD_MOUNT${NC}"

# 2. LIMPIEZA DE REGISTROS PREVIOS (Stateless)
echo "🧹 Purgando sesiones obsoletas en VirtualBox..."
# Desregistrar VMs para evitar conflictos de UUID
VBoxManage list vms | while read line; do
    if [[ $line =~ \{(.*)\} ]]; then
        VBoxManage unregistervm "${BASH_REMATCH[1]}" >/dev/null 2>&1
    fi
done
# Liberar manejadores de discos retenidos
VBoxManage list hdds | while read line; do
    if [[ $line =~ UUID:\ *([a-f0-9-]+) ]]; then
        VBoxManage closemedium disk "${BASH_REMATCH[1]}" >/dev/null 2>&1
    fi
done

# 3. VERIFICACIÓN Y CORRECCIÓN DE PERMISOS
if ! touch "$SSD_VMS_DIR/.perm_check" 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Permisos insuficientes detectados. Elevando privilegios...${NC}"
    sudo chown -R $(id -u):$(id -g) "$SSD_VMS_DIR"
    sudo find "$SSD_VMS_DIR" -type d -exec chmod 775 {} +
    sudo find "$SSD_VMS_DIR" -type f -exec chmod 664 {} +
    echo -e "${GREEN}✅ Permisos normalizados.${NC}"
else
    rm "$SSD_VMS_DIR/.perm_check"
fi

# 4. MOTOR DE PROCESAMIENTO
echo "🚀 Iniciando procesamiento de máquinas virtuales..."
COUNT=0
RECOVERED=0

while read vbox_file; do
    vm_name=$(basename "$vbox_file" .vbox)
    vm_dir=$(dirname "$vbox_file")

    # --- FASE A: REPARACIÓN DE RUTAS ---
    # Corrección heurística de rutas absolutas en el XML
    if grep -q "location=\"/" "$vbox_file"; then
        CHECK_PATH=$(grep "location=\"/" "$vbox_file" | head -1 | sed -n 's/.*location="\([^"]*\)".*/\1/p')
        if [[ "$CHECK_PATH" != "$SSD_VMS_DIR"* ]]; then
             OLD_ROOT=$(echo "$CHECK_PATH" | sed 's|\(.*VirtualBox_VMs\).*|\1|')
             [ -n "$OLD_ROOT" ] && sed -i "s|$OLD_ROOT|$SSD_VMS_DIR|g" "$vbox_file"
        fi
    fi

    # --- FASE B: REGISTRO Y RECONSTRUCCIÓN ---
    # Intento de registro estándar
    OUT=$(VBoxManage registervm "$vbox_file" 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "  [+] ${GREEN}$vm_name${NC}"
        ((COUNT++))
    else
        # FALLO DE REGISTRO -> INICIAR RECONSTRUCCIÓN AUTOMÁTICA (ACR)

        # Localizar el volumen lógico (.vdi) principal
        REAL_VDI=$(find "$vm_dir" -maxdepth 1 -name "*.vdi" -type f -printf "%s\t%p\n" | sort -rn | head -1 | cut -f2-)

        if [ -n "$REAL_VDI" ]; then
            # Definir nombre para la instancia recuperada
            NEW_NAME="${vm_name}_RECOVERED"

            # Detección de Firmware (BIOS vs EFI)
            FIRMWARE="bios"
            if grep -i "Firmware type=\"EFI\"" "$vbox_file" >/dev/null 2>&1; then
                FIRMWARE="efi"
            fi

            # Detección de Tipo de Sistema Operativo
            OSTYPE="Linux_64" # Default
            if [[ "${vm_name,,}" == *"windows"* ]] || [[ "${vm_name,,}" == *"server"* ]] || [[ "${vm_name,,}" == *"w10"* ]] || [[ "${vm_name,,}" == *"w11"* ]]; then
                OSTYPE="Windows2019_64"
            fi

            # 1. Aprovisionar nuevo contenedor VM
            VBoxManage createvm --name "$NEW_NAME" --ostype "$OSTYPE" --register >/dev/null 2>&1

            # 2. Configurar Hardware Virtual
            VBoxManage modifyvm "$NEW_NAME" --memory 4096 --cpus 2 --firmware "$FIRMWARE" --graphicscontroller vboxsvga --usbehci on >/dev/null 2>&1

            # 3. Configurar Controladora de Almacenamiento
            VBoxManage storagectl "$NEW_NAME" --name "SATA" --add sata --controller IntelAHCI >/dev/null 2>&1

            # 4. Regenerar UUID del medio físico (Evita colisión de firmas)
            VBoxManage internalcommands sethduuid "$REAL_VDI" >/dev/null 2>&1

            # 5. Vincular volumen existente
            ATTACH_OUT=$(VBoxManage storageattach "$NEW_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$REAL_VDI" 2>&1)

            if [ $? -eq 0 ]; then
                echo -e "  [+] ${GREEN}$vm_name${NC} (Reconstruida como $NEW_NAME)"
                ((COUNT++))
                ((RECOVERED++))
            else
                # Error crítico (normalmente snapshots encadenados rotos)
                VBoxManage unregistervm "$NEW_NAME" --delete >/dev/null 2>&1
                echo -e "  [!] ${RED}$vm_name${NC}: Error de dependencia en snapshot. No se puede reconstruir automáticamente."
            fi
        fi
    fi
done < <(find "$SSD_VMS_DIR" -name "*.vbox" -type f 2>/dev/null)

echo
echo -e "${GREEN}✨ OPERACIÓN COMPLETADA.${NC}"
echo -e "   ✅ Máquinas Disponibles: $COUNT"
if [ $RECOVERED -gt 0 ]; then
    echo -e "   ⚠️  Máquinas Reconstruidas: $RECOVERED (Sufijo: _RECOVERED)"
fi
echo
