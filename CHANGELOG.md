# Changelog

Todas las modificaciones notables de este proyecto serán documentadas en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/).

## [4.1] - 2026-01-21
### Añadido
- **Deep Path Surgery (Soporte de Snapshots):** Nueva lógica de inspección profunda que detecta y repara enlaces rotos en cadenas de instantáneas (Snapshots), permitiendo arrancar máquinas con estados guardados.
- **Normalización Dinámica de Rutas:** El script analiza el XML del archivo `.vbox`, identifica rutas absolutas obsoletas (ej. de usuarios anteriores) y las actualiza quirúrgicamente con la ruta real del sistema actual.
### Corregido
- **Error de "Medium Not Found":** Solucionado el fallo crítico al mover máquinas virtuales entre distribuciones con diferentes puntos de montaje (ej. `/run/media/user` vs `/media/user`), garantizando portabilidad total entre Arch, Ubuntu, Fedora, etc.

## [3.2] - 2026-01-20
### Añadido
- **Garbage Collection (Auto-Clean):** Implementada lógica para detectar máquinas virtuales irrecuperables (sin disco `.vdi`).
- **Limpieza Automática:** El sistema ahora elimina los archivos `.vbox` huérfanos y las carpetas vacías resultantes para mantener la higiene del disco.

## [3.1] - 2026-01-20
### Corregido
- **Gestión de Permisos (Cross-User):** Solucionado el error de "Acceso Denegado" al mover el disco entre equipos con diferentes usuarios (Linux/Windows).
### Añadido
- **Elevación de Privilegios:** Se ha integrado una solicitud de `sudo` al inicio para aplicar permisos universales (`chmod 777`) en el volumen de forma recursiva.
- **Detección de Entorno:** Lógica para diferenciar si el script corre en un disco de sistema o en una unidad portable.

## [2.0] - 2025-12-XX
### Añadido
- **ACR (Automated Crash Recovery):** Sistema para reconstruir máquinas virtuales cuando falla el registro por conflicto de UUID.
- **Sincronización Stateless:** Limpieza proactiva de sesiones inválidas en VirtualBox antes de intentar el registro.
- **Smart Skip:** Prevención de duplicados en la recuperación de máquinas.

## [1.0] - 2025-10-XX
### Inicial
- **Funcionalidad Base:** Escaneo recursivo de archivos `.vbox` y registro simple mediante `VBoxManage`.
