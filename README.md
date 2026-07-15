# WSL C++ Development Bootstrap

A reproducible bootstrap for a modern **C++23+** development environment on **Ubuntu WSL** with **VS Code**, **Clang/LLVM**, **CMake**, and **Ninja**.

## Features

- Ubuntu WSL-focused bootstrap (24.04+)
- LLVM/Clang setup with **default LLVM 23**
- LLVM package source fallback:
  - Ubuntu repositories when available
  - `apt.llvm.org` when needed
- Registers LLVM tools with `update-alternatives` so unversioned commands use the selected LLVM major
- Installs core development tools:
  - build-essential, CMake, Ninja, ccache, Git, GDB
  - Python 3 + venv + pip (plus Python 3.14 when available in distro repos)
  - curl/wget, jq, zip/unzip, pkg-config
- Optional Windows VS Code install (from WSL via PowerShell + winget)
- Optional VS Code extension installation
- Optional generation of `.vscode/settings.json` and `.vscode/extensions.json` for clangd-first C++ workflows
- Idempotent and safe to rerun

---

## Requirements

- Windows 11
- WSL2
- Ubuntu 24.04 or newer in WSL

---

## Installation

```bash
git clone https://github.com/<your-account>/wsl-dev-setup.git
cd wsl-dev-setup
chmod +x bootstrap-wsl-dev.sh
./bootstrap-wsl-dev.sh
```

---

## What changed (latest)

- Default LLVM moved from **22** to **23**
- Added explicit configuration validation (for example `LLVM_VERSION` must be integer `>=23`)
- `apt-get full-upgrade` is now **opt-in** (`FULL_UPGRADE=1`)
- Added clearer startup summary and failure diagnostics
- Hardened Windows VS Code detection/install checks for WSL
- Added optional `.vscode` workspace defaults generation (`GENERATE_VSCODE_SETTINGS=1`)

---

## Environment variables

| Variable | Default | Description |
|---|---|---|
| `LLVM_VERSION` | `23` | LLVM major version to install (`>=23`) |
| `FULL_UPGRADE` | `0` | `1` enables `apt-get full-upgrade`; `0` uses safer `apt-get upgrade` |
| `INSTALL_WINDOWS_VSCODE` | `1` | Install Windows VS Code via winget when running under WSL |
| `INSTALL_VSCODE_EXTENSIONS` | `1` | Install recommended VS Code extensions |
| `GENERATE_VSCODE_SETTINGS` | `0` | Generate `.vscode` workspace defaults in current directory |

Examples:

```bash
LLVM_VERSION=24 ./bootstrap-wsl-dev.sh
FULL_UPGRADE=1 ./bootstrap-wsl-dev.sh
GENERATE_VSCODE_SETTINGS=1 ./bootstrap-wsl-dev.sh
```

---

## After installation

Verify toolchain:

```bash
clang --version
clangd --version
clang-tidy --version
cmake --version
ninja --version
python3 --version
```

Open project in VS Code from WSL:

```bash
code .
```

Recommended CMake configure:

```bash
cmake -S . -B build \
  -G Ninja \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

Build and test:

```bash
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

---

## WSL + VS Code guidance

- Keep active source code under Linux paths (for example `~/src`) instead of `/mnt/c` for better IO performance.
- Use the clangd extension as the primary C++ language server.
- Prefer Ninja + `compile_commands.json` for fast CMake + clangd iteration.

---

## Troubleshooting

### `code` not found after installation

From Windows PowerShell:

```powershell
wsl --shutdown
```

Then reopen Ubuntu and rerun the bootstrap if needed.

### LLVM package resolution issues

Rerun the script. It re-checks package availability and falls back to `apt.llvm.org` when required.

### `winget` unavailable

Install VS Code manually on Windows and rerun the script with:

```bash
INSTALL_WINDOWS_VSCODE=0 ./bootstrap-wsl-dev.sh
```

---

## Updating

```bash
git pull
./bootstrap-wsl-dev.sh
```

The script is designed to be safely re-run.

---

## License

Use, modify, and distribute as desired.
