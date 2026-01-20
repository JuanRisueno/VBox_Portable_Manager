#!/bin/bash
# ==============================================================================
# VBOX PORTABLE MANAGER - SUITE DE AUTOMATIZACIÓN
# ==============================================================================
# Descripción:  Script de automatización avanzada para entornos VirtualBox portables.
#               Gestiona permisos, registro stateless, recuperación de fallos (ACR)
#               y limpieza automática de configuraciones huérfanas (Auto-Clean).
#
# Funciones:    1. Normalización Global de Permisos (sudo)
#               2. Detección Inteligente del Punto de Montaje
#               3. Limpieza de Sesiones Stateless
#               4. ACR (Recuperación) + Garbage Collection (Limpieza de Huérfanos)
#
# Autor:        https://github.com/JuanRisueno
# Versión:      3.2 (Auto-Clean/Profesional)
# ==============================================================================

# --- Configuración y Estilos ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # Sin Color

clear
echo -e "${YELLOW}================================================================${NC}"
echo -e "${YELLOW}   VBOX PORTABLE MANAGER (v3.2)                                 ${NC}"
echo -e "${YELLOW}   Estado del Sistema: Inicializando...                         ${NC}"
echo -e "${YELLOW}================================================================${NC}"

# ==============================================================================
# FASE 1: DETECCIÓN DE ENTORNO Y NORMALIZACIÓN DE PERMISOS
# ==============================================================================

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MOUNT_POINT=$(stat -c %m "$SCRIPT_DIR")

if [[ "$MOUNT_POINT" == "/" ]] || [[ "$MOUNT_POINT" == "/home"* ]]; then
    SEARCH_ROOT="$SCRIPT_DIR"
    echo -e " [INFO] Ejecutando en disco del sistema. Alcance restringido a: ${BLUE}$SEARCH_ROOT${NC}"
else
    SEARCH_ROOT="$MOUNT_POINT"
    echo -e " [INFO] Disco portable detectado. Escaneo completo en: ${BLUE}$SEARCH_ROOT${NC}"
fi

echo -e " [INFO] Verificando integridad de permisos del sistema de archivos..."
echo -e " ${YELLOW}[REQ] Se requieren privilegios sudo para desbloquear carpetas entre usuarios.${NC}"

if sudo timeout 30s chmod -R 777 "$SEARCH_ROOT"; then
    echo -e " ${GREEN}[OK] Permisos normalizados. Acceso universal garantizado.${NC}"
else
    echo -e " ${RED}[WARN] Fallo al actualizar permisos. Algunas MVs podrían ser inaccesibles.${NC}"
fi

echo "----------------------------------------------------------------"

# ==============================================================================
# FASE 2: LIMPIEZA DE SESIONES STATELESS
# ==============================================================================

echo -e " [INFO] Limpiando sesiones obsoletas..."

VBoxManage list vms | while read line; do
    if [[ $line =~ \{(.*)\} ]]; then
        VBoxManage unregistervm "${BASH_REMATCH[1]}" >/dev/null 2>&1
    fi
done

VBoxManage list hdds | while read line; do
    if [[ $line =~ UUID:\ *([a-f0-9-]+) ]]; then
        VBoxManage closemedium disk "${BASH_REMATCH[1]}" >/dev/null 2>&1
    fi
done

# ==============================================================================
# FASE 3: MOTOR DE DESCUBRIMIENTO Y REGISTRO
# ==============================================================================

mapfile -t FOUND_VMS < <(find "$SEARCH_ROOT" -xdev -name "*.vbox" -type f 2>/dev/null)

