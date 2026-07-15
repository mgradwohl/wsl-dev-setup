#!/usr/bin/env bash
set -Eeuo pipefail

# WSL Ubuntu C++ development bootstrap
# Intended for Ubuntu WSL, with support for Ubuntu 24.04 and newer.
#
# Usage:
#   chmod +x bootstrap-wsl-dev.sh
#   ./bootstrap-wsl-dev.sh
#
# Optional environment variables:
#   LLVM_VERSION=23 ./bootstrap-wsl-dev.sh
#   FULL_UPGRADE=1 ./bootstrap-wsl-dev.sh
#   INSTALL_VSCODE_EXTENSIONS=0 ./bootstrap-wsl-dev.sh
#   INSTALL_WINDOWS_VSCODE=0 ./bootstrap-wsl-dev.sh
#   GENERATE_VSCODE_SETTINGS=1 ./bootstrap-wsl-dev.sh

LLVM_VERSION="${LLVM_VERSION:-23}"
FULL_UPGRADE="${FULL_UPGRADE:-0}"
INSTALL_WINDOWS_VSCODE="${INSTALL_WINDOWS_VSCODE:-1}"
INSTALL_VSCODE_EXTENSIONS="${INSTALL_VSCODE_EXTENSIONS:-1}"
GENERATE_VSCODE_SETTINGS="${GENERATE_VSCODE_SETTINGS:-0}"

CURRENT_STEP="initialization"
LLVM_INSTALL_SOURCE="undetermined"

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

log() {
    printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
    printf '\n\033[1;33mWARNING:\033[0m %s\n' "$*" >&2
}

die() {
    printf '\n\033[1;31mERROR:\033[0m %s\n' "$*" >&2
    exit 1
}

ok() {
    printf '\033[1;32m✔\033[0m %s\n' "$*"
}

