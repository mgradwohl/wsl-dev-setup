# WSL C++ Dev Setup (Clang-first)

Bootstrap a modern **C++ in WSL** environment with a **clang/clangd-first** workflow for **VS Code**.

## What this gives you

- Ubuntu WSL bootstrap (24.04+)
- LLVM/Clang toolchain with default policy: **latest available major >= 23**
- Predictable fallback to `apt.llvm.org` when Ubuntu repos do not provide the selected LLVM major
- `update-alternatives` registration so `clang`, `clang++`, `clangd`, `clang-tidy`, etc. resolve to the selected LLVM major
- VS Code setup flow for WSL (optional Windows install + optional extension install)
- Interactive optional-tool selection at startup
- Optional generation of `.vscode/settings.json` + `.vscode/extensions.json`
- Safe reruns (idempotent design)

> No Microsoft C/C++ language server by default. This setup is **all clang, all the time**.

---

## Requirements

- Windows 11
- WSL2
- Ubuntu 24.04+ in WSL

---

## Quick start

```bash
git clone https://github.com/<your-account>/wsl-dev-setup.git
cd wsl-dev-setup
chmod +x bootstrap-wsl-dev.sh
./bootstrap-wsl-dev.sh
```

The script will ask which optional tool groups you want.

---

## Non-interactive usage

Use env vars to skip prompts and force choices:

```bash
INSTALL_OPTIONAL_TOOLS_PROMPT=0 \
INSTALL_GIT_LFS=1 \
INSTALL_DOCS_TOOLS=0 \
INSTALL_IWYU=1 \
INSTALL_PROFILING_TOOLS=0 \
GENERATE_VSCODE_SETTINGS=1 \
./bootstrap-wsl-dev.sh
```

---

## Configuration

| Variable | Default | Meaning |
|---|---|---|
| `LLVM_VERSION` | `latest` | `latest` = highest available LLVM major `>=23`; numeric values must be `>=23` |
| `INSTALL_WINDOWS_VSCODE` | `1` | Install Windows VS Code through winget when in WSL |
| `INSTALL_VSCODE_EXTENSIONS` | `1` | Install recommended clangd/CMake extensions |
| `INSTALL_OPTIONAL_TOOLS_PROMPT` | `1` | Ask for optional tool groups at startup (interactive terminals) |
| `INSTALL_GIT_LFS` | unset | Force Git LFS install (`1`/`0`) |
| `INSTALL_DOCS_TOOLS` | unset | Force Doxygen + Graphviz install (`1`/`0`) |
| `INSTALL_IWYU` | unset | Force Include-What-You-Use install (`1`/`0`) |
| `INSTALL_PROFILING_TOOLS` | unset | Force Valgrind + Heaptrack + gperftools install (`1`/`0`) |
| `GENERATE_VSCODE_SETTINGS` | unset | Force generation of `.vscode` defaults (`1`/`0`) |

---

## Should you generate `.vscode` defaults?

If you are unsure, choose **No** first.

Choose **Yes** when:
- you are starting a new repo
- you want a ready-to-go clangd + CMake + Ninja baseline
- you do not already have custom workspace settings

Choose **No** when:
- your project already has `.vscode/settings.json` and/or `.vscode/extensions.json`
- you want to keep editor config fully manual

The script never overwrites existing `.vscode` files.

---

## After install

Verify:

```bash
clang --version
clangd --version
clang-tidy --version
cmake --version
ninja --version
python3 --version
```

Open the current directory in VS Code (from WSL):

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

Build + test:

```bash
cmake --build build --parallel
ctest --test-dir build --output-on-failure
```

---

## Best practices for WSL C++

- Keep projects under Linux paths (`~/src/...`), not `/mnt/c/...`, for performance.
- Use `clangd` as the language server.
- Keep `compile_commands.json` enabled for reliable clangd indexing.

---

## Troubleshooting

### `code` command not found

From Windows PowerShell:

```powershell
wsl --shutdown
```

Then reopen Ubuntu and rerun bootstrap if needed.

### LLVM package issues

Rerun bootstrap. It re-checks package availability and uses `apt.llvm.org` when needed.

### `winget` unavailable

Install VS Code manually on Windows, then rerun with:

```bash
INSTALL_WINDOWS_VSCODE=0 ./bootstrap-wsl-dev.sh
```

---

## What changed recently

- LLVM default policy moved from fixed `22` to `latest >=23`
- `apt-get full-upgrade` path removed
- Added startup config validation and better failure diagnostics
- Added interactive optional-tool selection
- Kept VS Code extensions clangd/CMake-focused

---

## Updating

```bash
git pull
./bootstrap-wsl-dev.sh
```

---

## License

Use, modify, and distribute as desired.
