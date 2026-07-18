#!/usr/bin/env bash
set -Eeuo pipefail

# Switch between LLVM stable and nightly channels on Ubuntu WSL.
#
# Usage:
#   ./switch-llvm-channel.sh
#
# Optional environment variables:
#   TARGET_CHANNEL=stable ./switch-llvm-channel.sh
#   TARGET_CHANNEL=nightly ./switch-llvm-channel.sh
#   CHECK_ONLY=1 ./switch-llvm-channel.sh

TARGET_CHANNEL="${TARGET_CHANNEL:-}"
CHECK_ONLY="${CHECK_ONLY:-0}"
MAX_SUPPORTED_LLVM_MAJOR=999

CURRENT_STEP="startup"
VERSION_CODENAME=""
APT_LLVM_PAGE=""
APT_LLVM_SCRIPT=""
LLVM_STABLE_MAJOR=""
LLVM_NIGHTLY_MAJOR=""
CURRENT_CLANG_PATH=""
CURRENT_MAJOR=""
CURRENT_CHANNEL="unknown"
TARGET_MAJOR=""
TARGET_ACTION=""
WARNINGS=()

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

validate_channel() {
    local name="$1"
    local value="$2"
    [[ -z "$value" || "$value" == "stable" || "$value" == "nightly" ]] || die "${name} must be 'stable', 'nightly', or unset."
}

ask_channel() {
    local default_channel="$1"
    local answer

    while true; do
        if ! read -r -p "Choose LLVM channel [stable/nightly] (default: ${default_channel}): " answer; then
            answer="$default_channel"
        fi

        answer="${answer:-$default_channel}"
        case "${answer,,}" in
            stable|nightly)
                printf '%s\n' "${answer,,}"
                return 0
                ;;
            *)
                warn "Please answer 'stable' or 'nightly'."
                ;;
        esac
    done
}

require_ubuntu() {
    CURRENT_STEP="detect ubuntu release"
    [[ -r /etc/os-release ]] || die "/etc/os-release was not found."
    # shellcheck disable=SC1091
    . /etc/os-release
    [[ "${ID:-}" == "ubuntu" ]] || die "This script supports Ubuntu; detected ${ID:-unknown}."
    [[ -n "${VERSION_ID:-}" ]] || die "Could not determine Ubuntu VERSION_ID from /etc/os-release."
    VERSION_CODENAME="${VERSION_CODENAME:-}"
    [[ -n "$VERSION_CODENAME" ]] || die "Could not determine Ubuntu VERSION_CODENAME from /etc/os-release."
    log "Detected Ubuntu ${VERSION_ID:-unknown} (${VERSION_CODENAME})"
    if ! is_wsl; then
        warn "WSL was not detected. Continuing because the LLVM channel workflow is otherwise the same on Ubuntu."
    fi
}

validate_configuration() {
    CURRENT_STEP="validate configuration"
    validate_bool "CHECK_ONLY" "$CHECK_ONLY"
    TARGET_CHANNEL="${TARGET_CHANNEL,,}"
    validate_channel "TARGET_CHANNEL" "$TARGET_CHANNEL"
    command_exists curl || die "curl is required."
    command_exists gpg || die "gpg is required."
    command_exists sudo || die "sudo is required."
    command_exists apt-get || die "apt-get is required."
    command_exists apt-cache || die "apt-cache is required."
    command_exists dpkg-query || die "dpkg-query is required."
    command_exists update-alternatives || die "update-alternatives is required."
}

fetch_apt_llvm_page() {
    CURRENT_STEP="fetch apt.llvm.org channel metadata"
    log "Fetching apt.llvm.org channel metadata"
    APT_LLVM_PAGE="$({
        curl --fail --location --silent --show-error \
            --proto '=https' --tlsv1.2 \
            --retry 3 --retry-connrefused \
            https://apt.llvm.org/
    })"
}

fetch_apt_llvm_script() {
    CURRENT_STEP="fetch apt.llvm.org install script"
    log "Fetching apt.llvm.org install script"
    APT_LLVM_SCRIPT="$({
        curl --fail --location --silent --show-error \
            --proto '=https' --tlsv1.2 \
            --retry 3 --retry-connrefused \
            https://apt.llvm.org/llvm.sh
    })"
}

