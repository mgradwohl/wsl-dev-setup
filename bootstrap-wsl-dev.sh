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
#   LLVM_VERSION=latest ./bootstrap-wsl-dev.sh
#   INSTALL_VSCODE_EXTENSIONS=0 ./bootstrap-wsl-dev.sh
#   INSTALL_WINDOWS_VSCODE=0 ./bootstrap-wsl-dev.sh
#   GENERATE_VSCODE_SETTINGS=1 ./bootstrap-wsl-dev.sh

LLVM_VERSION="${LLVM_VERSION:-latest}"
MIN_LLVM_VERSION=23
INSTALL_WINDOWS_VSCODE="${INSTALL_WINDOWS_VSCODE:-1}"
INSTALL_VSCODE_EXTENSIONS="${INSTALL_VSCODE_EXTENSIONS:-1}"
GENERATE_VSCODE_SETTINGS="${GENERATE_VSCODE_SETTINGS:-}"
INSTALL_OPTIONAL_TOOLS_PROMPT="${INSTALL_OPTIONAL_TOOLS_PROMPT:-1}"
INSTALL_GIT_LFS="${INSTALL_GIT_LFS:-}"
INSTALL_DOCS_TOOLS="${INSTALL_DOCS_TOOLS:-}"
INSTALL_IWYU="${INSTALL_IWYU:-}"
INSTALL_PROFILING_TOOLS="${INSTALL_PROFILING_TOOLS:-}"

CURRENT_STEP="startup"
LLVM_INSTALL_SOURCE="undetermined"
LLVM_VERSION_REQUESTED="$LLVM_VERSION"
LLVM_VERSION_SOURCE_DETAIL="pending resolution"

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

is_interactive_terminal() {
    [[ -t 0 && -t 1 ]]
}

validate_bool() {
    local name="$1"
    local value="$2"
    [[ "$value" =~ ^[01]$ ]] || die "${name} must be 0 or 1."
}

validate_bool_or_empty() {
    local name="$1"
    local value="$2"
    [[ -z "$value" || "$value" =~ ^[01]$ ]] || die "${name} must be 0, 1, or unset."
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-N}"
    local answer

    while true; do
        if [[ "$default" == "Y" ]]; then
            read -r -p "${prompt} [Y/n]: " answer
            answer="${answer:-Y}"
        else
            read -r -p "${prompt} [y/N]: " answer
            answer="${answer:-N}"
        fi

        case "${answer,,}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) warn "Please answer y or n." ;;
        esac
    done
}

validate_configuration() {
    CURRENT_STEP="validate configuration"

    if [[ "$LLVM_VERSION" != "latest" ]]; then
        [[ "$LLVM_VERSION" =~ ^[0-9]+$ ]] || die "LLVM_VERSION must be 'latest' or an integer (for example ${MIN_LLVM_VERSION})."
        ((LLVM_VERSION >= MIN_LLVM_VERSION)) || die "When numeric, LLVM_VERSION must be ${MIN_LLVM_VERSION} or newer."
    fi

    validate_bool "INSTALL_WINDOWS_VSCODE" "$INSTALL_WINDOWS_VSCODE"
    validate_bool "INSTALL_VSCODE_EXTENSIONS" "$INSTALL_VSCODE_EXTENSIONS"
    validate_bool "INSTALL_OPTIONAL_TOOLS_PROMPT" "$INSTALL_OPTIONAL_TOOLS_PROMPT"

    validate_bool_or_empty "GENERATE_VSCODE_SETTINGS" "$GENERATE_VSCODE_SETTINGS"
    validate_bool_or_empty "INSTALL_GIT_LFS" "$INSTALL_GIT_LFS"
    validate_bool_or_empty "INSTALL_DOCS_TOOLS" "$INSTALL_DOCS_TOOLS"
    validate_bool_or_empty "INSTALL_IWYU" "$INSTALL_IWYU"
    validate_bool_or_empty "INSTALL_PROFILING_TOOLS" "$INSTALL_PROFILING_TOOLS"
}

require_ubuntu() {
    CURRENT_STEP="detect ubuntu release"
    [[ -r /etc/os-release ]] || die "/etc/os-release was not found."
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "This script supports Ubuntu; detected ${ID:-unknown}."
    log "Detected Ubuntu ${VERSION_ID:-unknown} (${VERSION_CODENAME:-unknown})"
}

