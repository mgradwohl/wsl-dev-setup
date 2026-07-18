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
COPILOT_TOOLS_BUNDLE_LABEL="git-delta, universal-ctags, entr, cloc, sqlite3, direnv, pipx, zsh, bash-completion"
INSTALL_WINDOWS_VSCODE="${INSTALL_WINDOWS_VSCODE:-1}"
INSTALL_VSCODE_EXTENSIONS="${INSTALL_VSCODE_EXTENSIONS:-1}"
INSTALL_VSCODE_EXT_CLANGD="${INSTALL_VSCODE_EXT_CLANGD:-}"
INSTALL_VSCODE_EXT_CMAKE_TOOLS="${INSTALL_VSCODE_EXT_CMAKE_TOOLS:-}"
INSTALL_VSCODE_EXT_CMAKE_SYNTAX="${INSTALL_VSCODE_EXT_CMAKE_SYNTAX:-}"
GENERATE_VSCODE_SETTINGS="${GENERATE_VSCODE_SETTINGS:-}"
INSTALL_OPTIONAL_TOOLS_PROMPT="${INSTALL_OPTIONAL_TOOLS_PROMPT:-1}"
INSTALL_GIT_LFS="${INSTALL_GIT_LFS:-}"
INSTALL_GITHUB_CLI="${INSTALL_GITHUB_CLI:-}"
INSTALL_COPILOT_TOOLS="${INSTALL_COPILOT_TOOLS:-}"
INSTALL_DOCS_TOOLS="${INSTALL_DOCS_TOOLS:-}"
INSTALL_IWYU="${INSTALL_IWYU:-}"
INSTALL_PROFILING_TOOLS="${INSTALL_PROFILING_TOOLS:-}"
INSTALL_PROFILE_PERFORMANCE="${INSTALL_PROFILE_PERFORMANCE:-}"
INSTALL_PROFILE_RELIABILITY="${INSTALL_PROFILE_RELIABILITY:-}"
INSTALL_PROFILE_TESTING="${INSTALL_PROFILE_TESTING:-}"
INSTALL_PROFILE_PRODUCTIVITY="${INSTALL_PROFILE_PRODUCTIVITY:-}"
CHECK_ONLY="${CHECK_ONLY:-0}"

CURRENT_STEP="startup"
LLVM_INSTALL_SOURCE="undetermined"
LLVM_VERSION_REQUESTED="$LLVM_VERSION"
LLVM_VERSION_SOURCE_DETAIL="pending resolution"
IWYU_INSTALL_CANDIDATE=""
WARNINGS=()
LLVM_OPTIONAL_MISSING=()
LLVM_OPTIONAL_FALLBACK_USED=()
LLVM_OPTIONAL_FALLBACK_REJECTED=()
LLVM_ALTERNATIVES_CONFIGURED=()
LLVM_ALTERNATIVES_SKIPPED=()
APT_LLVM_REPO_ENABLED=0

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

log() {
    printf '\n\033[1;34m==>\033[0m %s\n' "$*"
}

warn() {
    WARNINGS+=("$*")
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
            if ! read -r -p "${prompt} [Y/n]: " answer; then
                answer="Y"
            fi
            answer="${answer:-Y}"
        else
            if ! read -r -p "${prompt} [y/N]: " answer; then
                answer="N"
            fi
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
    validate_bool "CHECK_ONLY" "$CHECK_ONLY"

    validate_bool_or_empty "GENERATE_VSCODE_SETTINGS" "$GENERATE_VSCODE_SETTINGS"
    validate_bool_or_empty "INSTALL_VSCODE_EXT_CLANGD" "$INSTALL_VSCODE_EXT_CLANGD"
    validate_bool_or_empty "INSTALL_VSCODE_EXT_CMAKE_TOOLS" "$INSTALL_VSCODE_EXT_CMAKE_TOOLS"
    validate_bool_or_empty "INSTALL_VSCODE_EXT_CMAKE_SYNTAX" "$INSTALL_VSCODE_EXT_CMAKE_SYNTAX"
    validate_bool_or_empty "INSTALL_GIT_LFS" "$INSTALL_GIT_LFS"
    validate_bool_or_empty "INSTALL_GITHUB_CLI" "$INSTALL_GITHUB_CLI"
    validate_bool_or_empty "INSTALL_COPILOT_TOOLS" "$INSTALL_COPILOT_TOOLS"
    validate_bool_or_empty "INSTALL_DOCS_TOOLS" "$INSTALL_DOCS_TOOLS"
    validate_bool_or_empty "INSTALL_IWYU" "$INSTALL_IWYU"
    validate_bool_or_empty "INSTALL_PROFILING_TOOLS" "$INSTALL_PROFILING_TOOLS"
    validate_bool_or_empty "INSTALL_PROFILE_PERFORMANCE" "$INSTALL_PROFILE_PERFORMANCE"
    validate_bool_or_empty "INSTALL_PROFILE_RELIABILITY" "$INSTALL_PROFILE_RELIABILITY"
    validate_bool_or_empty "INSTALL_PROFILE_TESTING" "$INSTALL_PROFILE_TESTING"
    validate_bool_or_empty "INSTALL_PROFILE_PRODUCTIVITY" "$INSTALL_PROFILE_PRODUCTIVITY"
}

