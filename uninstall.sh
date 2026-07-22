#!/usr/bin/env bash
#
# uninstall-imperative-dots.sh
#
# Desinstalador para https://github.com/ilyamiro/imperative-dots (rama master)
# Revierte, en la medida de lo posible, lo que hace install.sh:
#   - Restaura (o elimina) las carpetas de ~/.config que install.sh sobrescribió
#   - Elimina el clon del repo, el archivo de versión y los wallpapers (opcional)
#   - Elimina las fuentes Iosevka Nerd Font instaladas por el script
#   - Revierte el tema/config de SDDM añadidos por el script
#   - Deshabilita los servicios systemd habilitados por el script
#   - Revuelve el shell por defecto a bash (si se cambió a zsh)
#   - Limpia las líneas añadidas a ~/.zshrc
#   - Opcionalmente desinstala los paquetes pacman/AUR que install.sh instaló
#
# NO toca: drivers de GPU (nvidia/mesa/etc.), NetworkManager, multilib,
# yay/paru, ni ningún display manager alternativo que hayas tenido antes:
# esas partes son demasiado riesgosas / específicas de tu hardware para
# revertir de forma automática y segura.
#
# Uso:
#   ./uninstall-imperative-dots.sh            # modo interactivo (recomendado)
#   ./uninstall-imperative-dots.sh --yes      # responde "sí" a todo
#   ./uninstall-imperative-dots.sh --dry-run  # solo muestra qué haría, no cambia nada
#   ./uninstall-imperative-dots.sh --purge    # además borra wallpapers y paquetes (con confirmación)
#
# ==============================================================================

set -uo pipefail

# ------------------------------------------------------------------------------
# Colores (mismo estilo que install.sh)
# ------------------------------------------------------------------------------
RESET="\e[0m"
BOLD="\e[1m"
DIM="\e[2m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_MAGENTA="\e[35m"

# ------------------------------------------------------------------------------
# Flags
# ------------------------------------------------------------------------------
ASSUME_YES=false
DRY_RUN=false
PURGE=false

while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --yes|-y) ASSUME_YES=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --purge) PURGE=true; shift ;;
        -h|--help)
            echo "Uso: $0 [--yes] [--dry-run] [--purge]"
            exit 0
            ;;
        *) shift ;;
    esac
done

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------
log_info()  { echo -e "${C_CYAN}[ INFO ]${RESET} $1"; }
log_ok()    { printf "  -> %-45s ${C_GREEN}[ OK ]${RESET}\n" "$1"; }
log_skip()  { printf "  -> %-45s ${DIM}[ SKIP ]${RESET}\n" "$1"; }
log_warn()  { echo -e "  -> ${C_YELLOW}$1${RESET}"; }
log_err()   { echo -e "  -> ${C_RED}$1${RESET}"; }

# Ejecuta un comando, o solo lo imprime si es --dry-run
run() {
    if [ "$DRY_RUN" = true ]; then
        echo -e "  ${DIM}[dry-run]\$ $*${RESET}"
    else
        "$@"
    fi
}

# Pregunta y/n. Devuelve 0 (true) si el usuario confirma.
confirm() {
    local prompt="$1"
    if [ "$ASSUME_YES" = true ]; then
        return 0
    fi
    local answer
    read -r -p "$(echo -e "${C_YELLOW}${prompt} [y/N]: ${RESET}")" answer
    [[ "$answer" =~ ^([yY][eE][sS]|[yY])$ ]]
}

# ------------------------------------------------------------------------------
# Detección de OS (misma lógica que install.sh)
# ------------------------------------------------------------------------------
if [ -f /etc/os-release ]; then
    DETECTED_OS=$(awk -F= '/^ID=/{gsub(/"/, "", $2); print $2}' /etc/os-release)
else
    log_err "No se pudo detectar el sistema operativo (/etc/os-release no encontrado)."
    exit 1
fi

case "$DETECTED_OS" in
    arch|endeavouros|manjaro|cachyos|parch|garuda) ;;
    *)
        echo -e "${C_RED}Sistema operativo no soportado ($DETECTED_OS). Este script solo funciona en Arch Linux y derivados.${RESET}"
        exit 1
        ;;
