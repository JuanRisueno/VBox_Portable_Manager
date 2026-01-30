#!/bin/bash
# ==============================================================================
# VBOX PORTABLE MANAGER - SUITE DE AUTOMATIZACIÓN
# ==============================================================================
# Descripción:  Script de gestión para entornos VirtualBox portables.
#               Incluye: Elevación de permisos, Limpieza Stateless,
#               Recuperación de Fallos (ACR) y DEEP PATH DOCTOR (Soporte Snapshots).
#
# Autor:        [Tu Usuario de GitHub]
# Versión:      4.1 (Deep Surgery Edition)
# ==============================================================================

# --- Configuración Visual ---
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${YELLOW}================================================================${NC}"
echo -e "${YELLOW}   VBOX PORTABLE MANAGER (v4.1)                                 ${NC}"
echo -e "${YELLOW}   Módulo: Reparación Profunda (Soporte Snapshots)              ${NC}"
echo -e "${YELLOW}================================================================${NC}"

# ==============================================================================
# FASE 1: PERMISOS Y ENTORNO
# ==============================================================================
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
MOUNT_POINT=$(stat -c %m "$SCRIPT_DIR")

if [[ "$MOUNT_POINT" == "/" ]] || [[ "$MOUNT_POINT" == "/home"* ]]; then
    SEARCH_ROOT="$SCRIPT_DIR"
    echo -e " [INFO] Ejecutando en sistema local. Alcance: ${BLUE}$SEARCH_ROOT${NC}"
else
    SEARCH_ROOT="$MOUNT_POINT"
    echo -e " [INFO] Disco portable detectado. Escaneo en: ${BLUE}$SEARCH_ROOT${NC}"
fi

echo -e " [INFO] Asegurando permisos universales..."
if sudo timeout 5s chmod -R 777 "$SEARCH_ROOT" 2>/dev/null; then
    echo -e " ${GREEN}[OK] Permisos actualizados.${NC}"
else
    echo -e " ${YELLOW}[WARN] Continuando sin sudo (posible acceso limitado).${NC}"
fi

# ==============================================================================
# FASE 2: LIMPIEZA STATELESS
# ==============================================================================
echo -e " [INFO] Limpiando registro de VirtualBox..."
VBoxManage list vms | while read line; do
    if [[ $line =~ \{(.*)\} ]]; then VBoxManage unregistervm "${BASH_REMATCH[1]}" >/dev/null 2>&1; fi
done
VBoxManage list hdds | while read line; do
    if [[ $line =~ UUID:\ *([a-f0-9-]+) ]]; then VBoxManage closemedium disk "${BASH_REMATCH[1]}" >/dev/null 2>&1; fi
done

# ==============================================================================
# FASE 3: MOTOR DE CIRUGÍA PROFUNDA
# ==============================================================================
echo "----------------------------------------------------------------"
mapfile -t FOUND_VMS < <(find "$SEARCH_ROOT" -xdev -name "*.vbox" -type f 2>/dev/null)