require_ubuntu() {
    CURRENT_STEP="detect ubuntu release"
    [[ -r /etc/os-release ]] || die "/etc/os-release was not found."
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "This script supports Ubuntu; detected ${ID:-unknown}."
    [[ -n "${VERSION_ID:-}" ]] || die "Could not determine Ubuntu VERSION_ID from /etc/os-release."
    dpkg --compare-versions "$VERSION_ID" ge "24.04" || die "Ubuntu 24.04+ is required; detected ${VERSION_ID}."
    log "Detected Ubuntu ${VERSION_ID:-unknown} (${VERSION_CODENAME:-unknown})"
}

show_startup_banner() {
    cat <<'EOF'

============================================================
  WSL C++ Bootstrap (Clang/LLVM-first)
============================================================

EOF
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

        if [[ -z "$INSTALL_GITHUB_CLI" ]]; then
            if ask_yes_no "Install GitHub CLI (gh)?" "Y"; then INSTALL_GITHUB_CLI="1"; else INSTALL_GITHUB_CLI="0"; fi
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

        log "Developer tool bundles"
        if [[ -z "$INSTALL_PROFILE_PERFORMANCE" ]]; then
            if ask_yes_no "Install Performance bundle (mold, hyperfine, hotspot, perf helpers when available)?" "N"; then INSTALL_PROFILE_PERFORMANCE="1"; else INSTALL_PROFILE_PERFORMANCE="0"; fi
        fi
        if [[ -z "$INSTALL_PROFILE_RELIABILITY" ]]; then
            if ask_yes_no "Install Reliability bundle (cppcheck, bear, debuginfod, diagnostics tools)?" "N"; then INSTALL_PROFILE_RELIABILITY="1"; else INSTALL_PROFILE_RELIABILITY="0"; fi
        fi
        if [[ -z "$INSTALL_PROFILE_TESTING" ]]; then
            if ask_yes_no "Install Testing bundle (lcov, gcovr, catch2/googletest headers)?" "N"; then INSTALL_PROFILE_TESTING="1"; else INSTALL_PROFILE_TESTING="0"; fi
        fi
        if [[ -z "$INSTALL_PROFILE_PRODUCTIVITY" ]]; then
            if ask_yes_no "Install Productivity bundle (ripgrep, fzf, shell tooling, terminal helpers)?" "N"; then INSTALL_PROFILE_PRODUCTIVITY="1"; else INSTALL_PROFILE_PRODUCTIVITY="0"; fi
        fi
        if [[ -z "$INSTALL_COPILOT_TOOLS" ]]; then
            if ask_yes_no "Install common Copilot tools (${COPILOT_TOOLS_BUNDLE_LABEL})?" "N"; then INSTALL_COPILOT_TOOLS="1"; else INSTALL_COPILOT_TOOLS="0"; fi
        fi

        if [[ -z "$GENERATE_VSCODE_SETTINGS" ]]; then
            if ask_yes_no "Generate .vscode/settings.json and .vscode/extensions.json in current directory?" "N"; then GENERATE_VSCODE_SETTINGS="1"; else GENERATE_VSCODE_SETTINGS="0"; fi
        fi

        if [[ "$INSTALL_VSCODE_EXTENSIONS" == "1" ]]; then
            log "VS Code extension selection"
            if [[ -z "$INSTALL_VSCODE_EXT_CLANGD" ]]; then
                if ask_yes_no "Install VS Code extension: llvm-vs-code-extensions.vscode-clangd?" "Y"; then INSTALL_VSCODE_EXT_CLANGD="1"; else INSTALL_VSCODE_EXT_CLANGD="0"; fi
            fi
            if [[ -z "$INSTALL_VSCODE_EXT_CMAKE_TOOLS" ]]; then
                if ask_yes_no "Install VS Code extension: ms-vscode.cmake-tools?" "Y"; then INSTALL_VSCODE_EXT_CMAKE_TOOLS="1"; else INSTALL_VSCODE_EXT_CMAKE_TOOLS="0"; fi
            fi
            if [[ -z "$INSTALL_VSCODE_EXT_CMAKE_SYNTAX" ]]; then
                if ask_yes_no "Install VS Code extension: twxs.cmake?" "Y"; then INSTALL_VSCODE_EXT_CMAKE_SYNTAX="1"; else INSTALL_VSCODE_EXT_CMAKE_SYNTAX="0"; fi
            fi
        fi
    fi

    INSTALL_GIT_LFS="${INSTALL_GIT_LFS:-0}"
    INSTALL_GITHUB_CLI="${INSTALL_GITHUB_CLI:-0}"
    INSTALL_DOCS_TOOLS="${INSTALL_DOCS_TOOLS:-0}"
    INSTALL_IWYU="${INSTALL_IWYU:-0}"
    INSTALL_PROFILING_TOOLS="${INSTALL_PROFILING_TOOLS:-0}"
    INSTALL_PROFILE_PERFORMANCE="${INSTALL_PROFILE_PERFORMANCE:-0}"
    INSTALL_PROFILE_RELIABILITY="${INSTALL_PROFILE_RELIABILITY:-0}"
    INSTALL_PROFILE_TESTING="${INSTALL_PROFILE_TESTING:-0}"
    INSTALL_PROFILE_PRODUCTIVITY="${INSTALL_PROFILE_PRODUCTIVITY:-0}"
    INSTALL_COPILOT_TOOLS="${INSTALL_COPILOT_TOOLS:-0}"
    GENERATE_VSCODE_SETTINGS="${GENERATE_VSCODE_SETTINGS:-0}"
    if [[ "$INSTALL_VSCODE_EXTENSIONS" == "1" ]]; then
        INSTALL_VSCODE_EXT_CLANGD="${INSTALL_VSCODE_EXT_CLANGD:-1}"
        INSTALL_VSCODE_EXT_CMAKE_TOOLS="${INSTALL_VSCODE_EXT_CMAKE_TOOLS:-1}"
        INSTALL_VSCODE_EXT_CMAKE_SYNTAX="${INSTALL_VSCODE_EXT_CMAKE_SYNTAX:-1}"
    else
        INSTALL_VSCODE_EXT_CLANGD="${INSTALL_VSCODE_EXT_CLANGD:-0}"
        INSTALL_VSCODE_EXT_CMAKE_TOOLS="${INSTALL_VSCODE_EXT_CMAKE_TOOLS:-0}"
        INSTALL_VSCODE_EXT_CMAKE_SYNTAX="${INSTALL_VSCODE_EXT_CMAKE_SYNTAX:-0}"
    fi

    validate_bool "INSTALL_GIT_LFS" "$INSTALL_GIT_LFS"
    validate_bool "INSTALL_GITHUB_CLI" "$INSTALL_GITHUB_CLI"
    validate_bool "INSTALL_DOCS_TOOLS" "$INSTALL_DOCS_TOOLS"
    validate_bool "INSTALL_IWYU" "$INSTALL_IWYU"
    validate_bool "INSTALL_PROFILING_TOOLS" "$INSTALL_PROFILING_TOOLS"
    validate_bool "INSTALL_PROFILE_PERFORMANCE" "$INSTALL_PROFILE_PERFORMANCE"
    validate_bool "INSTALL_PROFILE_RELIABILITY" "$INSTALL_PROFILE_RELIABILITY"
    validate_bool "INSTALL_PROFILE_TESTING" "$INSTALL_PROFILE_TESTING"
    validate_bool "INSTALL_PROFILE_PRODUCTIVITY" "$INSTALL_PROFILE_PRODUCTIVITY"
    validate_bool "INSTALL_COPILOT_TOOLS" "$INSTALL_COPILOT_TOOLS"
    validate_bool "GENERATE_VSCODE_SETTINGS" "$GENERATE_VSCODE_SETTINGS"
    validate_bool "INSTALL_VSCODE_EXT_CLANGD" "$INSTALL_VSCODE_EXT_CLANGD"
    validate_bool "INSTALL_VSCODE_EXT_CMAKE_TOOLS" "$INSTALL_VSCODE_EXT_CMAKE_TOOLS"
    validate_bool "INSTALL_VSCODE_EXT_CMAKE_SYNTAX" "$INSTALL_VSCODE_EXT_CMAKE_SYNTAX"
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
    - VS Code ext (clangd):    $([[ "$INSTALL_VSCODE_EXT_CLANGD" == "1" ]] && echo "yes" || echo "no")
    - VS Code ext (cmake):     $([[ "$INSTALL_VSCODE_EXT_CMAKE_TOOLS" == "1" ]] && echo "yes" || echo "no")
    - VS Code ext (syntax):    $([[ "$INSTALL_VSCODE_EXT_CMAKE_SYNTAX" == "1" ]] && echo "yes" || echo "no")
  - Generate .vscode files:  $([[ "$GENERATE_VSCODE_SETTINGS" == "1" ]] && echo "yes" || echo "no")
  - Check-only mode:         $([[ "$CHECK_ONLY" == "1" ]] && echo "yes" || echo "no")
  - Install Git LFS:         $([[ "$INSTALL_GIT_LFS" == "1" ]] && echo "yes" || echo "no")
  - Install GitHub CLI:      $([[ "$INSTALL_GITHUB_CLI" == "1" ]] && echo "yes" || echo "no")
  - Install docs tools:      $([[ "$INSTALL_DOCS_TOOLS" == "1" ]] && echo "yes" || echo "no")
  - Install IWYU:            $([[ "$INSTALL_IWYU" == "1" ]] && echo "yes" || echo "no")
  - Install profiling tools: $([[ "$INSTALL_PROFILING_TOOLS" == "1" ]] && echo "yes" || echo "no")
  - Perf bundle:             $([[ "$INSTALL_PROFILE_PERFORMANCE" == "1" ]] && echo "yes" || echo "no")
    - Reliability bundle:      $([[ "$INSTALL_PROFILE_RELIABILITY" == "1" ]] && echo "yes" || echo "no")
    - Testing bundle:          $([[ "$INSTALL_PROFILE_TESTING" == "1" ]] && echo "yes" || echo "no")
    - Productivity bundle:     $([[ "$INSTALL_PROFILE_PRODUCTIVITY" == "1" ]] && echo "yes" || echo "no")
    - Copilot tools bundle:    $([[ "$INSTALL_COPILOT_TOOLS" == "1" ]] && echo "yes" || echo "no")

EOF
}