if [ ${#FOUND_VMS[@]} -eq 0 ]; then
    echo -e " ${RED}[ERR] No se encontraron Máquinas Virtuales en el área escaneada.${NC}"
    exit 0
fi

echo -e " [INFO] MVs Detectadas: ${#FOUND_VMS[@]}. Iniciando sincronización..."
echo "----------------------------------------------------------------"

COUNT=0
RECOVERED=0
DELETED=0

for vbox_file in "${FOUND_VMS[@]}"; do
    vm_name=$(basename "$vbox_file" .vbox)
    vm_dir=$(dirname "$vbox_file")

    # --- INTENTO 1: Registro Estándar ---
    OUT=$(VBoxManage registervm "$vbox_file" 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "  [+] ${GREEN}$vm_name${NC}"
        ((COUNT++))
    else
        # ======================================================================
        # FASE 4: ACR & GARBAGE COLLECTION
        # ======================================================================

        # 1. Buscar VDI
        REAL_VDI=$(find "$vm_dir" -maxdepth 1 -name "*.vdi" -type f -printf "%s\t%p\n" | sort -rn | head -1 | cut -f2-)

        # --- LÓGICA DE LIMPIEZA (AUTO-CLEAN) ---
        if [ -z "$REAL_VDI" ]; then
             echo -e "  [♻️] ${PURPLE}$vm_name${NC}: Sin disco asociado. Eliminando archivo huérfano..."

             # Borramos el .vbox
             rm "$vbox_file"
             ((DELETED++))

             # Intentamos borrar la carpeta solo si ha quedado vacía
             if rmdir "$vm_dir" 2>/dev/null; then
                echo -e "      -> Carpeta vacía eliminada."
             fi
             continue
        fi
        # ---------------------------------------

        # 2. Definir Nombre Recuperado
        NEW_NAME="${vm_name}_RECOVERED"

        # 3. SMART SKIP
        if VBoxManage list vms | grep -q "\"$NEW_NAME\""; then
            echo -e "  [i] ${BLUE}$vm_name${NC}: Recuperación activa ($NEW_NAME). Omitiendo duplicado."
            continue
        fi

        # 4. RECONSTRUCCIÓN
        FIRMWARE="bios"
        if grep -i "Firmware type=\"EFI\"" "$vbox_file" >/dev/null 2>&1; then FIRMWARE="efi"; fi

        OSTYPE="Linux_64"
        if [[ "${vm_name,,}" == *"windows"* ]] || [[ "${vm_name,,}" == *"server"* ]] || [[ "${vm_name,,}" == *"w10"* ]] || [[ "${vm_name,,}" == *"w11"* ]]; then
            OSTYPE="Windows2019_64"
        fi

        VBoxManage createvm --name "$NEW_NAME" --ostype "$OSTYPE" --register >/dev/null 2>&1
        VBoxManage modifyvm "$NEW_NAME" --memory 4096 --cpus 2 --firmware "$FIRMWARE" --graphicscontroller vboxsvga --usbehci on >/dev/null 2>&1
        VBoxManage storagectl "$NEW_NAME" --name "SATA" --add sata --controller IntelAHCI >/dev/null 2>&1
        VBoxManage internalcommands sethduuid "$REAL_VDI" >/dev/null 2>&1
        VBoxManage storageattach "$NEW_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$REAL_VDI" >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo -e "  [+] ${GREEN}$vm_name${NC} -> ${YELLOW}(RECUPERADA como $NEW_NAME)${NC}"
            ((COUNT++))
            ((RECOVERED++))
        else
            VBoxManage unregistervm "$NEW_NAME" --delete >/dev/null 2>&1
            echo -e "  [!] ${RED}$vm_name${NC}: Fallo Crítico (Imposible recuperar)."
        fi
    fi
done

# ==============================================================================
# RESUMEN FINAL
# ==============================================================================
echo
echo -e "${GREEN}✨ OPERACIÓN COMPLETADA.${NC}"
echo -e "   ✅ Máquinas Activas:     $COUNT"
if [ $RECOVERED -gt 0 ]; then
    echo -e "   🆕  Máquinas Recuperadas: $RECOVERED"
fi
if [ $DELETED -gt 0 ]; then
    echo -e "   🗑️  Huérfanos Eliminados: $DELETED"
fi
echo