esac

echo -e "${BOLD}${C_MAGENTA}==================================================================${RESET}"
echo -e "${BOLD} Desinstalador de imperative-dots${RESET}"
echo -e "${BOLD}${C_MAGENTA}==================================================================${RESET}\n"

if [ "$DRY_RUN" = true ]; then
    log_warn "Modo --dry-run activo: no se modificará nada, solo se mostrará lo que se haría."
fi

if ! confirm "¿Deseas continuar con la desinstalación de imperative-dots?"; then
    echo "Cancelado."
    exit 0
fi

# ------------------------------------------------------------------------------
# Rutas usadas por install.sh
# ------------------------------------------------------------------------------
TARGET_CONFIG_DIR="$HOME/.config"
CLONE_DIR="$HOME/.hyprland-dots"
VERSION_FILE="$HOME/.local/state/imperative-dots-version"
TARGET_FONTS_DIR="$HOME/.local/share/fonts"
CAVA_WRAPPER="$HOME/.local/bin/cava"

CONFIG_FOLDERS=("cava" "hypr" "kitty" "rofi" "matugen" "zsh" "swayosd" "nvim")

# Wallpaper dir: intenta leer el que quedó guardado en el archivo de versión,
# igual que hace install.sh; si no existe, cae a ~/Pictures/Wallpapers
WALLPAPER_DIR=""
if [ -f "$VERSION_FILE" ]; then
    # shellcheck disable=SC1090
    source "$VERSION_FILE" 2>/dev/null || true
fi
if [ -z "${WALLPAPER_DIR:-}" ]; then
    USER_PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null)"
    [ -z "$USER_PICTURES_DIR" ] && USER_PICTURES_DIR="$HOME/Pictures"
    WALLPAPER_DIR="${USER_PICTURES_DIR%/}/Wallpapers"
fi

# ------------------------------------------------------------------------------
# 1. Servicios systemd habilitados por install.sh
# ------------------------------------------------------------------------------
log_info "Deshabilitando servicios systemd añadidos por imperative-dots..."

# EasyEffects (usuario)
if systemctl --user is-enabled easyeffects.service &>/dev/null; then
    run systemctl --user disable --now easyeffects.service 2>/dev/null || true
    log_ok "easyeffects.service (usuario) deshabilitado"
else
    log_skip "easyeffects.service no estaba habilitado"
fi

# SwayOSD libinput backend (sistema)
if systemctl is-enabled swayosd-libinput-backend.service &>/dev/null; then
    run sudo systemctl disable --now swayosd-libinput-backend.service 2>/dev/null || true
    log_ok "swayosd-libinput-backend.service deshabilitado"
else
    log_skip "swayosd-libinput-backend.service no estaba habilitado"
fi

# SDDM: solo se toca si el usuario confirma, porque puede ser tu único display manager
if systemctl is-enabled sddm.service &>/dev/null; then
    if confirm "SDDM está habilitado como display manager. ¿Deshabilitarlo? (hazlo solo si vas a configurar otro DM)"; then
        run sudo systemctl disable sddm.service 2>/dev/null || true
        log_ok "sddm.service deshabilitado"
    else
        log_skip "sddm.service se mantiene habilitado"
    fi
fi

# Nota: NetworkManager y power-profiles-daemon son servicios de sistema de uso
# general; no se deshabilitan automáticamente para no dejarte sin red/energía.
log_skip "NetworkManager.service y power-profiles-daemon.service se dejan como están (uso general del sistema)"

# ------------------------------------------------------------------------------
# 2. Tema y configuración de SDDM añadidos por install.sh
# ------------------------------------------------------------------------------
if [ -d /usr/share/sddm/themes/matugen-minimal ] || [ -f /etc/sddm.conf.d/10-wayland-matugen.conf ]; then
    log_info "Eliminando tema y configuración de SDDM instalados por el script..."
    if confirm "¿Eliminar el tema SDDM 'matugen-minimal' y su archivo de config en /etc/sddm.conf.d/?"; then
        run sudo rm -rf /usr/share/sddm/themes/matugen-minimal
        run sudo rm -f /etc/sddm.conf.d/10-wayland-matugen.conf
        log_ok "Tema y config de SDDM eliminados"
    else
        log_skip "Tema/config de SDDM se mantienen"
    fi
