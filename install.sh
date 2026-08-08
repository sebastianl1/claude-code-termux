#!/data/data/com.termux/files/usr/bin/bash
#
# Claude Code — Termux
# Script de instalacion para Termux
# v1.0.0
#
# Script creado por Sebastian Laguna
# https://github.com/sebastianl1/claude-code-termux
#
# Descripcion:
#   Instala Claude Code de forma nativa en Termux: descarga el binario
#   oficial (build glibc) y lo ejecuta con un launcher nativo Android
#   a traves de la capa glibc de Termux.
#   Multi-fuente: vendor oficial (npm), espejo propio y cache local.
#   Sin proot, sin VMs, sin Cloud Shell.
#
# Uso:
#   bash install.sh              Instalacion completa
#   bash install.sh --help       Muestra esta ayuda
#   bash install.sh --version    Muestra la version
#   bash install.sh --uninstall  Desinstala claude
#

set -eEuo pipefail

# ── Configuracion ────────────────────────────────────────────────────────────

SCRIPT_VERSION="1.0.0"
SCRIPT_AUTHOR="Sebastian Laguna"
SCRIPT_REPO="https://github.com/sebastianl1/claude-code-termux"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CLAUDE_BIN_DIR="$PREFIX/bin"
CLAUDE_SHARE_DIR="$PREFIX/share/claude"
CLAUDE_REAL="$CLAUDE_SHARE_DIR/claude.real"
GLIBC_PREFIX="$PREFIX/glibc"
CLAUDE_CONFIG_DIR="$HOME/.claude"
CLAUDE_SETTINGS_FILE="$CLAUDE_CONFIG_DIR/settings.json"
BACKUP_DIR="$HOME/backups/claude"
TMP_DIR="$PREFIX/tmp/claude-install"
LOG_FILE="$TMP_DIR/install.log"
INSTALL_FAILED=false
INSTALL_METHOD=""

# Fuentes del binario (por prioridad):
#   A. Vendor oficial  -> npm '@anthropic-ai/claude-code-linux-arm64' (ultima)
#   B. Espejo propio   -> GitHub Releases de este repositorio
#   C. Cache local     -> ~/.cache/claude-code/ (guardado tras instalar)
NPM_PKG="claude-code-linux-arm64"
NPM_SCOPE="@anthropic-ai"
MIRROR_DL="https://github.com/sebastianl1/claude-code-termux/releases/latest/download/claude-code-linux-arm64.tar.gz"
CACHE_DIR="$HOME/.cache/claude-code"

# ── Colores (profesionales, sin llamativos) ─────────────────────────────────

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
BLUE="\033[34m"
WHITE="\033[97m"
RESET="\033[0m"

# ── Dimensiones ─────────────────────────────────────────────────────────────

COLS=66

# ── Funciones de dibujo ─────────────────────────────────────────────────────

make_line() {
    local char="${1:-─}"
    local line=""
    printf -v line "%*s" "$COLS" ""
    echo "${line// /${char}}"
}

box_line() {
    echo -e "  ${BLUE}${BOLD}$1${RESET}"
}

