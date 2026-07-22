#!/usr/bin/env bash

# ==============================================================================
# Imperative Dots - Uninstaller Script
# ==============================================================================
# This script safely removes the imperative-dots installation and restores
# the system to a reasonable pre-installation state.
# ==============================================================================

# ==============================================================================
# Terminal UI Colors & Formatting
# ==============================================================================
RESET="\e[0m"
BOLD="\e[1m"
DIM="\e[2m"
C_BLUE="\e[34m"
C_CYAN="\e[36m"
C_GREEN="\e[32m"
C_YELLOW="\e[33m"
C_RED="\e[31m"
C_MAGENTA="\e[35m"

# ==============================================================================
# Script Variables
# ==============================================================================
VERSION_FILE="$HOME/.local/state/imperative-dots-version"
CLONE_DIR="$HOME/.hyprland-dots"
CONFIG_DIR="$HOME/.config"
BACKUP_SEARCH_DIR="$HOME"
FONTS_DIR="$HOME/.local/share/fonts"
WALLPAPERS_DIR=""
INSTALL_MARKER="$HOME/.config/hypr/settings.json"

# Flags
DRY_RUN=false
INTERACTIVE=true
RESTORE_BACKUPS=false
REMOVE_PACKAGES=false
REMOVE_ALL_CONFIG=false

# ==============================================================================
# Helper Functions
# ==============================================================================

print_header() {
    clear 
    printf "${BOLD}${C_CYAN}"
    cat << "EOF"
 ██╗██╗     ██╗   ██╗ █████╗ ███╗   ███╗██╗██████╗  ██████╗ 
 ██║██║     ╚██╗ ██╔╝██╔══██╗████╗ ████║██║██╔══██╗██╔═══██╗
 ██║██║      ╚████╔╝ ███████║██╔████╔██║██║██████╔╝██║   ██║
 ██║██║       ╚██╔╝  ██╔══██║██║╚██╔╝██║██║██╔══██╗██║   ██║
 ██║███████╗   ██║   ██║  ██║██║ ╚═╝ ██║██║██║  ██║╚██████╔╝
 ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝     ╚═╝╚═╝╚═╝  ╚═╝ ╚═════╝ 
                        UNINSTALLER
EOF
    printf "${RESET}\n"
}

log_info() {
    echo -e "${C_CYAN}[ INFO ]${RESET} $1"
}

log_success() {
    echo -e "${C_GREEN}[ OK ]${RESET} $1"
}

log_warning() {
    echo -e "${C_YELLOW}[ WARN ]${RESET} $1"
}

log_error() {
    echo -e "${C_RED}[ ERROR ]${RESET} $1"
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [ "$INTERACTIVE" = false ]; then
        [ "$default" = "y" ] && return 0 || return 1
    fi
    
    if [ "$default" = "y" ]; then
        read -p "$(echo -e "${BOLD}$prompt${RESET} (Y/n): ")" response
        [[ -z "$response" || "$response" =~ ^[Yy]$ ]] && return 0 || return 1
    else
        read -p "$(echo -e "${BOLD}$prompt${RESET} (y/N): ")" response
        [[ "$response" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# ==============================================================================
# Parse Command Line Arguments
# ==============================================================================
parse_arguments() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --dry-run) DRY_RUN=true; shift ;;
            --non-interactive) INTERACTIVE=false; shift ;;
            --restore-backups) RESTORE_BACKUPS=true; shift ;;
            --remove-packages) REMOVE_PACKAGES=true; shift ;;
            --remove-all-config) REMOVE_ALL_CONFIG=true; shift ;;
            --help|-h) show_help; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
}

show_help() {
    cat << EOF
${BOLD}Imperative Dots Uninstaller${RESET}

${BOLD}Usage:${RESET}
    bash uninstall.sh [OPTIONS]

${BOLD}Options:${RESET}
    --dry-run                  Show what would be removed without making changes
    --non-interactive          Skip all confirmation prompts (use defaults)
    --restore-backups          Restore configuration backups created during install
    --remove-packages          Remove packages installed by imperative-dots
    --remove-all-config        Remove ALL dot configuration (normally only removes imperative-dots configs)
    --help, -h                 Show this help message

${BOLD}Examples:${RESET}
    # Preview what will be removed
    bash uninstall.sh --dry-run

    # Full uninstall with package removal
    bash uninstall.sh --remove-packages --remove-all-config

    # Non-interactive uninstall (for scripts/automation)
    bash uninstall.sh --non-interactive --restore-backups

${BOLD}Notes:${RESET}
    - Backup configurations are NOT removed by default
    - Use --restore-backups to restore pre-installation configs
    - Use --remove-all-config to remove downloaded wallpapers and fonts
    - Always run with --dry-run first to preview changes
EOF
}