fi

# ------------------------------------------------------------------------------
# 3. Restaurar (o eliminar) las carpetas de ~/.config
#    Si existe un backup de install.sh (~/.config-backup-*), se restaura desde ahí.
# ------------------------------------------------------------------------------
log_info "Restaurando/eliminando carpetas de configuración en ~/.config..."

LATEST_BACKUP=$(ls -dt "$HOME"/.config-backup-* 2>/dev/null | head -n1 || true)

if [ -n "$LATEST_BACKUP" ]; then
    log_warn "Backup encontrado: $LATEST_BACKUP"
    if confirm "¿Restaurar tus configuraciones anteriores desde ese backup (donde existan)?"; then
        RESTORE_FROM_BACKUP=true
    else
        RESTORE_FROM_BACKUP=false
    fi
else
    log_skip "No se encontró ningún ~/.config-backup-* para restaurar"
    RESTORE_FROM_BACKUP=false
fi

for folder in "${CONFIG_FOLDERS[@]}"; do
    TARGET_PATH="$TARGET_CONFIG_DIR/$folder"

    if [ "$RESTORE_FROM_BACKUP" = true ] && [ -e "$LATEST_BACKUP/$folder" ]; then
        run rm -rf "$TARGET_PATH"
        run mv "$LATEST_BACKUP/$folder" "$TARGET_PATH"
        log_ok "Restaurado ~/.config/$folder desde backup"
    elif [ -e "$TARGET_PATH" ] || [ -L "$TARGET_PATH" ]; then
        run rm -rf "$TARGET_PATH"
        log_ok "Eliminado ~/.config/$folder"
    else
        log_skip "~/.config/$folder no existe"
    fi
done

# ------------------------------------------------------------------------------
# 4. Archivos GTK / Qt generados por install.sh (solo si coinciden con lo que
#    el script genera, para no borrar personalizaciones tuyas por accidente)
# ------------------------------------------------------------------------------
log_info "Revirtiendo theming de GTK/Qt añadido por matugen..."

for f in "$HOME/.config/gtk-3.0/gtk.css" "$HOME/.config/gtk-4.0/gtk.css"; do
    if [ -f "$f" ] && grep -q "matugen" "$f" 2>/dev/null; then
        run rm -f "$f"
        log_ok "Eliminado $f"
    fi
done

for f in "$HOME/.config/gtk-3.0/settings.ini" "$HOME/.config/gtk-4.0/settings.ini"; do
    if [ -f "$f" ] && grep -q "adw-gtk3-dark\|gtk-application-prefer-dark-theme" "$f" 2>/dev/null; then
        run rm -f "$f"
        log_ok "Eliminado $f"
    fi
done

for f in "$HOME/.config/qt5ct/qt5ct.conf" "$HOME/.config/qt6ct/qt6ct.conf"; do
    if [ -f "$f" ] && grep -q "matugen" "$f" 2>/dev/null; then
        run rm -f "$f"
        log_ok "Eliminado $f"
    fi
done

# ------------------------------------------------------------------------------
# 5. Wrapper de cava en ~/.local/bin
# ------------------------------------------------------------------------------
if [ -f "$CAVA_WRAPPER" ]; then
    run rm -f "$CAVA_WRAPPER"
    log_ok "Eliminado wrapper $CAVA_WRAPPER"
else
    log_skip "No hay wrapper de cava en ~/.local/bin"
fi

# ------------------------------------------------------------------------------
# 6. Fuentes Iosevka Nerd Font
# ------------------------------------------------------------------------------
log_info "Eliminando Iosevka Nerd Font instalada por el script..."