update_apt_metadata_and_resolve_llvm() {
    CURRENT_STEP="update apt metadata and resolve llvm version"
    log "Updating apt package metadata"
    sudo apt-get update

    if [[ "$LLVM_VERSION_REQUESTED" == "latest" ]]; then
        local resolved
        resolved="$(
            apt-cache search --names-only '^clang-[0-9][0-9]*$' \
                | awk '{print $1}' \
                | sed -E 's/^clang-([0-9]+)$/\1/' \
                | awk -v min="${MIN_LLVM_VERSION}" '$1 >= min' \
                | sort -nr \
                | head -n 1
        )"

        if [[ -n "$resolved" ]]; then
            LLVM_VERSION="$resolved"
            LLVM_VERSION_SOURCE_DETAIL="latest from configured apt metadata"
        else
            LLVM_VERSION="${MIN_LLVM_VERSION}"
            LLVM_VERSION_SOURCE_DETAIL="fallback minimum (${MIN_LLVM_VERSION}); no LLVM >=${MIN_LLVM_VERSION} package found in current apt metadata — will install from apt.llvm.org if unavailable in Ubuntu repos"
        fi
    else
        LLVM_VERSION_SOURCE_DETAIL="explicitly requested"
    fi
}

configure_optional_choices() {
    CURRENT_STEP="collect optional install choices"

    if [[ "$INSTALL_OPTIONAL_TOOLS_PROMPT" == "1" ]] && is_interactive_terminal; then
        log "Optional tool selection"

        if [[ -z "$INSTALL_GIT_LFS" ]]; then
            if ask_yes_no "Install Git LFS?" "Y"; then INSTALL_GIT_LFS="1"; else INSTALL_GIT_LFS="0"; fi
        fi

        if [[ -z "$INSTALL_DOCS_TOOLS" ]]; then
            if ask_yes_no "Install documentation tools (Doxygen + Graphviz)?" "N"; then INSTALL_DOCS_TOOLS="1"; else INSTALL_DOCS_TOOLS="0"; fi
        fi

        if [[ -z "$INSTALL_IWYU" ]]; then
            if ask_yes_no "Install Include-What-You-Use (IWYU) when available?" "N"; then INSTALL_IWYU="1"; else INSTALL_IWYU="0"; fi
        fi

        if [[ -z "$INSTALL_PROFILING_TOOLS" ]]; then
            if ask_yes_no "Install profiling tools (Valgrind + Heaptrack + gperftools) when available?" "N"; then INSTALL_PROFILING_TOOLS="1"; else INSTALL_PROFILING_TOOLS="0"; fi
        fi

        if [[ -z "$GENERATE_VSCODE_SETTINGS" ]]; then
            if ask_yes_no "Generate .vscode/settings.json and .vscode/extensions.json in current directory?" "N"; then GENERATE_VSCODE_SETTINGS="1"; else GENERATE_VSCODE_SETTINGS="0"; fi
        fi
    fi

    INSTALL_GIT_LFS="${INSTALL_GIT_LFS:-0}"
    INSTALL_DOCS_TOOLS="${INSTALL_DOCS_TOOLS:-0}"
    INSTALL_IWYU="${INSTALL_IWYU:-0}"
    INSTALL_PROFILING_TOOLS="${INSTALL_PROFILING_TOOLS:-0}"
    GENERATE_VSCODE_SETTINGS="${GENERATE_VSCODE_SETTINGS:-0}"

    validate_bool "INSTALL_GIT_LFS" "$INSTALL_GIT_LFS"
    validate_bool "INSTALL_DOCS_TOOLS" "$INSTALL_DOCS_TOOLS"
    validate_bool "INSTALL_IWYU" "$INSTALL_IWYU"
    validate_bool "INSTALL_PROFILING_TOOLS" "$INSTALL_PROFILING_TOOLS"
    validate_bool "GENERATE_VSCODE_SETTINGS" "$GENERATE_VSCODE_SETTINGS"
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
  - LLVM request:            ${LLVM_VERSION_REQUESTED}
  - LLVM selected:           ${LLVM_VERSION} (${LLVM_VERSION_SOURCE_DETAIL})
  - Install Windows VS Code: $([[ "$INSTALL_WINDOWS_VSCODE" == "1" ]] && echo "yes" || echo "no")
  - Install VS Code ext:     $([[ "$INSTALL_VSCODE_EXTENSIONS" == "1" ]] && echo "yes" || echo "no")
  - Generate .vscode files:  $([[ "$GENERATE_VSCODE_SETTINGS" == "1" ]] && echo "yes" || echo "no")
  - Install Git LFS:         $([[ "$INSTALL_GIT_LFS" == "1" ]] && echo "yes" || echo "no")
  - Install docs tools:      $([[ "$INSTALL_DOCS_TOOLS" == "1" ]] && echo "yes" || echo "no")
  - Install IWYU:            $([[ "$INSTALL_IWYU" == "1" ]] && echo "yes" || echo "no")
  - Install profiling tools: $([[ "$INSTALL_PROFILING_TOOLS" == "1" ]] && echo "yes" || echo "no")

EOF
}