on_error() {
    local exit_code="$1"
    local line_no="$2"
    local command_text="$3"
    printf '\n\033[1;31mERROR:\033[0m step "%s" failed (line %s, exit %s)\n' "$CURRENT_STEP" "$line_no" "$exit_code" >&2
    printf '\033[1;31mERROR:\033[0m command: %s\n' "$command_text" >&2
    exit "$exit_code"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_wsl() {
    grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null
}

validate_configuration() {
    CURRENT_STEP="validate configuration"

    [[ "$LLVM_VERSION" =~ ^[0-9]+$ ]] || die "LLVM_VERSION must be an integer (for example 23)."
    ((LLVM_VERSION >= 23)) || die "LLVM_VERSION must be 23 or newer."

    [[ "$FULL_UPGRADE" =~ ^[01]$ ]] || die "FULL_UPGRADE must be 0 or 1."
    [[ "$INSTALL_WINDOWS_VSCODE" =~ ^[01]$ ]] || die "INSTALL_WINDOWS_VSCODE must be 0 or 1."
    [[ "$INSTALL_VSCODE_EXTENSIONS" =~ ^[01]$ ]] || die "INSTALL_VSCODE_EXTENSIONS must be 0 or 1."
    [[ "$GENERATE_VSCODE_SETTINGS" =~ ^[01]$ ]] || die "GENERATE_VSCODE_SETTINGS must be 0 or 1."
}

require_ubuntu() {
    CURRENT_STEP="detect ubuntu release"
    [[ -r /etc/os-release ]] || die "/etc/os-release was not found."
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "This script supports Ubuntu; detected ${ID:-unknown}."
    log "Detected Ubuntu ${VERSION_ID:-unknown} (${VERSION_CODENAME:-unknown})"
}

show_startup_summary() {
    CURRENT_STEP="print startup summary"
    local wsl_status="no"
    if is_wsl; then
        wsl_status="yes"
    fi

    cat <<EOF

Configuration summary:
  - WSL detected:            ${wsl_status}
  - Target LLVM major:       ${LLVM_VERSION}
  - Full apt full-upgrade:   $([[ "$FULL_UPGRADE" == "1" ]] && echo "enabled" || echo "disabled (safer default)")
  - Install Windows VS Code: $([[ "$INSTALL_WINDOWS_VSCODE" == "1" ]] && echo "yes" || echo "no")
  - Install VS Code ext:     $([[ "$INSTALL_VSCODE_EXTENSIONS" == "1" ]] && echo "yes" || echo "no")
  - Generate .vscode files:  $([[ "$GENERATE_VSCODE_SETTINGS" == "1" ]] && echo "yes" || echo "no")

EOF
}

install_base_packages() {
    CURRENT_STEP="install base packages"
    log "Updating Ubuntu packages"
    sudo apt-get update

    if [[ "$FULL_UPGRADE" == "1" ]]; then
        log "Running apt-get full-upgrade (FULL_UPGRADE=1)"
        sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
    else
        log "Running safer apt-get upgrade (FULL_UPGRADE=0)"
        sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    fi

    log "Installing core development tools"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        build-essential \
        ca-certificates \
        ccache \
        cmake \
        curl \
        file \
        gdb \
        git \
        gnupg \
        jq \
        lsb-release \
        make \
        ninja-build \
        pkg-config \
        python3 \
        python3-dev \
        python3-pip \
        python3-venv \
        software-properties-common \
        unzip \
        wget \
        zip
    ok "Base packages installed"
}

install_python_314() {
    CURRENT_STEP="install python 3.14 (best effort)"
    if apt-cache show python3.14 >/dev/null 2>&1; then
        log "Installing Python 3.14"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            python3.14 \
            python3.14-dev \
            python3.14-venv
        ok "Python 3.14 installed"
    else
        warn "python3.14 is not available from this Ubuntu release's configured repositories."
        warn "Leaving the distro-provided python3 installed rather than adding an unofficial PPA."
    fi
}

install_llvm() {
    CURRENT_STEP="install llvm/clang"
    local packages=(
        "clang-${LLVM_VERSION}"
        "clangd-${LLVM_VERSION}"
        "clang-format-${LLVM_VERSION}"
        "clang-tidy-${LLVM_VERSION}"
        "clang-tools-${LLVM_VERSION}"
        "lld-${LLVM_VERSION}"
        "lldb-${LLVM_VERSION}"
        "llvm-${LLVM_VERSION}"
        "llvm-${LLVM_VERSION}-dev"
        "libc++-${LLVM_VERSION}-dev"
        "libc++abi-${LLVM_VERSION}-dev"
    )

    if apt-cache show "clang-${LLVM_VERSION}" >/dev/null 2>&1; then
        LLVM_INSTALL_SOURCE="ubuntu"
        log "Installing LLVM/Clang ${LLVM_VERSION} from Ubuntu repositories"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
    else
        LLVM_INSTALL_SOURCE="apt.llvm.org"
        log "LLVM ${LLVM_VERSION} is not in the configured Ubuntu repositories"
        log "Using the official apt.llvm.org installer"
        local installer
        installer="$(mktemp)"
        curl --fail --location --silent --show-error \
            https://apt.llvm.org/llvm.sh \
            --output "$installer"
        chmod +x "$installer"
        sudo "$installer" "$LLVM_VERSION" all
        rm -f "$installer"

        # Some optional packages may not be installed by llvm.sh "all" on every release.
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
    fi
    ok "LLVM/Clang ${LLVM_VERSION} installed (${LLVM_INSTALL_SOURCE})"
}

configure_llvm_alternatives() {
    CURRENT_STEP="configure llvm alternatives"
    log "Registering LLVM ${LLVM_VERSION} as the default toolchain"

    local tools=(
        clang
        clang++
        clangd
        clang-format
        clang-tidy
        lld
        lldb
        llvm-ar
        llvm-cov
        llvm-nm
        llvm-objcopy
        llvm-objdump
        llvm-profdata
        llvm-ranlib
        llvm-readelf
        llvm-symbolizer
        llvm-size
        llvm-strip
        llvm-config
        llvm-link
    )

    local tool versioned
    for tool in "${tools[@]}"; do
        versioned="/usr/bin/${tool}-${LLVM_VERSION}"
        if [[ -x "$versioned" ]]; then
            sudo update-alternatives \
                --install "/usr/bin/${tool}" "$tool" "$versioned" "$((LLVM_VERSION * 10))"
        fi
    done
    ok "LLVM alternatives configured"
}

# Detect the Windows username from WSL via cmd.exe for path probing.
detect_windows_user() {
    if ! command_exists cmd.exe; then
        return 1
    fi

    local detected
    detected="$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r' | xargs || true)"
    [[ -n "$detected" ]] || return 1
    printf '%s\n' "$detected"
}

install_windows_vscode() {
    CURRENT_STEP="install windows vscode"
    [[ "$INSTALL_WINDOWS_VSCODE" == "1" ]] || return 0

    if ! is_wsl; then
        warn "Not running under WSL; skipping the Windows VS Code installation."
        return 0
    fi

    if command_exists code || command_exists code.exe; then
        log "VS Code is already available"
        return 0
    fi

    if ! command_exists powershell.exe; then
        warn "powershell.exe is unavailable. Install VS Code on Windows manually."
        return 0
    fi

    if ! powershell.exe -NoProfile -NonInteractive -Command "if (\$null -eq (Get-Command winget -ErrorAction SilentlyContinue)) { exit 1 }" >/dev/null 2>&1; then
        warn "winget is unavailable in this Windows environment. Install VS Code manually on Windows."
        return 0
    fi

    log "Installing Windows VS Code with winget"
    powershell.exe -NoProfile -NonInteractive -Command \
        'winget install --id Microsoft.VisualStudioCode --exact --scope machine --accept-package-agreements --accept-source-agreements' \
        || warn "winget could not install VS Code. You may need to run the script again from an elevated Windows terminal."

    log "Installing the Windows VS Code WSL extension"
    # shellcheck disable=SC2016 # PowerShell expression uses $code, not shell expansion.
    powershell.exe -NoProfile -NonInteractive -Command \
        '$code = Get-Command code -ErrorAction SilentlyContinue; if ($code) { code --install-extension ms-vscode-remote.remote-wsl --force }' \
        || warn "Could not install the Windows-side WSL extension automatically."
    ok "Windows VS Code install step completed"
}

find_code_command() {
    if command_exists code; then
        printf '%s\n' "code"
        return 0
    fi

    if command_exists code.exe; then
        printf '%s\n' "code.exe"
        return 0
    fi

    # Common system-wide and per-user Windows VS Code paths exposed inside WSL.
    local candidate windows_user
    windows_user="${WINUSER:-}"
    if [[ -z "$windows_user" ]]; then
        windows_user="$(detect_windows_user || true)"
    fi

    for candidate in "/mnt/c/Program Files/Microsoft VS Code/bin/code"; do
        if [[ -n "${candidate}" && -x "${candidate}" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    if [[ -n "$windows_user" ]]; then
        candidate="/mnt/c/Users/${windows_user}/AppData/Local/Programs/Microsoft VS Code/bin/code"
        if [[ -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    fi

    return 1
}

install_vscode_extensions() {
    CURRENT_STEP="install vscode extensions"
    [[ "$INSTALL_VSCODE_EXTENSIONS" == "1" ]] || return 0

    local code_cmd
    if ! code_cmd="$(find_code_command)"; then
        warn "The code command is not yet visible in this WSL session."
        warn "Restart WSL, then rerun this script to install the extensions."
        return 0
    fi

    log "Installing recommended VS Code extensions"
    local extensions=(
        llvm-vs-code-extensions.vscode-clangd
        ms-vscode.cmake-tools
        twxs.cmake
        ms-vscode.cpptools-themes
        streetsidesoftware.code-spell-checker
    )

    local extension
    for extension in "${extensions[@]}"; do
        "$code_cmd" --install-extension "$extension" --force \
            || warn "Could not install VS Code extension: $extension"
    done
    ok "VS Code extensions step completed"
}

generate_vscode_workspace_defaults() {
    CURRENT_STEP="generate vscode workspace defaults"
    [[ "$GENERATE_VSCODE_SETTINGS" == "1" ]] || return 0

    local vscode_dir settings_file extensions_file
    vscode_dir="${PWD}/.vscode"
    settings_file="${vscode_dir}/settings.json"
    extensions_file="${vscode_dir}/extensions.json"

    mkdir -p "$vscode_dir"

    if [[ ! -e "$settings_file" ]]; then
        cat >"$settings_file" <<'EOF'
{
  "C_Cpp.intelliSenseEngine": "disabled",
  "clangd.arguments": [
    "--background-index",
    "--clang-tidy",
    "--header-insertion=iwyu"
  ],
  "cmake.generator": "Ninja",
  "cmake.configureOnOpen": true,
  "cmake.exportCompileCommandsFile": true,
  "editor.formatOnSave": true,
  "files.associations": {
    "*.ipp": "cpp",
    "*.tpp": "cpp"
  }
}
EOF
        ok "Created ${settings_file}"
    else
        warn "${settings_file} already exists; leaving it unchanged."
    fi

    if [[ ! -e "$extensions_file" ]]; then
        cat >"$extensions_file" <<'EOF'
{
  "recommendations": [
    "llvm-vs-code-extensions.vscode-clangd",
    "ms-vscode.cmake-tools",
    "twxs.cmake"
  ]
}
EOF
        ok "Created ${extensions_file}"
    else
        warn "${extensions_file} already exists; leaving it unchanged."
    fi
}

configure_git_and_ccache() {
    CURRENT_STEP="configure git and ccache"
    log "Applying small developer-friendly defaults"
    git config --global init.defaultBranch main
    git config --global core.autocrlf input

    mkdir -p "${HOME}/.config/ccache"
    cat >"${HOME}/.config/ccache/ccache.conf" <<'EOF'
max_size = 20G
compression = true
compression_level = 6
compiler_check = content
EOF
    ok "Git and ccache configured"
}

cleanup() {
    CURRENT_STEP="cleanup package cache"
    log "Cleaning package cache"
    sudo apt-get autoremove -y
    sudo apt-get clean
}

show_versions() {
    CURRENT_STEP="show versions and next actions"
    log "Installed versions"

    local commands=(
        "clang --version"
        "clangd --version"
        "clang-tidy --version"
        "lld --version"
        "lldb --version"
        "cmake --version"
        "ninja --version"
        "python3 --version"
        "git --version"
        "ccache --version"
    )

    local item
    for item in "${commands[@]}"; do
        printf '\n$ %s\n' "$item"
        bash -lc "$item" 2>/dev/null | head -n 3 || true
    done

    if command_exists python3.14; then
        printf '\n$ python3.14 --version\n'
        python3.14 --version
    fi

    cat <<EOF

Bootstrap complete.

LLVM source:
  ${LLVM_INSTALL_SOURCE}

Recommended CMake configure command:
  cmake -S . -B build -G Ninja \\
    -DCMAKE_C_COMPILER=clang \\
    -DCMAKE_CXX_COMPILER=clang++ \\
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \\
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

Open the current WSL directory in VS Code:
  code .

If 'code' is not found immediately, run this in Windows PowerShell:
  wsl --shutdown
Then reopen Ubuntu.

Recommended next actions for C++ in WSL:
  1) Keep code under Linux paths (for example: ~/src/my-project)
  2) Configure with Ninja + compile_commands.json (command above)
  3) Run clangd from VS Code in this WSL environment
EOF
}

main() {
    validate_configuration
    require_ubuntu
    show_startup_summary
    install_base_packages
    install_python_314
    install_llvm
    configure_llvm_alternatives
    install_windows_vscode
    install_vscode_extensions
    generate_vscode_workspace_defaults
    configure_git_and_ccache
    cleanup
    show_versions
}

main "$@"