if [ -d "$TARGET_FONTS_DIR/IosevkaNerdFont" ]; then
    run rm -rf "$TARGET_FONTS_DIR/IosevkaNerdFont"
    log_ok "Eliminado $TARGET_FONTS_DIR/IosevkaNerdFont"
else
    log_skip "No se encontró IosevkaNerdFont en $TARGET_FONTS_DIR"
fi

if [ -d /usr/share/fonts/IosevkaNerdFont ]; then
    run sudo rm -rf /usr/share/fonts/IosevkaNerdFont
    log_ok "Eliminado /usr/share/fonts/IosevkaNerdFont"
else
    log_skip "No se encontró IosevkaNerdFont en /usr/share/fonts"
fi

command -v fc-cache &>/dev/null && run fc-cache -f &>/dev/null

# ------------------------------------------------------------------------------
# 7. Clon del repo y archivo de versión
# ------------------------------------------------------------------------------
if [ -d "$CLONE_DIR" ]; then
    run rm -rf "$CLONE_DIR"
    log_ok "Eliminado clon del repo en $CLONE_DIR"
else
    log_skip "$CLONE_DIR no existe"
fi

if [ -f "$VERSION_FILE" ]; then
    run rm -f "$VERSION_FILE"
    log_ok "Eliminado archivo de versión $VERSION_FILE"
else
    log_skip "Archivo de versión no encontrado"
fi

run rm -f "$HOME/.cache/quickshell/updater/update_pending"
run rm -f "$HOME/.local/state/quickshell/wallpaper_picker/wallpaper_initialized"

# ------------------------------------------------------------------------------
# 8. Wallpapers (destructivo: pueden ser fotos tuyas si reusaste la carpeta)
# ------------------------------------------------------------------------------
if [ -d "$WALLPAPER_DIR" ]; then
    if [ "$PURGE" = true ] || confirm "¿Eliminar también la carpeta de wallpapers ($WALLPAPER_DIR)?"; then
        run rm -rf "$WALLPAPER_DIR"
        log_ok "Eliminada carpeta de wallpapers $WALLPAPER_DIR"
    else
        log_skip "Carpeta de wallpapers conservada"
    fi
fi

# ------------------------------------------------------------------------------
# 9. Shell por defecto (zsh -> bash) y limpieza de ~/.zshrc
# ------------------------------------------------------------------------------
CURRENT_SHELL=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)
if [[ "$CURRENT_SHELL" == *zsh* ]]; then
    if confirm "Tu shell por defecto es zsh (posiblemente cambiado por install.sh). ¿Volver a bash?"; then
        if command -v bash &>/dev/null; then
            run chsh -s "$(command -v bash)" "$USER"
            log_ok "Shell por defecto cambiado a bash"
        else
            log_err "No se encontró bash en el sistema, no se cambió el shell"
        fi
    else
        log_skip "Shell se mantiene en zsh"
    fi
fi

ZSH_RC="$HOME/.zshrc"
if [ -f "$ZSH_RC" ]; then
    if confirm "¿Limpiar las líneas que install.sh añadió a ~/.zshrc (WALLPAPER_DIR, SCRIPT_DIR, alias de usuario)?"; then
        run sed -i '/# Dynamic System Paths/d' "$ZSH_RC"
        run sed -i '/export WALLPAPER_DIR=/d' "$ZSH_RC"
        run sed -i '/export SCRIPT_DIR=/d' "$ZSH_RC"
        run sed -i '/# Load User Aliases/d' "$ZSH_RC"
        run sed -i "\|source $TARGET_CONFIG_DIR/zsh/user_aliases.zsh|d" "$ZSH_RC"
        log_ok "Líneas añadidas por el script eliminadas de ~/.zshrc"
    else
        log_skip "~/.zshrc no modificado"
    fi
fi