# ==============================================================================
# Detection Functions
# ==============================================================================

detect_installation() {
    if [ ! -f "$VERSION_FILE" ]; then
        return 1
    fi
    
    if [ ! -f "$INSTALL_MARKER" ]; then
        return 1
    fi
    
    return 0
}

detect_backup_dir() {
    # Look for the most recent backup directory
    local backups=($(find "$BACKUP_SEARCH_DIR" -maxdepth 1 -type d -name ".config-backup-*" 2>/dev/null | sort -r))
    
    if [ ${#backups[@]} -gt 0 ]; then
        echo "${backups[0]}"
        return 0
    fi
    
    return 1
}

detect_wallpaper_dir() {
    if [ -f "$VERSION_FILE" ]; then
        source "$VERSION_FILE" 2>/dev/null
        if [ -n "$WALLPAPER_DIR" ] && [ -d "$WALLPAPER_DIR" ]; then
            echo "$WALLPAPER_DIR"
            return 0
        fi
    fi
    return 1
}

# ==============================================================================
# Uninstall Steps
# ==============================================================================

uninstall_step_display_manager() {
    log_info "Checking Display Manager configuration..."
    
    if [ -f "/etc/sddm.conf.d/10-wayland-matugen.conf" ]; then
        if confirm "Remove SDDM configuration?" "n"; then
            if [ "$DRY_RUN" = false ]; then
                sudo rm -f /etc/sddm.conf.d/10-wayland-matugen.conf
                log_success "Removed SDDM configuration"
            else
                log_info "[DRY RUN] Would remove /etc/sddm.conf.d/10-wayland-matugen.conf"
            fi
        fi
    fi
    
    if [ -d "/usr/share/sddm/themes/matugen-minimal" ]; then
        if confirm "Remove SDDM Matugen Minimal theme?" "n"; then
            if [ "$DRY_RUN" = false ]; then
                sudo rm -rf /usr/share/sddm/themes/matugen-minimal
                log_success "Removed SDDM theme"
            else
                log_info "[DRY RUN] Would remove /usr/share/sddm/themes/matugen-minimal"
            fi
        fi
    fi
}

uninstall_step_dotfiles() {
    log_info "Removing imperative-dots configuration files..."
    
    local config_folders=("cava" "hypr" "kitty" "rofi" "matugen" "zsh" "swayosd")
    
    for folder in "${config_folders[@]}"; do
        local target_path="$CONFIG_DIR/$folder"
        
        if [ -e "$target_path" ]; then
            if [ "$REMOVE_ALL_CONFIG" = true ] || [ -f "$target_path/.imperative-dots-marker" ] 2>/dev/null; then
                if confirm "Remove $folder configuration?" "y"; then
                    if [ "$DRY_RUN" = false ]; then
                        rm -rf "$target_path"
                        log_success "Removed $folder"
                    else
                        log_info "[DRY RUN] Would remove $target_path"
                    fi
                fi
            fi
        fi
    done
}

uninstall_step_fonts() {
    log_info "Checking font installation..."
    
    if [ -d "$FONTS_DIR/IosevkaNerdFont" ]; then
        if confirm "Remove Iosevka Nerd Fonts?" "n"; then
            if [ "$DRY_RUN" = false ]; then
                rm -rf "$FONTS_DIR/IosevkaNerdFont"
                sudo rm -rf /usr/share/fonts/IosevkaNerdFont 2>/dev/null || true
                
                if command -v fc-cache &> /dev/null; then
                    fc-cache -f "$FONTS_DIR" > /dev/null 2>&1
                fi
                log_success "Removed Iosevka Nerd Fonts"
            else
                log_info "[DRY RUN] Would remove $FONTS_DIR/IosevkaNerdFont"
            fi
        fi
    fi
}

uninstall_step_wallpapers() {
    log_info "Checking wallpaper directory..."
    
    WALLPAPERS_DIR=$(detect_wallpaper_dir)
    
    if [ -n "$WALLPAPERS_DIR" ] && [ -d "$WALLPAPERS_DIR" ]; then
        local wp_count=$(find "$WALLPAPERS_DIR" -maxdepth 1 -type f -name "*.{jpg,png,jpeg,gif,webp}" 2>/dev/null | wc -l)
        
        if [ "$wp_count" -gt 0 ]; then
            if confirm "Remove downloaded wallpapers ($wp_count files) from $WALLPAPERS_DIR?" "n"; then
                if [ "$DRY_RUN" = false ]; then
                    rm -f "$WALLPAPERS_DIR"/*.{jpg,png,jpeg,gif,webp} 2>/dev/null || true
                    log_success "Removed wallpapers"
                else
                    log_info "[DRY RUN] Would remove wallpapers from $WALLPAPERS_DIR"
                fi
            fi
        fi
    fi
}

uninstall_step_repository() {
    log_info "Checking repository clone..."
    
    if [ -d "$CLONE_DIR" ]; then
        if confirm "Remove cloned repository at $CLONE_DIR?" "y"; then
            if [ "$DRY_RUN" = false ]; then
                rm -rf "$CLONE_DIR"
                log_success "Removed cloned repository"
            else
                log_info "[DRY RUN] Would remove $CLONE_DIR"
            fi
        fi
    fi
}

uninstall_step_version_file() {
    log_info "Checking version marker..."
    
    if [ -f "$VERSION_FILE" ]; then
        if confirm "Remove installation marker ($VERSION_FILE)?" "y"; then
            if [ "$DRY_RUN" = false ]; then
                rm -f "$VERSION_FILE"
                log_success "Removed version marker"
            else
                log_info "[DRY RUN] Would remove $VERSION_FILE"
            fi
        fi
    fi
}

uninstall_step_services() {
    log_info "Checking systemd services..."
    
    local services=("easyeffects" "swayosd-libinput-backend")
    
    for service in "${services[@]}"; do
        if systemctl --user is-enabled "$service.service" &>/dev/null 2>&1; then
            log_warning "User service $service is still enabled"
            if confirm "Disable $service?" "y"; then
                if [ "$DRY_RUN" = false ]; then
                    systemctl --user disable "$service.service" 2>/dev/null || true
                    systemctl --user stop "$service.service" 2>/dev/null || true
                    log_success "Disabled $service"
                else
                    log_info "[DRY RUN] Would disable $service"
                fi
            fi
        fi
    done
}

uninstall_step_packages() {
    if [ "$REMOVE_PACKAGES" = false ]; then
        return
    fi
    
    log_info "Removing installed packages..."
    echo -e "${C_YELLOW}[!] Package removal is destructive and may break your system if other applications depend on these packages.${RESET}"
    
    if ! confirm "${BOLD}${C_RED}Are you 100% sure you want to remove all packages?${RESET}" "n"; then
        log_warning "Package removal skipped"
        return
    fi
    
    local packages=(
        "hyprland" "hypridle" "kitty" "cava" "zbar" "pavucontrol" "alsa-utils" "awww" "networkmanager-dmenu-git"
        "wl-clipboard" "fd" "qt6-multimedia" "qt6-5compat" "ripgrep"
        "cliphist" "jq" "socat" "inotify-tools" "pamixer" "brightnessctl" "acpi" "iw"
        "bluez" "bluez-utils" "libnotify" "lm_sensors" "bc" 
        "matugen-bin" "ffmpeg" "fastfetch" "quickshell-git" "unzip" "python-websockets" "qt6-websockets"
        "grim" "playerctl" "satty" "yq" "xdg-desktop-portal-gtk" "slurp" "mpvpaper"
        "wmctrl" "power-profiles-daemon" "easyeffects" "swayosd-git" "nautilus" "lsp-plugins" "hyprpolkitagent"
        "qt5-wayland" "qt5-quickcontrols" "qt5-quickcontrols2" "qt5-graphicaleffects" "qt6-wayland"
        "qt5ct" "qt6ct" "gpu-screen-recorder" "adw-gtk-theme" "xdg-desktop-portal-wlr"
        "neovim" "lua-language-server" "nodejs" "npm" "python3" "zsh" "sddm"
    )
    
    local installed_pkgs=()
    for pkg in "${packages[@]}"; do
        if pacman -Q "$pkg" &>/dev/null 2>&1; then
            installed_pkgs+=("$pkg")
        fi
    done
    
    if [ ${#installed_pkgs[@]} -eq 0 ]; then
        log_info "No imperative-dots packages found to remove"
        return
    fi
    
    echo -e "\n${C_YELLOW}Found ${#installed_pkgs[@]} packages to remove:${RESET}"
    printf '%s\n' "${installed_pkgs[@]}" | sed 's/^/  - /'
    
    if ! confirm "\n${BOLD}${C_RED}Remove these packages?${RESET}" "n"; then
        log_warning "Package removal cancelled"
        return
    fi
    
    if [ "$DRY_RUN" = false ]; then
        log_warning "Requesting sudo privileges for package removal..."
        sudo -v
        
        for pkg in "${installed_pkgs[@]}"; do
            if ! sudo pacman -Rns --noconfirm "$pkg" > /dev/null 2>&1; then
                log_warning "Could not remove $pkg (may have dependencies or be needed by system)"
            else
                log_success "Removed $pkg"
            fi
        done
    else
        log_info "[DRY RUN] Would remove ${#installed_pkgs[@]} packages"
    fi
}

restore_backups() {
    log_info "Looking for backup configurations..."
    
    local backup_dir=$(detect_backup_dir)
    
    if [ -z "$backup_dir" ]; then
        log_warning "No backup directory found"
        return 1
    fi
    
    echo -e "\n${C_GREEN}Found backup: $backup_dir${RESET}"
    
    if ! confirm "Restore configurations from backup?" "n"; then
        log_warning "Backup restore skipped"
        return 0
    fi
    
    if [ "$DRY_RUN" = false ]; then
        log_info "Restoring configurations..."
        
        # Restore each backed-up folder
        for item in "$backup_dir"/*; do
            if [ -e "$item" ]; then
                local name=$(basename "$item")
                local target="$CONFIG_DIR/$name"
                
                # Preserve new configs, restore old ones
                if [ -e "$target" ]; then
                    rm -rf "$target"
                fi
                
                cp -r "$item" "$target"
                log_success "Restored $name"
            fi
        done
        
        # Restore home-level files if they exist
        if [ -f "$backup_dir/.zshrc" ]; then
            cp "$backup_dir/.zshrc" "$HOME/.zshrc"
            log_success "Restored .zshrc"
        fi
        
        log_success "Backup restoration complete"
    else
        log_info "[DRY RUN] Would restore from $backup_dir"
    fi
}

# ==============================================================================
# Main Uninstall Flow
# ==============================================================================

main() {
    parse_arguments "$@"
    
    print_header
    
    if ! detect_installation; then
        log_error "Imperative Dots does not appear to be installed"
        echo -e "Expected installation marker at: ${C_CYAN}$INSTALL_MARKER${RESET}"
        exit 1
    fi
    
    log_success "Detected imperative-dots installation"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${C_YELLOW}${BOLD}[DRY RUN MODE] - No changes will be made${RESET}\n"
    fi
    
    if [ "$INTERACTIVE" = true ]; then
        echo -e "${C_BLUE}The following will be removed:${RESET}"
        echo "  - Hyprland dot configuration (.config/hypr, .config/kitty, etc.)"
        echo "  - Imperative Dots repository clone"
        echo "  - Installation marker and version tracking"
        echo ""
        echo -e "${C_YELLOW}These will NOT be removed unless you specify:${RESET}"
        echo "  - Configuration backups (--restore-backups to restore)"
        echo "  - Installed packages (use --remove-packages)"
        echo "  - Other dot configurations (--remove-all-config)"
        echo "  - Wallpapers and fonts (--remove-all-config)"
        echo ""
        
        if ! confirm "${BOLD}${C_RED}Proceed with uninstallation?${RESET}" "n"; then
            log_warning "Uninstallation cancelled"
            exit 0
        fi
    fi
    
    echo ""
    
    # Execute uninstall steps
    uninstall_step_dotfiles
    echo ""
    uninstall_step_display_manager
    echo ""
    uninstall_step_services
    echo ""
    uninstall_step_repository
    echo ""
    uninstall_step_fonts
    echo ""
    uninstall_step_wallpapers
    echo ""
    uninstall_step_packages
    echo ""
    uninstall_step_version_file
    
    # Restoration
    if [ "$RESTORE_BACKUPS" = true ]; then
        echo ""
        restore_backups
    fi
    
    # Final summary
    echo ""
    echo -e "${BOLD}${C_GREEN}"
    cat << "EOF"
 _   _ _   _ ___ _   _ ___ _____ _   _    _   _    _ _ 
| | | | \ | |_ _| | | / __|_   _/_\ | |  | | | |  | | |
| |_| |  \| || | | |_| \__ \ | |/ _ \| |__| |_| |_ |_|_|
 \___/|_|\_|___| \___/|___/ |_/_/ \_\____|_____|___||_|_|
                                                         
EOF
    echo -e "${RESET}\n"
    
    if [ "$DRY_RUN" = true ]; then
        log_info "Dry run complete. Review the changes above."
        echo -e "Run without ${C_CYAN}--dry-run${RESET} to apply changes.\n"
    else
        log_success "Uninstallation complete!"
        echo -e "\nYou may want to:"
        echo "  - Run ${C_CYAN}systemctl --user daemon-reload${RESET} to refresh systemd"
        echo "  - Use ${C_CYAN}chsh -s /bin/bash${RESET} to restore bash if using Zsh"
        echo "  - Restart your system to fully clean up"
        echo ""
    fi
}

main "$@"