show_resolved_llvm_summary() {
    CURRENT_STEP="print resolved llvm summary"
    cat <<EOF

Resolved LLVM selection:
    - LLVM selected: ${LLVM_VERSION} (${LLVM_VERSION_SOURCE_DETAIL})

EOF
}

confirm_startup_if_interactive() {
    CURRENT_STEP="confirm startup"
    if is_interactive_terminal; then
        if ! ask_yes_no "Proceed with bootstrap using the configuration above?" "Y"; then
            die "Bootstrap cancelled by user."
        fi
    fi
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
    if [[ "$INSTALL_GITHUB_CLI" == "1" ]]; then
        requested+=("gh")
    fi
    if [[ "$INSTALL_DOCS_TOOLS" == "1" ]]; then
        requested+=("doxygen" "graphviz")
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

install_tool_profile_bundles() {
    CURRENT_STEP="install tool profile bundles"
    local requested=()
    local installable=()
    local package

    if [[ "$INSTALL_PROFILE_PERFORMANCE" == "1" ]]; then
        requested+=("mold" "hyperfine" "hotspot" "linux-tools-common" "linux-tools-generic")
    fi
    if [[ "$INSTALL_PROFILE_RELIABILITY" == "1" ]]; then
        requested+=("cppcheck" "bear" "elfutils" "debuginfod")
    fi
    if [[ "$INSTALL_PROFILE_TESTING" == "1" ]]; then
        requested+=("lcov" "gcovr" "catch2" "libgtest-dev")
    fi
    if [[ "$INSTALL_PROFILE_PRODUCTIVITY" == "1" ]]; then
        requested+=(
            "ripgrep"
            "fd-find"
            "bat"
            "fzf"
            "yq"
            "tree"
            "shellcheck"
            "shfmt"
            "htop"
            "btop"
            "ncdu"
            "tmux"
        )
    fi

    if ((${#requested[@]} == 0)); then
        log "No tool profile bundles selected"
        return 0
    fi

    for package in "${requested[@]}"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            installable+=("$package")
        else
            warn "Tool profile package not available on this release: $package"
        fi
    done

    if ((${#installable[@]} > 0)); then
        log "Installing selected tool profile bundles"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${installable[@]}"
        ok "Tool profile bundles installed"
    fi
}

install_copilot_tools() {
    CURRENT_STEP="install common Copilot tools"
    [[ "$INSTALL_COPILOT_TOOLS" == "1" ]] || return 0

    local gh_auth_timeout_seconds=15
    local gh_query_timeout_seconds=30
    local gh_install_timeout_seconds=60
    local requested_packages=(
        "git-delta"
        "universal-ctags"
        "entr"
        "cloc"
        "sqlite3"
        "direnv"
        "pipx"
        "zsh"
        "bash-completion"
    )
    local installable=()
    local package

    for package in "${requested_packages[@]}"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            installable+=("$package")
        else
            warn "Copilot tool package not available on this release: $package"
        fi
    done

    if ((${#installable[@]} > 0)); then
        log "Installing common Copilot tools"
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${installable[@]}"
        ok "Common Copilot tools installed"
    else
        warn "No common Copilot tools were installable from the configured repositories."
        return 0
    fi

    if command_exists delta; then
        git config --global core.pager delta
        git config --global interactive.diffFilter "delta --color-only"
        git config --global delta.navigate true
        git config --global delta.light false
        git config --global merge.conflictstyle zdiff3
        ok "Configured git-delta as the default Git pager"
    fi

    if command_exists gh; then
        local gh_auth_status=0
        local gh_extensions
        if timeout "${gh_auth_timeout_seconds}s" gh auth status >/dev/null 2>&1; then
            gh_auth_status=0
        else
            gh_auth_status=$?
        fi

        if [[ "$gh_auth_status" -eq 0 ]]; then
            if gh_extensions="$(timeout "${gh_query_timeout_seconds}s" gh extension list 2>/dev/null)"; then
                if ! printf '%s\n' "$gh_extensions" | awk '{print $1}' | grep -qx 'github/gh-copilot'; then
                    log "Installing GitHub Copilot CLI extension for gh"
                    if timeout "${gh_install_timeout_seconds}s" gh extension install github/gh-copilot; then
                        ok "Installed gh-copilot extension"
                    else
                        warn "Could not install gh-copilot extension automatically."
                    fi
                fi
            else
                warn "Could not query gh extensions automatically; skipping gh-copilot extension installation."
            fi
        elif [[ "$gh_auth_status" -eq 124 ]]; then
            warn "Timed out while checking GitHub CLI authentication; skipping gh-copilot extension installation."
        else
            warn "GitHub CLI is not authenticated; skipping gh-copilot extension installation."
        fi
    else
        warn "GitHub CLI is not installed; skipping gh-copilot extension installation."
    fi
}

show_check_only_plan() {
    CURRENT_STEP="show check-only plan"

    cat <<EOF

CHECK-ONLY PLAN

No package installs or system changes will be made.

Planned actions:
  1) Update apt metadata and resolve LLVM major from request: ${LLVM_VERSION_REQUESTED}
  2) Install base packages: build-essential, cmake, ninja-build, ccache, gdb, git, python3 toolchain, and helpers
  3) Install optional packages by selection:
     - Git LFS: $([[ "$INSTALL_GIT_LFS" == "1" ]] && echo "yes" || echo "no")
     - GitHub CLI: $([[ "$INSTALL_GITHUB_CLI" == "1" ]] && echo "yes" || echo "no")
     - Docs tools: $([[ "$INSTALL_DOCS_TOOLS" == "1" ]] && echo "yes" || echo "no")
     - Profiling tools: $([[ "$INSTALL_PROFILING_TOOLS" == "1" ]] && echo "yes" || echo "no")
  4) Install tool profile bundles by selection:
     - Performance bundle: $([[ "$INSTALL_PROFILE_PERFORMANCE" == "1" ]] && echo "yes" || echo "no")
      - Reliability bundle: $([[ "$INSTALL_PROFILE_RELIABILITY" == "1" ]] && echo "yes" || echo "no")
      - Testing bundle: $([[ "$INSTALL_PROFILE_TESTING" == "1" ]] && echo "yes" || echo "no")
      - Productivity bundle: $([[ "$INSTALL_PROFILE_PRODUCTIVITY" == "1" ]] && echo "yes" || echo "no")
  5) Install common Copilot tools bundle by selection:
     - Copilot tools bundle: $([[ "$INSTALL_COPILOT_TOOLS" == "1" ]] && echo "yes" || echo "no")
     - Includes: ${COPILOT_TOOLS_BUNDLE_LABEL}
     - Optional add-on: gh-copilot extension when gh is installed
  6) Install LLVM/Clang (${LLVM_VERSION_REQUESTED}) required package set; for optional LLVM packages try exact version, then apt.llvm.org exact, then unversioned fallback at least one major behind selected LLVM
  7) Install IWYU if selected and available via candidate resolution
  8) Configure LLVM alternatives
  9) Optionally install Windows VS Code (machine scope) and VS Code extensions
     - clangd extension: $([[ "$INSTALL_VSCODE_EXT_CLANGD" == "1" ]] && echo "yes" || echo "no")
     - CMake Tools extension: $([[ "$INSTALL_VSCODE_EXT_CMAKE_TOOLS" == "1" ]] && echo "yes" || echo "no")
     - CMake syntax extension: $([[ "$INSTALL_VSCODE_EXT_CMAKE_SYNTAX" == "1" ]] && echo "yes" || echo "no")
  10) Optionally generate .vscode defaults in current directory
  11) Configure git + ccache defaults and show versions