box_text() {
    local content="$1"
    local color="${2:-}"
    local padding=$(( COLS - ${#content} - 2 ))
    printf "  ${BLUE}${BOLD}│${RESET} ${color}%s${RESET}%*s${BLUE}${BOLD}│${RESET}\n" "$content" "$padding" ""
}

section_header() {
    local title="$1"
    echo ""
    echo -e "  ${BLUE}${BOLD}◆ ${title}${RESET}"
    echo -e "  ${BLUE}${DIM}$(make_line)${RESET}"
    echo ""
}

check_item() {
    local label="$1"
    local status="$2"
    local detail="${3:-}"

    if [ "$status" = "ok" ]; then
        printf "  ${GREEN}✔${RESET} ${BOLD}%-34s${RESET}" "$label"
    elif [ "$status" = "skip" ]; then
        printf "  ${DIM}−${RESET} ${DIM}%-34s${RESET}" "$label"
    else
        printf "  ${YELLOW}⬡${RESET} ${BOLD}%-34s${RESET}" "$label"
    fi

    if [ -n "$detail" ]; then
        echo -e "${DIM}${detail}${RESET}"
    else
        echo ""
    fi
}

# ── Funciones de utilidad ───────────────────────────────────────────────────

cleanup() {
    if [ "$INSTALL_FAILED" = "true" ] && [ -d "$BACKUP_DIR" ]; then
        restore_backup
    fi
    rm -rf "$TMP_DIR" 2>/dev/null || true
}

trap cleanup EXIT INT TERM

print_error() {
    echo -e "\n  ${RED}${BOLD}ERROR${RESET} ${1}"
    exit 1
}

print_info() {
    echo -e "  ${DIM}${1}${RESET}"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-S}"
    local yn

    printf "  %s " "$prompt"
    if [ "$default" = "S" ]; then
        printf "${BOLD}[S/n]${RESET}: "
    else
        printf "${BOLD}[s/N]${RESET}: "
    fi

    read -r yn
    yn="${yn:-$default}"

    case "$yn" in
        [Ss]*) return 0 ;;
        *) return 1 ;;
    esac
}

run_hidden() {
    local desc="$1"
    shift

    mkdir -p "$TMP_DIR"

    printf "  ⬡ ${BOLD}%-34s${RESET}" "$desc"

    echo "--- [$desc] $(date) ---" >> "$LOG_FILE"
    "$@" >> "$LOG_FILE" 2>&1 &
    local pid=$!
    local spin='-\|/'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${WHITE}${BOLD}⬡${RESET} ${BOLD}%-34s${RESET} ${DIM}%s${RESET}" "$desc" "${spin:$i:1}"
        i=$(( (i + 1) % 4 ))
        sleep 0.1
    done

    local exit_code=0
    wait "$pid" || exit_code=$?

    printf "\r"

    if [ "$exit_code" -eq 0 ]; then
        printf "  ${GREEN}✔${RESET} ${BOLD}%-34s${RESET} ${GREEN}hecho${RESET}\n" "$desc"
    else
        printf "  ${RED}✘${RESET} ${BOLD}%-34s${RESET} ${RED}fallo${RESET}\n" "$desc"
        return "$exit_code"
    fi
}

show_log_tail() {
    echo ""
    echo -e "  ${DIM}Ultimas lineas del log:${RESET}"
    tail -15 "$LOG_FILE" 2>/dev/null | while IFS= read -r line; do
        echo -e "  ${DIM}  ${line}${RESET}"
    done
}

explain_termux_failure() {
    local log_content
    log_content=$(cat "$LOG_FILE" 2>/dev/null || true)

    case "$log_content" in
        *"unable to locate package"*|*"E: Unable"*|*"Failed to fetch"*|*"Could not resolve"*|*"curl"*|*"unexpected e_type"*|*"required file not found"*|*"Binary not found"*)
            echo ""
            echo -e "  ${YELLOW}⬡${RESET} ${BOLD}Instalacion nativa de Claude Code en Termux${RESET}"
            echo -e "  ${DIM}Claude Code se instala con el binario oficial glibc + un${RESET}"
            echo -e "  ${DIM}launcher nativo Android, a traves de la capa glibc de${RESET}"
            echo -e "  ${DIM}Termux. No usa npm, proot ni VMs.${RESET}"
            echo ""
            echo -e "  ${BOLD}Si fallaron todas las fuentes, verifica:${RESET}"
            echo -e "  ${DIM}1.${RESET} Conexion a internet (el binario pesa ~290MB)"
            echo -e "  ${DIM}2.${RESET} Que la capa glibc quede instalada:"
            echo -e "     ${RESET}pkg install -y glibc-repo && pkg update && pkg install -y glibc"
            echo -e "  ${DIM}3.${RESET} Reintentar en otro momento (descarga de npm/GitHub)"
            echo ""
            ;;
    esac
}

