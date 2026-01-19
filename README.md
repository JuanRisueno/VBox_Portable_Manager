# VBox Portable Manager

![Bash](https://img.shields.io/badge/Lenguaje-Bash-4EAA25?style=flat-square)
![Plataforma](https://img.shields.io/badge/Plataforma-Linux-blue?style=flat-square)
![Licencia](https://img.shields.io/badge/Licencia-MIT-grey?style=flat-square)

**VBox Portable Manager** es una utilidad avanzada en Bash diseñada para automatizar la sincronización, reparación y registro de máquinas virtuales de VirtualBox entre entornos Linux heterogéneos (por ejemplo, perfiles móviles o discos SSD externos moviéndose entre diferentes distribuciones).

Esta herramienta asegura la portabilidad entre entornos incompatibles (como Arch Linux vs Ubuntu LTS) gestionando dinámicamente el mapeo de rutas, las inconsistencias de permisos y el versionado de configuraciones.

## 📋 Contexto y Problemática

Mover máquinas virtuales en medios externos entre diferentes sistemas anfitriones suele generar incidencias críticas:
* **Inconsistencia de Rutas:** Los puntos de montaje varían (`/media`, `/run/media`, `/mnt`) rompiendo las rutas absolutas.
* **Conflictos de UUID:** Errores `VERR_UUID_EXISTS` causados por la duplicación de discos o clonaciones manuales.
* **Denegación de Permisos:** Discrepancias en UID/GID entre el usuario del sistema doméstico y el corporativo/educativo.
* **Corrupción de Ficheros XML:** Archivos de definición `.vbox` que quedan inválidos al cambiar de versión de hipervisor.

Este script actúa como un **aprovisionador sin estado (stateless)**, escaneando el medio de almacenamiento y forzando al registro local de VirtualBox a coincidir con la realidad física del disco.

## ⚙️ Funcionalidades Clave

### 1. Detección Agnóstica del Entorno
Detecta automáticamente el punto de montaje relativo a la ejecución del script. Elimina la necesidad de rutas estáticas, soportando la estructura de directorios de cualquier distribución Linux.

### 2. Reescritura Dinámica de Rutas
Analiza y parchea los ficheros de configuración XML (`.vbox`) al vuelo utilizando `sed`. Actualiza las rutas absolutas de los discos duros (`.vdi`) y snapshots para coincidir con el sistema anfitrión actual.

### 3. Normalización de Permisos
Detecta conflictos de propiedad en el sistema de ficheros. Si el usuario actual no tiene permisos de escritura (común al cambiar de usuario entre Casa/Trabajo), el script eleva privilegios automáticamente vía `sudo` para normalizar los permisos (chown/chmod).

### 4. Resolución de Conflictos de UUID
Detecta identificadores de disco duplicados (común en entornos de laboratorio con VMs clonadas). El script automáticamente:
* Genera nuevos UUIDs para la máquina y el medio de almacenamiento.
* Parchea las cabeceras internas de los archivos `.vdi`.
* Actualiza la configuración de la VM para mapear los nuevos identificadores.

### 5. Regeneración Automática de Configuración (RCM)
Si un fichero de configuración `.vbox` es irrecuperable o incompatible con la versión del host:
* El sistema inicia un **proceso de reconstrucción**.
* Crea un contenedor VM nuevo y limpio coincidiendo con el Tipo de SO y Firmware (BIOS/EFI) originales.
* Identifica y reconecta el disco `.vdi` original.
* **Resultado:** Recuperación total de datos y servicio, evitando la pérdida por corrupción de XML.

## 🚀 Uso

1.  Conectar el SSD externo que contiene el directorio `VirtualBox_VMs`.
2.  Navegar al directorio del script.
3.  Ejecutar la herramienta:

```bash
chmod +x Vbox-Portable-Manager.sh
./Vbox-Portable-Manager.sh