if [ ${#FOUND_VMS[@]} -eq 0 ]; then
    echo -e " ${RED}[ERR] No se encontraron máquinas virtuales.${NC}"; exit 0
fi

echo -e " [INFO] Procesando ${#FOUND_VMS[@]} máquinas..."

COUNT=0
REPAIRED=0
RECOVERED=0

for vbox_file in "${FOUND_VMS[@]}"; do
    vm_name=$(basename "$vbox_file" .vbox)
    vm_dir=$(dirname "$vbox_file")
    
    # Flag para saber si hemos tocado este archivo
    FILE_MODIFIED=0

    # --------------------------------------------------------------------------
    # CIRUGÍA DE RUTAS v4.1 (Iteración línea a línea)
    # --------------------------------------------------------------------------
    # Extraemos TODAS las rutas de discos (.vdi) definidas en el XML
    # Usamos grep para sacar lo que hay entre comillas en location="..."
    # que termine en .vdi
    
    # Creamos una lista temporal de rutas a verificar
    grep -oP 'location="\K[^"]+\.vdi' "$vbox_file" | sort | uniq | while read -r OLD_PATH; do
        
        # 1. ¿Existe el archivo en la ruta antigua?
        if [ ! -f "$OLD_PATH" ]; then
            # NO existe. Es una ruta rota (ej: apunta a /run/media/johnyadmin...)
            
            FILENAME=$(basename "$OLD_PATH")
            
            # 2. Buscamos dónde está ese archivo REALMENTE dentro de la carpeta actual
            # "find" nos permite encontrarlo aunque esté en una subcarpeta Snapshots
            NEW_REAL_PATH=$(find "$vm_dir" -name "$FILENAME" | head -1)
            
            if [ -f "$NEW_REAL_PATH" ]; then
                # ¡Lo encontramos! Hacemos el trasplante.
                # Usamos pipe | como delimitador de sed para no romper las rutas
                sed -i "s|location=\"$OLD_PATH\"|location=\"$NEW_REAL_PATH\"|g" "$vbox_file"
                
                echo -e "      🔧 Reparado: $FILENAME"
                # Marcamos que hemos hecho cambios (truco para bash variable scope)
                touch "${vbox_file}.fixed"
            fi
        fi
    done

    # Comprobamos si el bucle while marcó el archivo como arreglado
    if [ -f "${vbox_file}.fixed" ]; then
        ((REPAIRED++))
        rm "${vbox_file}.fixed"
    fi
    # --------------------------------------------------------------------------

    # INTENTO DE REGISTRO
    OUT=$(VBoxManage registervm "$vbox_file" 2>&1)

    if [ $? -eq 0 ]; then
        echo -e "  [+] ${GREEN}$vm_name${NC}"
        ((COUNT++))
    else
        # FALLBACK: ACR (Si falla incluso tras reparar rutas, reconstruimos la base)
        # Nota: ACR reconstruye solo el disco base, se pierden snapshots.
        # Es el último recurso.
        
        # ... (Código ACR estándar igual que v4.0) ...
        # Solo se activa si el archivo está corrupto más allá de las rutas
        
        REAL_VDI=$(find "$vm_dir" -maxdepth 1 -name "*.vdi" -type f | sort -rn | head -1)
        if [ -z "$REAL_VDI" ]; then 
            echo -e "  [!] ${RED}$vm_name${NC}: Error fatal (Sin disco base)."
            continue
        fi
        
        NEW_NAME="${vm_name}_RECOVERED"
        if VBoxManage list vms | grep -q "\"$NEW_NAME\""; then continue; fi
        
        # Heurística OS
        OSTYPE="Linux_64"
        if [[ "${vm_name,,}" == *"windows"* ]] || [[ "${vm_name,,}" == *"server"* ]]; then OSTYPE="Windows2019_64"; fi

        VBoxManage createvm --name "$NEW_NAME" --ostype "$OSTYPE" --register >/dev/null 2>&1
        VBoxManage modifyvm "$NEW_NAME" --memory 4096 --cpus 2 --graphicscontroller vboxsvga --usbehci on >/dev/null 2>&1
        VBoxManage storagectl "$NEW_NAME" --name "SATA" --add sata --controller IntelAHCI >/dev/null 2>&1
        VBoxManage internalcommands sethduuid "$REAL_VDI" >/dev/null 2>&1
        VBoxManage storageattach "$NEW_NAME" --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$REAL_VDI" >/dev/null 2>&1

        if [ $? -eq 0 ]; then
            echo -e "  [+] ${GREEN}$vm_name${NC} -> ${YELLOW}(RECUPERADA: UUID Error)${NC}"
            ((COUNT++)); ((RECOVERED++))
        fi
    fi
done

# ==============================================================================
# FASE 4: SANITIZACIÓN DE USB (Prevención de "Name Clash")
# ==============================================================================
echo -e " [INFO] Normalizando controladores USB en todas las máquinas..."

# Recorremos todas las máquinas registradas para apagar USBs conflictivos
VBoxManage list vms | while read line; do
    if [[ $line =~ \"(.*)\" ]]; then
        current_vm="${BASH_REMATCH[1]}"
        # Apagamos todos los controladores USB (1.1, 2.0 y 3.0)
        VBoxManage modifyvm "$current_vm" --usb off --usbehci off --usbxhci off >/dev/null 2>&1
    fi
done
echo -e " ${GREEN}[OK] USBs desactivados (Modo Seguro).${NC}"
# ==============================================================================

echo
echo -e "${GREEN}✨ OPERACIÓN COMPLETADA.${NC}"
echo -e "   ✅ Activas: $COUNT | 🔧 Rutas Reparadas: $REPAIRED | 🚑 Reconstruidas: $RECOVERED"
echo