# ------------------------------------------------------------------------------
# 10. Paquetes pacman/AUR (opcional, no se hace por defecto salvo --purge o confirmación)
# ------------------------------------------------------------------------------
ARCH_PKGS=(
    "hyprland" "hypridle" "kitty" "cava" "zbar" "pavucontrol" "alsa-utils" "awww" "networkmanager-dmenu-git"
    "wl-clipboard" "fd" "qt6-multimedia" "qt6-5compat" "ripgrep"
    "cliphist" "socat" "inotify-tools" "pamixer" "brightnessctl" "acpi" "iw"
    "bluez" "bluez-utils" "lm_sensors"
    "matugen-bin" "fastfetch" "quickshell-git" "python-websockets" "qt6-websockets"
    "grim" "playerctl" "satty" "yq" "slurp" "mpvpaper"
    "wmctrl" "easyeffects" "swayosd-git" "lsp-plugins" "hyprpolkitagent"
    "qt5-wayland" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects" "qt6-wayland"
    "qt5ct" "qt6ct" "gpu-screen-recorder" "adw-gtk-theme" "xdg-desktop-portal-wlr"
)
# Nota: paquetes de propósito general que install.sh también instala
# (git, python, wget, file, jq, curl, unzip, ffmpeg, imagemagick, bc,
# NetworkManager, pipewire y sus plugins, libnotify, xdg-desktop-portal-gtk,
# power-profiles-daemon, psmisc, nautilus) se excluyen deliberadamente de esta
# lista porque es muy probable que otras apps de tu sistema dependan de ellos.

echo ""
log_info "Paquetes específicos de imperative-dots que el script instaló:"
printf '  %s\n' "${ARCH_PKGS[@]}" | column -c 100 2>/dev/null || printf '  %s\n' "${ARCH_PKGS[@]}"
echo ""
log_warn "No se eliminan paquetes de sistema de uso general (git, python, NetworkManager, pipewire, etc.)."
log_warn "Los drivers de GPU (nvidia/mesa/vulkan-*) NUNCA se tocan: revísalos manualmente si los instalaste."

REMOVE_PKGS=false
if [ "$PURGE" = true ]; then
    REMOVE_PKGS=true
elif confirm "¿Desinstalar también los paquetes de arriba con pacman/yay?"; then
    REMOVE_PKGS=true
fi

if [ "$REMOVE_PKGS" = true ]; then
    if command -v yay &>/dev/null; then
        REMOVE_CMD=(yay -Rns --noconfirm)
    elif command -v paru &>/dev/null; then
        REMOVE_CMD=(paru -Rns --noconfirm)
    else
        REMOVE_CMD=(sudo pacman -Rns --noconfirm)
    fi

    FAILED_PKGS=()
    for pkg in "${ARCH_PKGS[@]}"; do
        if pacman -Qi "$pkg" &>/dev/null; then
            if [ "$DRY_RUN" = true ]; then
                echo -e "  ${DIM}[dry-run]\$ ${REMOVE_CMD[*]} $pkg${RESET}"
            else
                if "${REMOVE_CMD[@]}" "$pkg" &>/dev/null; then
                    log_ok "Paquete removido: $pkg"
                else
                    FAILED_PKGS+=("$pkg")
                    log_err "No se pudo remover: $pkg (puede ser dependencia de otro paquete)"
                fi
            fi
        else
            log_skip "$pkg no está instalado"
        fi
    done

    if [ ${#FAILED_PKGS[@]} -ne 0 ]; then
        echo -e "\n${C_YELLOW}Los siguientes paquetes no se pudieron remover automáticamente:${RESET}"
        for fp in "${FAILED_PKGS[@]}"; do
            echo -e "  - $fp"
        done
    fi
else
    log_skip "Desinstalación de paquetes omitida"
fi

# ------------------------------------------------------------------------------
# Resumen final
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}${C_GREEN}=================================================================${RESET}"
echo -e "${BOLD} Desinstalación de imperative-dots completada${RESET}"
echo -e "${BOLD}${C_GREEN}=================================================================${RESET}"
if [ "$DRY_RUN" = true ]; then
    echo -e "${C_YELLOW}Esto fue un --dry-run: no se modificó nada realmente.${RESET}"
fi
echo -e "Recomendado: reinicia sesión o el sistema para que los cambios de shell/servicios/tema surtan efecto."