detect_installed_version() {
    if command -v claude &>/dev/null; then
        claude --version 2>/dev/null || echo ""
    fi
}

# ── Banner principal ────────────────────────────────────────────────────────

print_banner() {
    echo ""
    box_line "┌$(make_line)┐"
    box_text "" ""
    box_text "Claude Code — Termux" "$WHITE${BOLD}"
    box_text "Script de instalacion  v${SCRIPT_VERSION}" "${DIM}"
    box_text "" ""
    box_text "Sebastian Laguna" "${BOLD}"
    box_text "${SCRIPT_REPO}" "${DIM}"
    box_text "" ""
    box_line "├$(make_line)┤"
}

# ── Funciones del instalador ────────────────────────────────────────────────

check_environment() {
    section_header "Preparacion"

    local env_ok=true
    local arch_ok=true

    if [ -n "${TERMUX_VERSION:-}" ]; then
        check_item "Entorno Termux" "ok" ""
    else
        check_item "Entorno Termux" "skip" ""
        env_ok=false
    fi

    if [ "$(uname -m)" = "aarch64" ]; then
        check_item "Arquitectura aarch64" "ok" ""
    else
        check_item "Arquitectura aarch64" "skip" "$(uname -m)"
        arch_ok=false
    fi

    if command -v node &>/dev/null; then
        local node_ver
        node_ver=$(node --version 2>/dev/null)
        check_item "Node.js (opcional)" "ok" "$node_ver"
    else
        check_item "Node.js (opcional)" "skip" "no requerido"
    fi

    if command -v npm &>/dev/null; then
        local npm_ver
        npm_ver=$(npm --version 2>/dev/null)
        check_item "npm (opcional)" "ok" "v$npm_ver"
    else
        check_item "npm (opcional)" "skip" "no requerido"
    fi

    echo ""

    if [ "$env_ok" != "true" ] || [ "$arch_ok" != "true" ]; then
        print_error "Este instalador solo funciona en Termux ARM64 (aarch64)."
    fi
}

check_dependencies() {
    :
}

check_existing() {
    local current_version="$1"

    section_header "Estado actual"

    check_item "Claude Code" "ok" "$current_version"
    check_item "Origen" "ok" "$(command -v claude)"

    if ! ask_yes_no "¿Reinstalar Claude Code?" "N"; then
        print_info "Instalacion omitida."
        return 1
    fi
}

backup_existing() {
    section_header "Respaldo"

    if [ -d "$CLAUDE_CONFIG_DIR" ]; then
        mkdir -p "$BACKUP_DIR"
        local ts
        ts=$(date +%Y%m%d-%H%M%S)
        cp -r "$CLAUDE_CONFIG_DIR" "$BACKUP_DIR/claude.backup.$ts"
        check_item "Respaldo configuracion" "ok" "$BACKUP_DIR/claude.backup.$ts"
    else
        check_item "Sin configuracion previa" "ok" ""
    fi
}