resolve_channel_versions() {
    CURRENT_STEP="resolve stable and nightly llvm majors"

    LLVM_NIGHTLY_MAJOR="$({
        printf '%s\n' "$APT_LLVM_PAGE" \
            | sed -En 's/.*currently version ([0-9]+).*/\1/p' \
            | head -n 1
    })"

    if [[ -z "$LLVM_NIGHTLY_MAJOR" ]]; then
        # Fallback for the apt.llvm.org overview sentence that lists
        # stable, qualification, and development majors inline.
        LLVM_NIGHTLY_MAJOR="$({
            printf '%s\n' "$APT_LLVM_PAGE" \
                | sed -En 's/.*currently ([0-9]+), ([0-9]+) and ([0-9]+).*/\1\n\2\n\3/p' \
                | sort -nr \
                | head -n 1
        })"
    fi

    [[ -n "$LLVM_NIGHTLY_MAJOR" ]] || die "Could not determine the apt.llvm.org nightly LLVM major."

    LLVM_STABLE_MAJOR="$({
        printf '%s\n' "$APT_LLVM_SCRIPT" \
            | sed -n 's/^CURRENT_LLVM_STABLE=\([0-9][0-9]*\)$/\1/p' \
            | head -n 1
    })"

    [[ -n "$LLVM_STABLE_MAJOR" ]] || die "Could not determine the latest stable LLVM major from apt.llvm.org/llvm.sh."
    log "Resolved channel majors: stable=${LLVM_STABLE_MAJOR}, nightly=${LLVM_NIGHTLY_MAJOR}"
}

ensure_apt_llvm_keyring() {
    CURRENT_STEP="install apt.llvm.org keyring"
    local keyring_path="/usr/share/keyrings/llvm-snapshot.gpg"
    local tmp_keyring

    tmp_keyring="$(mktemp)"
    curl --fail --location --silent --show-error \
        --proto '=https' --tlsv1.2 \
        --retry 3 --retry-connrefused \
        https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor > "$tmp_keyring"
    sudo install -o root -g root -m 0644 "$tmp_keyring" "$keyring_path"
    rm -f "$tmp_keyring"
}

write_repo_file() {
    local path="$1"
    local component="$2"
    printf 'deb [signed-by=%s] https://apt.llvm.org/%s/ %s main\n' \
        "/usr/share/keyrings/llvm-snapshot.gpg" "$VERSION_CODENAME" "$component" \
        | sudo tee "$path" >/dev/null
}

ensure_channel_repositories() {
    CURRENT_STEP="ensure stable and nightly apt repositories"
    log "Configuring apt.llvm.org stable and nightly repositories"
    ensure_apt_llvm_keyring
    write_repo_file "/etc/apt/sources.list.d/llvm-stable-current.list" "llvm-toolchain-${VERSION_CODENAME}-${LLVM_STABLE_MAJOR}"
    write_repo_file "/etc/apt/sources.list.d/llvm-nightly-current.list" "llvm-toolchain-${VERSION_CODENAME}"
}

refresh_apt_metadata() {
    CURRENT_STEP="refresh apt metadata"
    log "Refreshing apt package metadata"
    sudo apt-get update
}

package_has_candidate() {
    local package="$1"
    local candidate_version
    candidate_version="$(package_candidate_version "$package")"
    [[ -n "$candidate_version" && "$candidate_version" != "(none)" ]]
}