To run for real, set CHECK_ONLY=0 (or unset it) and rerun.

EOF
}

configure_iwyu_candidate() {
    CURRENT_STEP="resolve iwyu package candidate"
    [[ "$INSTALL_IWYU" == "1" ]] || return 0

    local candidate
    local candidates=(
        "include-what-you-use-${LLVM_VERSION}"
        "include-what-you-use"
        "iwyu"
    )

    for candidate in "${candidates[@]}"; do
        if apt-cache show "$candidate" >/dev/null 2>&1; then
            IWYU_INSTALL_CANDIDATE="$candidate"
            return 0
        fi
    done

    IWYU_INSTALL_CANDIDATE=""
}

install_iwyu_if_selected() {
    CURRENT_STEP="install include-what-you-use"
    [[ "$INSTALL_IWYU" == "1" ]] || return 0

    configure_iwyu_candidate

    if [[ -z "$IWYU_INSTALL_CANDIDATE" ]]; then
        warn "IWYU was requested, but no package candidate is available on this release (tried include-what-you-use-${LLVM_VERSION}, include-what-you-use, iwyu)."
        warn "Skipping IWYU installation."
        return 0
    fi

    log "Installing IWYU package: ${IWYU_INSTALL_CANDIDATE}"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$IWYU_INSTALL_CANDIDATE"
    ok "IWYU installed (${IWYU_INSTALL_CANDIDATE})"
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

enable_apt_llvm_repo() {
    local required="${1:-1}"
    [[ "$APT_LLVM_REPO_ENABLED" == "0" ]] || return 0

    # apt.llvm.org does not publish every Ubuntu codename immediately.
    # Keep this list conservative and update as new codenames appear.
    local supported_codenames=(
        noble
        jammy
        focal
        bionic
    )
    local codename_supported=0
    local codename
    for codename in "${supported_codenames[@]}"; do
        if [[ "$VERSION_CODENAME" == "$codename" ]]; then
            codename_supported=1
            break
        fi
    done

    if [[ "$codename_supported" == "0" ]]; then
        if [[ "$required" == "1" ]]; then
            die "apt.llvm.org does not currently list Ubuntu codename '${VERSION_CODENAME}' for LLVM ${LLVM_VERSION}. Required LLVM packages are unavailable in Ubuntu repositories, so installation cannot continue."
        fi
        warn "apt.llvm.org does not currently list Ubuntu codename '${VERSION_CODENAME}'; skipping optional apt.llvm.org lookup and continuing with fallback resolution."
        return 1
    fi

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
        if [[ "$required" == "1" ]]; then
            die "Failed to update apt metadata after adding apt.llvm.org for LLVM ${LLVM_VERSION} (Ubuntu: ${VERSION_CODENAME}). Removed ${sources_file}; verify this release/version is supported by apt.llvm.org."
        fi
        warn "apt.llvm.org is not available for Ubuntu ${VERSION_CODENAME}; skipping apt.llvm.org optional lookup and continuing with fallback resolution."
        return 1
    fi

    APT_LLVM_REPO_ENABLED=1
}

apt_package_major() {
    local package="$1"
    local version
    version="$(apt-cache show "$package" 2>/dev/null | awk '/^Version:/{print $2; exit}')"
    [[ -n "$version" ]] || return 1

    # Strip epoch (for example 1:23.0.0-...) before extracting a major.
    version="${version#*:}"
    local major
    major="$(printf '%s\n' "$version" | grep -Eo '^[0-9]+' || true)"
    [[ -n "$major" ]] || return 1
    printf '%s\n' "$major"
}

llvm_optional_fallback_for() {
    local versioned_pkg="$1"
    case "$versioned_pkg" in
        lld-*) printf '%s\n' "lld" ;;
        lldb-*) printf '%s\n' "lldb" ;;
        libc++-*-dev) printf '%s\n' "libc++-dev" ;;
        libc++abi-*-dev) printf '%s\n' "libc++abi-dev" ;;
        *) return 1 ;;
    esac
}

