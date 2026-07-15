#!/usr/bin/env bash
set -Eeuo pipefail

# WSL Ubuntu C++ development bootstrap
# Intended for Ubuntu 26.04, but includes reasonable fallbacks.
#
# Usage:
#   chmod +x bootstrap-wsl-dev.sh
#   ./bootstrap-wsl-dev.sh
#
# Optional environment variables:
#   LLVM_VERSION=22 ./bootstrap-wsl-dev.sh
#   INSTALL_VSCODE_EXTENSIONS=0 ./bootstrap-wsl-dev.sh
#   INSTALL_WINDOWS_VSCODE=0 ./bootstrap-wsl-dev.sh

LLVM_VERSION="${LLVM_VERSION:-22}"
INSTALL_WINDOWS_VSCODE="${INSTALL_WINDOWS_VSCODE:-1}"
INSTALL_VSCODE_EXTENSIONS="${INSTALL_VSCODE_EXTENSIONS:-1}"

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

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

is_wsl() {
    grep -qiE '(microsoft|wsl)' /proc/version 2>/dev/null
}

require_ubuntu() {
    [[ -r /etc/os-release ]] || die "/etc/os-release was not found."
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "This script supports Ubuntu; detected ${ID:-unknown}."
    log "Detected Ubuntu ${VERSION_ID:-unknown} (${VERSION_CODENAME:-unknown})"
}

install_base_packages() {
    log "Updating Ubuntu packages"
    sudo apt-get update
    sudo DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y

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
}

install_python_314() {
    if apt-cache show python3.14 >/dev/null 2>&1; then
        log "Installing Python 3.14"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            python3.14 \
            python3.14-dev \
            python3.14-venv
    else
        warn "python3.14 is not available from this Ubuntu release's configured repositories."
        warn "Leaving the distro-provided python3 installed rather than adding an unofficial PPA."
    fi
}

install_llvm() {
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
        log "Installing LLVM/Clang ${LLVM_VERSION} from Ubuntu repositories"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
    else
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
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
            "clangd-${LLVM_VERSION}" \
            "clang-format-${LLVM_VERSION}" \
            "clang-tidy-${LLVM_VERSION}" \
            "clang-tools-${LLVM_VERSION}" \
            "libc++-${LLVM_VERSION}-dev" \
            "libc++abi-${LLVM_VERSION}-dev"
    fi
}

configure_llvm_alternatives() {
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
        llvm-size
        llvm-strip
    )

    local tool versioned
    for tool in "${tools[@]}"; do
        versioned="/usr/bin/${tool}-${LLVM_VERSION}"
        if [[ -x "$versioned" ]]; then
            sudo update-alternatives \
                --install "/usr/bin/${tool}" "$tool" "$versioned" "$((LLVM_VERSION * 10))"
        fi
    done
}

install_windows_vscode() {
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

    log "Installing Windows VS Code with winget"
    powershell.exe -NoProfile -NonInteractive -Command \
        'winget install --id Microsoft.VisualStudioCode --exact --scope machine --accept-package-agreements --accept-source-agreements' \
        || warn "winget could not install VS Code. You may need to run the script again from an elevated Windows terminal."

    log "Installing the Windows VS Code WSL extension"
    powershell.exe -NoProfile -NonInteractive -Command \
        '$code = Get-Command code -ErrorAction SilentlyContinue; if ($code) { code --install-extension ms-vscode-remote.remote-wsl --force }' \
        || warn "Could not install the Windows-side WSL extension automatically."
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
    local candidate
    for candidate in \
        "/mnt/c/Program Files/Microsoft VS Code/bin/code" \
        "/mnt/c/Users/${WINUSER:-}/AppData/Local/Programs/Microsoft VS Code/bin/code"; do
        if [[ -n "${candidate}" && -x "${candidate}" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

install_vscode_extensions() {
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
        ms-python.python
        ms-python.vscode-pylance
        eamodio.gitlens
    )

    local extension
    for extension in "${extensions[@]}"; do
        "$code_cmd" --install-extension "$extension" --force \
            || warn "Could not install VS Code extension: $extension"
    done
}

configure_git_and_ccache() {
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
}

cleanup() {
    log "Cleaning package cache"
    sudo apt-get autoremove -y
    sudo apt-get clean
}

show_versions() {
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

Recommended CMake configure command:
  cmake -S . -B build -G Ninja \\
    -DCMAKE_C_COMPILER=clang \\
    -DCMAKE_CXX_COMPILER=clang++ \\
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache

Open the current WSL directory in VS Code:
  code .

If 'code' is not found immediately, run this in Windows PowerShell:
  wsl --shutdown
Then reopen Ubuntu.
EOF
}

main() {
    require_ubuntu
    install_base_packages
    install_python_314
    install_llvm
    configure_llvm_alternatives
    install_windows_vscode
    install_vscode_extensions
    configure_git_and_ccache
    cleanup
    show_versions
}

main "$@"