install_base_packages() {
    CURRENT_STEP="install base packages"
    # Deliberately avoid full-upgrade to reduce risk in repeatable bootstrap runs.
    log "Applying available package upgrades"
    sudo DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

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

install_optional_packages() {
    CURRENT_STEP="install optional packages"
    local requested=()
    local installable=()
    local package

    if [[ "$INSTALL_GIT_LFS" == "1" ]]; then
        requested+=("git-lfs")
    fi
    if [[ "$INSTALL_DOCS_TOOLS" == "1" ]]; then
        requested+=("doxygen" "graphviz")
    fi
    if [[ "$INSTALL_IWYU" == "1" ]]; then
        requested+=("include-what-you-use")
    fi
    if [[ "$INSTALL_PROFILING_TOOLS" == "1" ]]; then
        requested+=("valgrind" "heaptrack" "libgoogle-perftools-dev")
    fi

    if ((${#requested[@]} == 0)); then
        log "No optional packages selected"
        return 0
    fi

    for package in "${requested[@]}"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            installable+=("$package")
        else
            warn "Optional package not available on this release: $package"
        fi
    done

    if ((${#installable[@]} > 0)); then
        log "Installing selected optional packages"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${installable[@]}"
        ok "Optional packages installed"
    fi

    if [[ "$INSTALL_GIT_LFS" == "1" ]] && command_exists git-lfs; then
        git lfs install >/dev/null 2>&1 || true
    fi
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
        log "Adding apt.llvm.org repository for LLVM ${LLVM_VERSION}"

        local keyring_path="/usr/share/keyrings/llvm-snapshot.gpg"
        curl --fail --location --silent --show-error \
            --proto '=https' --tlsv1.2 \
            --retry 3 --retry-connrefused \
            https://apt.llvm.org/llvm-snapshot.gpg.key \
            | sudo gpg --dearmor --yes -o "$keyring_path"

local sources_file="/etc/apt/sources.list.d/llvm-${LLVM_VERSION}.list"
printf 'deb [signed-by=%s] https://apt.llvm.org/%s/ llvm-toolchain-%s-%s main\n' \
    "$keyring_path" "${VERSION_CODENAME}" "${VERSION_CODENAME}" "${LLVM_VERSION}" \
    | sudo tee "$sources_file" >/dev/null

if ! sudo apt-get update; then
    sudo rm -f "$sources_file"
    die "Failed to update apt metadata after adding apt.llvm.org for LLVM ${LLVM_VERSION} (Ubuntu: ${VERSION_CODENAME}). Removed ${sources_file}; verify this release/version is supported by apt.llvm.org."
fi
        local installable=()
        local pkg
        for pkg in "${packages[@]}"; do
            if apt-cache show "$pkg" >/dev/null 2>&1; then
                installable+=("$pkg")
            else
                warn "LLVM package not available from configured repos: $pkg"
            fi
        done
        ((${#installable[@]} > 0)) || die "No installable LLVM packages found for LLVM_VERSION=${LLVM_VERSION}."
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${installable[@]}"
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

# Try to detect the Windows username from WSL via cmd.exe for path probing.
try_detect_windows_user() {
    if ! command_exists cmd.exe; then
        return 1
    fi

    local detected
    detected="$(cmd.exe /C "echo %USERNAME%" 2>/dev/null | tr -d '\r' || true)"
    [[ -n "$detected" ]] || return 1
    printf '%s\n' "$detected"
}

winget_available() {
    powershell.exe -NoProfile -NonInteractive -Command \
        "if (\$null -eq (Get-Command winget -ErrorAction SilentlyContinue)) { exit 1 }"
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

    if ! winget_available >/dev/null 2>&1; then
        warn "winget is unavailable in this Windows environment. Install VS Code manually on Windows."
        return 0
    fi

    log "Installing Windows VS Code with winget"
    powershell.exe -NoProfile -NonInteractive -Command \
        'winget install --id Microsoft.VisualStudioCode --exact --scope machine --accept-package-agreements --accept-source-agreements' \
        || warn "winget could not install VS Code. You may need to run the script again from an elevated Windows terminal."

    log "Installing the Windows VS Code WSL extension"
    # shellcheck disable=SC2016 # PowerShell variable $code must not be shell-expanded by bash.
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
        windows_user="$(try_detect_windows_user || true)"
    fi

    candidate="/mnt/c/Program Files/Microsoft VS Code/bin/code"
    if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
    fi

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

    if [[ -e "$vscode_dir" && ! -d "$vscode_dir" ]]; then
        die "${vscode_dir} exists but is not a directory; remove or rename it before generating VS Code workspace defaults."
    fi
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
    update_apt_metadata_and_resolve_llvm
    configure_optional_choices
    show_startup_summary
    install_base_packages
    install_optional_packages
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