verify_channel_packages_available() {
    local channel="$1"
    local major="$2"
    local missing=()
    local package

    while IFS= read -r package; do
        if ! package_has_candidate "$package"; then
            missing+=("$package")
        fi
    done < <(required_packages_for_major "$major")

    if ((${#missing[@]} > 0)); then
        die "Required packages for the ${channel} channel (LLVM ${major}) are unavailable after refreshing apt metadata: ${missing[*]}"
    fi
}

resolve_current_setup() {
    CURRENT_STEP="detect current llvm setup"
    local clang_command=""

    if command_exists clang; then
        clang_command="$(command -v clang 2>/dev/null || true)"
        if [[ -n "$clang_command" ]]; then
            CURRENT_CLANG_PATH="$(readlink -f "$clang_command" 2>/dev/null || true)"
        else
            CURRENT_CLANG_PATH=""
        fi
    else
        CURRENT_CLANG_PATH=""
    fi

    CURRENT_MAJOR="$({
        printf '%s\n' "$CURRENT_CLANG_PATH" \
            | sed -En 's#.*/clang-([0-9]+)$#\1#p'
    })"

    if [[ -n "$CURRENT_MAJOR" ]]; then
        if [[ "$CURRENT_MAJOR" == "$LLVM_NIGHTLY_MAJOR" ]]; then
            CURRENT_CHANNEL="nightly"
        elif [[ "$CURRENT_MAJOR" == "$LLVM_STABLE_MAJOR" ]]; then
            CURRENT_CHANNEL="stable"
        else
            CURRENT_CHANNEL="custom"
        fi
    fi
}

required_packages_for_major() {
    local major="$1"
    printf '%s\n' \
        "clang-${major}" \
        "clangd-${major}" \
        "clang-format-${major}" \
        "clang-tidy-${major}" \
        "clang-tools-${major}" \
        "llvm-${major}" \
        "llvm-${major}-dev"
}

optional_packages_for_major() {
    local major="$1"
    printf '%s\n' \
        "lld-${major}" \
        "lldb-${major}" \
        "libc++-${major}-dev" \
        "libc++abi-${major}-dev"
}

package_installed_version() {
    local package="$1"
    dpkg-query -W -f='${Version}' "$package" 2>/dev/null || true
}

package_candidate_version() {
    local package="$1"
    apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/{print $2; exit}'
}

channel_status_counts() {
    local major="$1"
    local package
    local installed_version
    local candidate_version
    local installed_count=0
    local missing_count=0
    local update_count=0

    while IFS= read -r package; do
        installed_version="$(package_installed_version "$package")"
        candidate_version="$(package_candidate_version "$package")"

        if [[ -n "$installed_version" ]]; then
            ((installed_count += 1))
            if [[ -n "$candidate_version" && "$candidate_version" != "(none)" && "$candidate_version" != "$installed_version" ]]; then
                ((update_count += 1))
            fi
        else
            ((missing_count += 1))
        fi
    done < <(required_packages_for_major "$major")

    printf '%s %s %s\n' "$installed_count" "$missing_count" "$update_count"
}

channel_status_label() {
    local major="$1"
    local installed_count missing_count update_count

    read -r installed_count missing_count update_count < <(channel_status_counts "$major")

    if ((missing_count == 0 && update_count == 0)); then
        printf 'installed and up to date'
    elif ((missing_count == 0 && update_count > 0)); then
        printf 'installed with updates available'
    elif ((installed_count > 0 && update_count > 0)); then
        printf 'partially installed with updates available'
    elif ((installed_count > 0)); then
        printf 'partially installed'
    else
        printf 'not installed'
    fi
}

show_channel_summary() {
    CURRENT_STEP="show llvm channel summary"
    local stable_status nightly_status

    stable_status="$(channel_status_label "$LLVM_STABLE_MAJOR")"
    nightly_status="$(channel_status_label "$LLVM_NIGHTLY_MAJOR")"

    cat <<EOF_SUMMARY

LLVM channel summary
  - Current clang path: ${CURRENT_CLANG_PATH:-not configured}
  - Current LLVM major: ${CURRENT_MAJOR:-not detected}
  - Current channel:    ${CURRENT_CHANNEL}
  - Stable channel:     LLVM ${LLVM_STABLE_MAJOR} (${stable_status})
  - Nightly channel:    LLVM ${LLVM_NIGHTLY_MAJOR} (${nightly_status})

EOF_SUMMARY
}

choose_target_channel() {
    CURRENT_STEP="choose target channel"

    if [[ -n "$TARGET_CHANNEL" ]]; then
        return 0
    fi

    if ! is_interactive_terminal; then
        die "TARGET_CHANNEL must be set to 'stable' or 'nightly' when no interactive terminal is available."
    fi

    case "$CURRENT_CHANNEL" in
        stable|nightly)
            TARGET_CHANNEL="$(ask_channel "$CURRENT_CHANNEL")"
            ;;
        *)
            TARGET_CHANNEL="$(ask_channel stable)"
            ;;
    esac
}

choose_target_major() {
    CURRENT_STEP="resolve target major"

    case "$TARGET_CHANNEL" in
        stable) TARGET_MAJOR="$LLVM_STABLE_MAJOR" ;;
        nightly) TARGET_MAJOR="$LLVM_NIGHTLY_MAJOR" ;;
        *) die "Unsupported target channel: ${TARGET_CHANNEL}" ;;
    esac
}

optional_package_candidates_for_major() {
    local major="$1"
    local package
    while IFS= read -r package; do
        if package_has_candidate "$package"; then
            printf '%s\n' "$package"
        else
            warn "Optional LLVM package is unavailable for LLVM ${major}: ${package}"
        fi
    done < <(optional_packages_for_major "$major")
}