restore_backup() {
    local backup_path
    backup_path=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name 'claude.backup.*' -print -quit 2>/dev/null || true)
    if [ -n "$backup_path" ] && [ -d "$backup_path" ]; then
        cp -r "$backup_path"/* "$CLAUDE_CONFIG_DIR/" 2>/dev/null || true
        {
            echo "--- [restore_backup] $(date) ---"
            echo "Configuracion restaurada desde $backup_path"
        } >> "$LOG_FILE"
        echo -e "\n  ${YELLOW}⬡${RESET} Configuracion anterior restaurada desde backup." >&2
    fi
}

ensure_glibc_layer() {
    if [ ! -f "$PREFIX/etc/apt/sources.list.d/glibc.list" ]; then
        run_hidden "Actualizar repositorios" pkg update -y || {
            show_log_tail
            print_error "Falló 'pkg update'. Revisa tu conexión a internet."
        }
        run_hidden "Agregar repositorio glibc" pkg install -y glibc-repo || {
            show_log_tail
            print_error "No se pudo agregar el repositorio glibc de Termux."
        }
        run_hidden "Actualizar repositorios" pkg update -y || {
            show_log_tail
            print_error "Falló 'pkg update'. Revisa tu conexión a internet."
        }
    fi

    run_hidden "Instalar capa glibc" pkg install -y glibc ca-certificates ca-certificates-glibc clang curl tar || {
        show_log_tail
        print_error "No se pudo instalar la capa glibc de Termux (glibc)."
    }
}

verify_binary() {
    local bin="$1"
    [ -f "$bin" ] || return 1
    [ "$(head -c 4 "$bin" | od -An -tx1 | tr -d ' \n')" = "7f454c46" ] || return 1
    local size
    size=$(wc -c < "$bin")
    [ "$size" -ge 200000000 ] || return 1
    file "$bin" 2>/dev/null | grep -qi 'aarch64' || return 1
    return 0
}

save_to_cache() {
    local src="$1"
    mkdir -p "$CACHE_DIR"
    cp "$src" "$CACHE_DIR/claude" 2>/dev/null || true
    chmod 755 "$CACHE_DIR/claude" 2>/dev/null || true
}

install_binary() {
    local src="$1"
    if verify_binary "$src"; then
        cp "$src" "$CLAUDE_REAL"
        chmod 755 "$CLAUDE_REAL"
        return 0
    fi
    return 1
}

fetch_binary_from_npm() {
    local meta tarball archive

    meta=$(curl -fsSL --proto =https --connect-timeout 20 --max-time 60 "https://registry.npmjs.org/${NPM_SCOPE}/${NPM_PKG}/latest") || return 1
    tarball=$(printf '%s' "$meta" | grep -o '"tarball":"[^"]*"' | cut -d'"' -f4) || return 1
    [ -n "$tarball" ] || return 1

    archive="$TMP_DIR/claude-code-linux-arm64.tgz"
    curl -fsSL --proto =https --retry 2 --connect-timeout 20 --max-time 1200 -o "$archive" "$tarball" || return 1
    mkdir -p "$TMP_DIR/npmbin"
    tar -xzf "$archive" -C "$TMP_DIR/npmbin"
    verify_binary "$TMP_DIR/npmbin/package/claude"
}

fetch_binary_from_url() {
    local url="$1"
    local archive="$TMP_DIR/claude-code-linux-arm64.tar.gz"

    curl -fsSL --proto =https --retry 2 --connect-timeout 20 --max-time 1200 -o "$archive" "$url" || return 1
    mkdir -p "$TMP_DIR/bin"
    tar -xzf "$archive" -C "$TMP_DIR/bin"
    verify_binary "$TMP_DIR/bin/claude"
}

install_launcher() {
    local launcher_src="$SCRIPT_DIR/launcher.c"

    if [ ! -f "$launcher_src" ]; then
        print_error "No se encontró 'launcher.c' junto a install.sh ($SCRIPT_DIR)."
    fi

    if ! run_hidden "Compilar launcher nativo" cc -O2 -DPREFIX="\"$PREFIX\"" -o "$CLAUDE_BIN_DIR/claude" "$launcher_src"; then
        show_log_tail
        print_error "Falló la compilación del launcher nativo (requiere clang)."
    fi
    chmod 755 "$CLAUDE_BIN_DIR/claude"
}

setup_glibc_override() {
    local ovr="$CLAUDE_SHARE_DIR/glibc"
    mkdir -p "$ovr"
    local lib elf_base count=0
    for lib in "$GLIBC_PREFIX"/lib/lib*.so.*; do
        [ -e "$lib" ] || continue
        if [ "$(head -c 4 "$lib" 2>/dev/null | od -An -tx1 | tr -d ' \n')" != "7f454c46" ]; then
            continue
        fi
        elf_base=$(basename "$lib")
        elf_base=${elf_base%%.so.*}.so
        if [ ! -e "$ovr/$elf_base" ]; then
            ln -sfn "$lib" "$ovr/$elf_base"
            count=$((count + 1))
        fi
    done
    ln -sfn "$GLIBC_PREFIX/lib/ld-linux-aarch64.so.1" "$ovr/ld-linux-aarch64.so.1" 2>/dev/null || true
    check_item "Symlinks glibc (override)" "ok" "$count enlaces"
}

configure_claude_settings() {
    section_header "Configuracion"

    mkdir -p "$CLAUDE_CONFIG_DIR"

    local merged=false
    if [ -f "$CLAUDE_SETTINGS_FILE" ]; then
        if command -v python3 &>/dev/null; then
            local py_script="$TMP_DIR/merge_settings.py"
            cat > "$py_script" <<'PYEOF'
import json, sys
path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except Exception:
    data = {}
data.setdefault("autoUpdates", False)
data.setdefault("env", {})["DISABLE_AUTOUPDATER"] = "1"
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYEOF
            if run_hidden "Ajustar settings.json" python3 "$py_script" "$CLAUDE_SETTINGS_FILE"; then
                merged=true
            fi
        fi
    fi

    if [ "$merged" != "true" ]; then
        cat > "$CLAUDE_SETTINGS_FILE" <<'EOF'
{
  "autoUpdates": false,
  "env": {
    "DISABLE_AUTOUPDATER": "1"
  }
}
EOF
    fi

    check_item "Configuracion de claude" "ok" "$CLAUDE_SETTINGS_FILE"
}

fetch_claude_binary() {
    mkdir -p "$CLAUDE_SHARE_DIR"

    if run_hidden "Descargar binario (vendor)" fetch_binary_from_npm; then
        install_binary "$TMP_DIR/npmbin/package/claude"
        INSTALL_METHOD="vendor (npm)"
        save_to_cache "$TMP_DIR/npmbin/package/claude"
        return 0
    fi

    if run_hidden "Descargar binario (espejo)" fetch_binary_from_url "$MIRROR_DL"; then
        install_binary "$TMP_DIR/bin/claude"
        INSTALL_METHOD="espejo"
        save_to_cache "$TMP_DIR/bin/claude"
        return 0
    fi

    if [ -f "$CACHE_DIR/claude" ]; then
        if run_hidden "Instalar desde caché" true; then
            if install_binary "$CACHE_DIR/claude"; then
                INSTALL_METHOD="caché local"
                return 0
            fi
        fi
    fi

    show_log_tail
    explain_termux_failure
    print_error "Fallaron todas las fuentes de Claude Code. Revisa el log: $LOG_FILE"
}

install_claude() {
    section_header "Instalacion"

    ensure_glibc_layer
    fetch_claude_binary
    install_launcher
    setup_glibc_override
    configure_claude_settings
}

verify_installation() {
    local version
    if version=$(claude --version 2>/dev/null); then
        check_item "Verificar instalacion" "ok" "${version}"
    else
        print_error "La verificacion de Claude Code fallo. Revisa la instalacion."
    fi
}

# ── Resumen final ────────────────────────────────────────────────────────────

print_summary() {
    local line
    printf -v line "%*s" "$COLS" ""
    line="${line// /─}"

    echo ""
    box_line "├$(make_line)┤"
    box_text "" ""
    box_text "  Instalacion completada exitosamente" "${WHITE}${BOLD}"
    box_text "" ""
    box_line "└$(make_line)┘"
    echo ""

    echo -e "  ${BOLD}Comandos disponibles${RESET}"
    echo ""
    printf "    ${BOLD}%-26s${RESET} ${DIM}%s${RESET}\n" "claude" "Iniciar Claude Code (TUI interactiva)"
    printf "    ${BOLD}%-26s${RESET} ${DIM}%s${RESET}\n" "claude --version" "Version instalada"
    printf "    ${BOLD}%-26s${RESET} ${DIM}%s${RESET}\n" "claude --help" "Ayuda y comandos"
    printf "    ${BOLD}%-26s${RESET} ${DIM}%s${RESET}\n" "bash install.sh" "Actualizar Claude Code"
    echo ""

    echo -e "  ${BOLD}Archivos instalados${RESET}"
    echo ""
    printf "    ${DIM}%-30s ${RESET}%s\n" "Origen:" "binario oficial glibc ($INSTALL_METHOD)"
    printf "    ${DIM}%-30s ${RESET}%s\n" "Launcher:" "$CLAUDE_BIN_DIR/claude"
    printf "    ${DIM}%-30s ${RESET}%s\n" "Binario:" "$CLAUDE_REAL"
    printf "    ${DIM}%-30s ${RESET}%s\n" "Configuracion:" "$CLAUDE_CONFIG_DIR/"
    if [ -d "$BACKUP_DIR" ] && [ -n "$(find "$BACKUP_DIR" -maxdepth 1 -type d -name 'claude.backup.*' -print -quit 2>/dev/null || true)" ]; then
        printf "    ${DIM}%-30s ${RESET}%s\n" "Respaldo:" "$BACKUP_DIR/"
    fi
    echo ""

    echo -e "  ${BOLD}Proximos pasos${RESET}"
    echo ""
    echo -e "  ${DIM}1.${RESET} ${BOLD}Iniciar sesion${RESET}"
    echo -e "     ${DIM}Ejecuta:${RESET}  claude"
    echo -e "     ${DIM}Sigue las instrucciones para autenticar con tu cuenta de Anthropic${RESET}"
    echo ""

    echo -e "  ${DIM}2.${RESET} ${BOLD}Configurar tu clave de API (opcional)${RESET}"
    echo -e "     ${DIM}Ejecuta:${RESET}  export ANTHROPIC_API_KEY=tu_clave"
    echo -e "     ${DIM}O inicia sesion dentro de claude con /login${RESET}"
    echo ""

    local sep
    printf -v sep "%*s" "$COLS" ""
    sep="${sep// /─}"
    echo -e "  ${DIM}${sep}${RESET}"
    echo -e "  ${BOLD}Script creado por Sebastian Laguna${RESET}"
    echo -e "  ${DIM}${SCRIPT_REPO}${RESET}"
    echo ""
}

# ── Desinstalacion ──────────────────────────────────────────────────────────

do_uninstall() {
    echo ""
    box_line "┌$(make_line)┐"
    box_text "Desinstalar Claude Code" "$WHITE${BOLD}"
    box_line "└$(make_line)┘"
    echo ""

    if ! ask_yes_no "¿Esta seguro de desinstalar Claude Code?" "N"; then
        echo -e "  ${DIM}Desinstalacion cancelada.${RESET}"
        exit 0
    fi
    echo ""

    local removed=false

    if command -v claude &>/dev/null; then
        if [ -f "$CLAUDE_BIN_DIR/claude" ]; then
            echo -e "  ${GREEN}✔${RESET} Eliminando launcher: $CLAUDE_BIN_DIR/claude"
            rm -f "$CLAUDE_BIN_DIR/claude"
            removed=true
        fi
        if [ -d "$CLAUDE_SHARE_DIR" ]; then
            echo -e "  ${GREEN}✔${RESET} Eliminando binario: $CLAUDE_SHARE_DIR/"
            rm -rf "$CLAUDE_SHARE_DIR"
            removed=true
        fi
        if [ "$removed" = "false" ]; then
            echo -e "  ${YELLOW}−${RESET} No se encontro instalacion de Claude Code."
        fi
    else
        echo -e "  ${YELLOW}−${RESET} No se encontro instalacion de Claude Code."
    fi

    if [ -d "$CLAUDE_CONFIG_DIR" ]; then
        echo ""
        if ask_yes_no "¿Eliminar tambien la configuracion de Claude Code?" "N"; then
            rm -rf "$CLAUDE_CONFIG_DIR"
            echo -e "  ${GREEN}✔${RESET} Eliminado: $CLAUDE_CONFIG_DIR"
        fi
    fi

    echo ""
    echo -e "  ${BOLD}Para eliminar respaldos:${RESET}"
    echo -e "  ${DIM}  rm -rf ${BACKUP_DIR}${RESET}"
    echo ""

    local sep
    printf -v sep "%*s" "$COLS" ""
    sep="${sep// /─}"
    echo -e "  ${DIM}${sep}${RESET}"
    echo -e "  ${BOLD}Script creado por Sebastian Laguna${RESET}"
    echo -e "  ${DIM}${SCRIPT_REPO}${RESET}"
    echo ""

    exit 0
}

# ── Ayuda ───────────────────────────────────────────────────────────────────

show_help() {
    echo ""
    box_line "┌$(make_line)┐"
    box_text "Claude Code - Termux" "$WHITE${BOLD}"
    box_text "Script de instalacion v${SCRIPT_VERSION}" ""
    box_line "└$(make_line)┘"
    echo ""
    echo -e "  ${BOLD}Uso:${RESET}"
    echo ""
    printf "  ${BOLD}%-28s${RESET} ${DIM}%s${RESET}\n" "bash install.sh" "Instalacion completa"
    printf "  ${BOLD}%-28s${RESET} ${DIM}%s${RESET}\n" "bash install.sh --help" "Muestra esta ayuda"
    printf "  ${BOLD}%-28s${RESET} ${DIM}%s${RESET}\n" "bash install.sh --version" "Muestra la version"
    printf "  ${BOLD}%-28s${RESET} ${DIM}%s${RESET}\n" "bash install.sh --uninstall" "Desinstala Claude Code"
    echo ""
    echo -e "  ${BOLD}Descripcion:${RESET}"
    echo -e "  ${DIM}Instala Claude Code de forma nativa en Termux."
    echo -e "  ${DIM}Descarga el binario oficial glibc y lo lanza con un"
    echo -e "  ${DIM}launcher nativo Android via la capa glibc de Termux."
    echo -e "  ${DIM}  - Fuentes: vendor oficial (npm), espejo propio, cache"
    echo -e "  ${DIM}  - Nativo en Termux (sin proot, sin VMs)"
    echo -e "  ${DIM}  - Sin dependencias npm"
    echo -e "  ${DIM}  - Actualizar: re-ejecutar install.sh${RESET}"
    echo ""
    echo -e "  ${BOLD}Script creado por Sebastian Laguna${RESET}"
    echo -e "  ${DIM}${SCRIPT_REPO}${RESET}"
    echo ""
    exit 0
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
    case "${1:-}" in
        --help|-h)
            show_help
            ;;
        --version|-v)
            echo "claude-code-termux v${SCRIPT_VERSION}"
            exit 0
            ;;
        --uninstall)
            do_uninstall
            ;;
        "")
            ;;
        *)
            echo -e "  ${RED}[ERR]${RESET} Opcion desconocida: ${1}"
            echo "  Usa: bash install.sh --help"
            exit 1
            ;;
    esac

    print_banner

    if ! ask_yes_no "¿Deseas continuar con la instalacion?" "S"; then
        echo -e "  ${DIM}Instalacion cancelada.${RESET}"
        exit 0
    fi

    check_environment
    check_dependencies

    local current_version
    current_version=$(detect_installed_version)
    if [ -n "$current_version" ] && ! check_existing "$current_version"; then
        exit 0
    fi

    backup_existing

    INSTALL_FAILED=true
    install_claude
    verify_installation
    INSTALL_FAILED=false

    print_summary
}

main "$@"