install_llvm() {
    CURRENT_STEP="install llvm/clang"
    local required_packages=(
        "clang-${LLVM_VERSION}"
        "clangd-${LLVM_VERSION}"
        "clang-format-${LLVM_VERSION}"
        "clang-tidy-${LLVM_VERSION}"
        "clang-tools-${LLVM_VERSION}"
        "llvm-${LLVM_VERSION}"
        "llvm-${LLVM_VERSION}-dev"
    )

    local optional_packages=(
        "lld-${LLVM_VERSION}"
        "lldb-${LLVM_VERSION}"
        "libc++-${LLVM_VERSION}-dev"
        "libc++abi-${LLVM_VERSION}-dev"
    )

    local pkg fallback_pkg fallback_major
    local missing_required=()
    local missing_optional_exact=()
    local missing_optional_final=()
    local installable=()
    local min_fallback_major="$((LLVM_VERSION - 1))"

    for pkg in "${required_packages[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            installable+=("$pkg")
        else
            missing_required+=("$pkg")
        fi
    done

    if ((${#missing_required[@]} > 0)); then
        LLVM_INSTALL_SOURCE="apt.llvm.org"
        log "LLVM ${LLVM_VERSION} is incomplete in Ubuntu repositories"
        warn "Missing required LLVM packages in Ubuntu repos: ${missing_required[*]}"
        enable_apt_llvm_repo 1

        installable=()
        missing_required=()

        for pkg in "${required_packages[@]}"; do
            if apt-cache show "$pkg" >/dev/null 2>&1; then
                installable+=("$pkg")
            else
                missing_required+=("$pkg")
            fi
        done

        if ((${#missing_required[@]} > 0)); then
            die "Required LLVM packages are still unavailable after enabling apt.llvm.org: ${missing_required[*]}"
        fi
    else
        LLVM_INSTALL_SOURCE="ubuntu"
        log "Installing LLVM/Clang ${LLVM_VERSION} from Ubuntu repositories"
    fi

    missing_optional_exact=()
    for pkg in "${optional_packages[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
            installable+=("$pkg")
        else
            missing_optional_exact+=("$pkg")
        fi
    done

    if ((${#missing_optional_exact[@]} > 0)) && [[ "$APT_LLVM_REPO_ENABLED" == "0" ]]; then
        log "Trying apt.llvm.org for missing optional LLVM packages"
        if enable_apt_llvm_repo 0; then
            if [[ "$LLVM_INSTALL_SOURCE" == "ubuntu" ]]; then
                LLVM_INSTALL_SOURCE="ubuntu+apt.llvm.org(optional)"
            fi

            missing_optional_exact=()
            for pkg in "${optional_packages[@]}"; do
                if apt-cache show "$pkg" >/dev/null 2>&1; then
                    if [[ " ${installable[*]} " != *" $pkg "* ]]; then
                        installable+=("$pkg")
                    fi
                else
                    missing_optional_exact+=("$pkg")
                fi
            done
        fi
    fi

    LLVM_OPTIONAL_FALLBACK_USED=()
    LLVM_OPTIONAL_FALLBACK_REJECTED=()
    missing_optional_final=()

    for pkg in "${missing_optional_exact[@]}"; do
        if fallback_pkg="$(llvm_optional_fallback_for "$pkg")" && apt-cache show "$fallback_pkg" >/dev/null 2>&1; then
            fallback_major="$(apt_package_major "$fallback_pkg" || true)"
            if [[ -n "$fallback_major" ]] && ((fallback_major >= min_fallback_major)); then
                if [[ " ${installable[*]} " != *" $fallback_pkg "* ]]; then
                    installable+=("$fallback_pkg")
                fi
                LLVM_OPTIONAL_FALLBACK_USED+=("${pkg}->${fallback_pkg}@${fallback_major}")
            else
                if [[ -n "$fallback_major" ]]; then
                    LLVM_OPTIONAL_FALLBACK_REJECTED+=("${pkg}->${fallback_pkg}@${fallback_major}<${min_fallback_major}")
                else
                    LLVM_OPTIONAL_FALLBACK_REJECTED+=("${pkg}->${fallback_pkg}@unknown<${min_fallback_major}")
                fi
                missing_optional_final+=("$pkg")
            fi
        else
            missing_optional_final+=("$pkg")
        fi
    done

    if ((${#LLVM_OPTIONAL_FALLBACK_USED[@]} > 0)); then
        warn "Using fallback optional LLVM packages: ${LLVM_OPTIONAL_FALLBACK_USED[*]}"
    fi
    if ((${#LLVM_OPTIONAL_FALLBACK_REJECTED[@]} > 0)); then
        warn "Rejected optional LLVM fallbacks below minimum major ${min_fallback_major}: ${LLVM_OPTIONAL_FALLBACK_REJECTED[*]}"
    fi
    if ((${#missing_optional_final[@]} > 0)); then
        warn "Optional LLVM packages unavailable after exact+fallback resolution: ${missing_optional_final[*]}"
    fi

    LLVM_OPTIONAL_MISSING=("${missing_optional_final[@]}")

    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${installable[@]}"
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
    local configured=()
    local skipped=()
    for tool in "${tools[@]}"; do
        versioned="/usr/bin/${tool}-${LLVM_VERSION}"
        if [[ -x "$versioned" ]]; then
            sudo update-alternatives \
                --install "/usr/bin/${tool}" "$tool" "$versioned" "$((LLVM_VERSION * 10))"
            configured+=("$tool")
        else
            skipped+=("$tool")
        fi
    done

    ok "LLVM alternatives configured (${#configured[@]} tools)"
    if ((${#skipped[@]} > 0)); then
        warn "Skipped alternative registration (versioned tool missing): ${skipped[*]}"
    fi

    LLVM_ALTERNATIVES_CONFIGURED=("${configured[@]}")
    LLVM_ALTERNATIVES_SKIPPED=("${skipped[@]}")
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
        'winget install --id Microsoft.VisualStudioCode --exact --scope machine --disable-interactivity --accept-package-agreements --accept-source-agreements' \
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
    local extensions=()
    if [[ "$INSTALL_VSCODE_EXT_CLANGD" == "1" ]]; then
        extensions+=("llvm-vs-code-extensions.vscode-clangd")
    fi
    if [[ "$INSTALL_VSCODE_EXT_CMAKE_TOOLS" == "1" ]]; then
        extensions+=("ms-vscode.cmake-tools")
    fi
    if [[ "$INSTALL_VSCODE_EXT_CMAKE_SYNTAX" == "1" ]]; then
        extensions+=("twxs.cmake")
    fi

    if ((${#extensions[@]} == 0)); then
        log "No VS Code extensions selected"
        return 0
    fi

    local extension
    for extension in "${extensions[@]}"; do
        if ! "$code_cmd" --install-extension "$extension" --force \
            2> >(grep -Ev 'DEP0169|url\.parse\(\)|trace-deprecation|CVEs are not issued' >&2 || true); then
            warn "Could not install VS Code extension: $extension"
        fi
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
        local output
        local status=0
        if output="$(bash -lc "$item" 2>&1)"; then
            status=0
        else
            status=$?
        fi

        if [[ "$status" -eq 0 ]]; then
            if [[ -n "$output" ]]; then
                printf '%s\n' "$output" | head -n 3
            else
                printf '(no output)\n'
            fi
        else
            if [[ -n "$output" ]]; then
                printf 'non-zero exit (%s)\n' "$status"
            else
                printf 'unavailable\n'
            fi
            if [[ -n "$output" ]]; then
                printf '%s\n' "$output" | head -n 2
            fi
        fi
    done

    local missing_optional_text="none"
    local fallback_optional_text="none"
    local rejected_fallback_text="none"
    local skipped_alt_text="none"
    if ((${#LLVM_OPTIONAL_MISSING[@]} > 0)); then
        missing_optional_text="${LLVM_OPTIONAL_MISSING[*]}"
    fi
    if ((${#LLVM_OPTIONAL_FALLBACK_USED[@]} > 0)); then
        fallback_optional_text="${LLVM_OPTIONAL_FALLBACK_USED[*]}"
    fi
    if ((${#LLVM_OPTIONAL_FALLBACK_REJECTED[@]} > 0)); then
        rejected_fallback_text="${LLVM_OPTIONAL_FALLBACK_REJECTED[*]}"
    fi
    if ((${#LLVM_ALTERNATIVES_SKIPPED[@]} > 0)); then
        skipped_alt_text="${LLVM_ALTERNATIVES_SKIPPED[*]}"
    fi
    printf '\nToolchain summary: optional LLVM fallback-used [%s]; fallback-rejected [%s]; optional missing [%s]; alternatives configured=%d skipped=%d (%s)\n' \
        "$fallback_optional_text" \
        "$rejected_fallback_text" \
        "$missing_optional_text" \
        "${#LLVM_ALTERNATIVES_CONFIGURED[@]}" \
        "${#LLVM_ALTERNATIVES_SKIPPED[@]}" \
        "$skipped_alt_text"

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

    if [[ "$INSTALL_COPILOT_TOOLS" == "1" ]] && command_exists direnv; then
        cat <<'EOF'

Copilot tools note:
  - To enable direnv in bash, add this to ~/.bashrc:
      eval "$(direnv hook bash)"
  - For zsh, add this to ~/.zshrc:
      eval "$(direnv hook zsh)"
EOF
    fi
}

show_warnings_recap() {
    CURRENT_STEP="show warnings recap"
    if ((${#WARNINGS[@]} == 0)); then
        return 0
    fi

    log "Warnings recap"
    local index=1
    local warning
    for warning in "${WARNINGS[@]}"; do
        printf '  %d) %s\n' "$index" "$warning"
        ((index++))
    done
}

main() {
    show_startup_banner
    validate_configuration
    require_ubuntu
    configure_optional_choices
    show_startup_summary
    confirm_startup_if_interactive

    if [[ "$CHECK_ONLY" == "1" ]]; then
        show_check_only_plan
        return 0
    fi

    update_apt_metadata_and_resolve_llvm
    show_resolved_llvm_summary
    install_base_packages
    install_optional_packages
    install_tool_profile_bundles
    install_copilot_tools
    install_python_314
    install_llvm
    install_iwyu_if_selected
    configure_llvm_alternatives
    install_windows_vscode
    install_vscode_extensions
    generate_vscode_workspace_defaults
    configure_git_and_ccache
    cleanup
    show_versions
    show_warnings_recap
}

main "$@"