resolve_target_action() {
    CURRENT_STEP="resolve target action"
    local installed_count missing_count update_count

    read -r installed_count missing_count update_count < <(channel_status_counts "$TARGET_MAJOR")

    if [[ "$CURRENT_MAJOR" == "$TARGET_MAJOR" ]]; then
        if ((update_count > 0)); then
            TARGET_ACTION="update current ${TARGET_CHANNEL} channel"
        else
            TARGET_ACTION="keep current ${TARGET_CHANNEL} channel"
        fi
    elif ((missing_count == 0)); then
        TARGET_ACTION="switch to ${TARGET_CHANNEL} channel"
    else
        TARGET_ACTION="install and switch to ${TARGET_CHANNEL} channel"
    fi

    printf 'Planned action: %s (LLVM %s)\n' "$TARGET_ACTION" "$TARGET_MAJOR"
}

install_target_packages() {
    CURRENT_STEP="install target llvm packages"
    local packages=()
    local package

    while IFS= read -r package; do
        packages+=("$package")
    done < <(required_packages_for_major "$TARGET_MAJOR")

    while IFS= read -r package; do
        packages+=("$package")
    done < <(optional_package_candidates_for_major "$TARGET_MAJOR")

    log "Installing/updating LLVM ${TARGET_MAJOR} packages for channel '${TARGET_CHANNEL}'"
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
}

configure_llvm_alternatives() {
    CURRENT_STEP="configure llvm alternatives"
    log "Registering LLVM ${TARGET_MAJOR} as the default toolchain"
    [[ "$TARGET_MAJOR" =~ ^[0-9]+$ ]] || die "TARGET_MAJOR must be numeric before configuring update-alternatives."
    ((TARGET_MAJOR <= MAX_SUPPORTED_LLVM_MAJOR)) || die "TARGET_MAJOR is unexpectedly large for update-alternatives priority calculation: ${TARGET_MAJOR}"

    # Some entries below come from optional packages, so versioned binaries may
    # legitimately be absent on a given channel or Ubuntu release.
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
    local tool
    local versioned

    for tool in "${tools[@]}"; do
        versioned="/usr/bin/${tool}-${TARGET_MAJOR}"
        if [[ -x "$versioned" ]]; then
            # Keep priorities monotonic by major version so newer LLVM releases
            # naturally win automatic selection when multiple versions exist.
            sudo update-alternatives --install "/usr/bin/${tool}" "$tool" "$versioned" "$((TARGET_MAJOR * 10))"
            sudo update-alternatives --set "$tool" "$versioned"
        fi
    done

    ok "LLVM ${TARGET_MAJOR} is now the default toolchain"
}

show_completion_summary() {
    CURRENT_STEP="show completion summary"
    local stable_status nightly_status

    resolve_current_setup
    stable_status="$(channel_status_label "$LLVM_STABLE_MAJOR")"
    nightly_status="$(channel_status_label "$LLVM_NIGHTLY_MAJOR")"

    cat <<EOF_DONE

Completed LLVM channel action
  - Selected channel:  ${TARGET_CHANNEL}
  - Default clang path: ${CURRENT_CLANG_PATH:-not configured}
  - Default LLVM major: ${CURRENT_MAJOR:-not detected}
  - Stable channel:     LLVM ${LLVM_STABLE_MAJOR} (${stable_status})
  - Nightly channel:    LLVM ${LLVM_NIGHTLY_MAJOR} (${nightly_status})

Verify with:
  clang --version
  clangd --version
  clang-tidy --version
EOF_DONE
}

show_warnings_recap() {
    CURRENT_STEP="show warnings recap"
    if ((${#WARNINGS[@]} == 0)); then
        return 0
    fi

    log "Warnings recap"
    local warning
    for warning in "${WARNINGS[@]}"; do
        printf '  - %s\n' "$warning"
    done
}

main() {
    validate_configuration
    require_ubuntu
    fetch_apt_llvm_page
    fetch_apt_llvm_script
    resolve_channel_versions
    ensure_channel_repositories
    refresh_apt_metadata
    verify_channel_packages_available "stable" "$LLVM_STABLE_MAJOR"
    verify_channel_packages_available "nightly" "$LLVM_NIGHTLY_MAJOR"
    resolve_current_setup
    show_channel_summary
    choose_target_channel
    choose_target_major
    resolve_target_action

    if [[ "$CHECK_ONLY" == "1" ]]; then
        log "CHECK_ONLY=1 set; exiting before package installation or alternative changes"
        show_warnings_recap
        return 0
    fi

    install_target_packages
    configure_llvm_alternatives
    show_completion_summary
    show_warnings_recap
}

main "$@"
