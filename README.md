# WSL C++ Dev Setup (Clang-first)

Bootstrap a modern **C++ in WSL** environment with a **clang/clangd-first** workflow for **VS Code**.

## What this gives you

- Ubuntu WSL bootstrap (24.04+)
- LLVM/Clang toolchain with default policy: **latest available major >= 23** from configured APT repos; falls back to `apt.llvm.org` when the selected version is not in Ubuntu repos
- `update-alternatives` registration so `clang`, `clang++`, `clangd`, `clang-tidy`, etc. resolve to the selected LLVM major
- VS Code setup flow for WSL (optional Windows install + optional extension install)
- Interactive optional-tool selection at startup (all prompts are collected before package installs begin)
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
git clone https://github.com/mgradwohl/wsl-dev-setup.git
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
CHECK_ONLY=1 \
INSTALL_GIT_LFS=1 \
INSTALL_GITHUB_CLI=1 \
INSTALL_COPILOT_TOOLS=1 \
INSTALL_DOCS_TOOLS=0 \
INSTALL_IWYU=1 \
INSTALL_PROFILING_TOOLS=0 \
INSTALL_PROFILE_PERFORMANCE=1 \
INSTALL_PROFILE_RELIABILITY=1 \
INSTALL_PROFILE_TESTING=1 \
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
| `INSTALL_VSCODE_EXT_CLANGD` | unset | Install `llvm-vs-code-extensions.vscode-clangd` (`1`/`0`); defaults to `1` when `INSTALL_VSCODE_EXTENSIONS=1` |
| `INSTALL_VSCODE_EXT_CMAKE_TOOLS` | unset | Install `ms-vscode.cmake-tools` (`1`/`0`); defaults to `1` when `INSTALL_VSCODE_EXTENSIONS=1` |
| `INSTALL_VSCODE_EXT_CMAKE_SYNTAX` | unset | Install `twxs.cmake` (`1`/`0`); defaults to `1` when `INSTALL_VSCODE_EXTENSIONS=1` |
| `INSTALL_OPTIONAL_TOOLS_PROMPT` | `1` | Ask for optional tool groups at startup (interactive terminals) |
| `CHECK_ONLY` | `0` | Print a complete installation plan and exit without making install/config changes (`1`/`0`) |
| `INSTALL_GIT_LFS` | unset | Force Git LFS install (`1`/`0`) |
| `INSTALL_GITHUB_CLI` | unset | Force GitHub CLI (`gh`) install (`1`/`0`) |
| `INSTALL_COPILOT_TOOLS` | unset | Force install of the common Copilot tools bundle (`1`/`0`) |
| `INSTALL_DOCS_TOOLS` | unset | Force Doxygen + Graphviz install (`1`/`0`) |
| `INSTALL_IWYU` | unset | Force Include-What-You-Use install (`1`/`0`) |
| `INSTALL_PROFILING_TOOLS` | unset | Force Valgrind + Heaptrack + gperftools install (`1`/`0`) |
| `INSTALL_PROFILE_PERFORMANCE` | unset | Force install of performance bundle (`1`/`0`) |
| `INSTALL_PROFILE_RELIABILITY` | unset | Force install of reliability bundle (`1`/`0`) |
| `INSTALL_PROFILE_TESTING` | unset | Force install of testing bundle (`1`/`0`) |
| `INSTALL_PROFILE_PRODUCTIVITY` | unset | Force install of productivity CLI bundle (`1`/`0`) |
| `GENERATE_VSCODE_SETTINGS` | unset | Force generation of `.vscode` defaults (`1`/`0`) |

When `INSTALL_IWYU=1`, the script now tries the best available package candidate for your selected LLVM major (`include-what-you-use-<major>`, then `include-what-you-use`, then `iwyu`). If none are available on your release, it logs a clear warning and continues.

Tool profile bundles:
- Performance: `mold`, `hyperfine`, `hotspot`, and perf helpers when available.
- Reliability: `cppcheck`, `bear`, and ELF/debug diagnostics helpers when available.
- Testing: `lcov`, `gcovr`, `catch2`, and `libgtest-dev` when available.
- Productivity: `ripgrep`, `fd-find`, `bat`, `fzf`, `yq`, `tree`, `shellcheck`, `shfmt`, `htop`, `btop`, `ncdu`, and `tmux` when available.
- Common Copilot tools: `git-delta`, `universal-ctags`, `entr`, `cloc`, `sqlite3`, `direnv`, `pipx`, `zsh`, and `bash-completion` when available; also tries to install `gh-copilot` when `gh` is installed.

Check-only mode (`CHECK_ONLY=1`) prints a full action plan and exits before installs or configuration changes.

When `INSTALL_OPTIONAL_TOOLS_PROMPT=1` in an interactive terminal and `INSTALL_VSCODE_EXTENSIONS=1`, the script asks at startup whether to install each recommended VS Code extension individually.

Runtime output behavior:
- After apt metadata refresh, the script prints a compact "Resolved LLVM selection" line instead of reprinting the full startup summary.
- Optional LLVM package availability warnings are grouped to reduce output noise.
- Optional LLVM package resolution now uses a tiered strategy: exact version in current repos, then exact version via `apt.llvm.org`, then unversioned fallback packages only when their detected major is at least `(requested_major - 1)`.
- A final "Warnings recap" is printed at the end when non-fatal warnings occurred.
- Tool version checks now distinguish non-zero exits from unavailable commands.
- A one-line toolchain summary is printed near the end (optional fallback used/rejected/missing + alternatives configured/skipped).

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

## Optional CLI utilities worth installing

Yes, installing core terminal utilities is a good idea for daily dev workflows.

Suggested list:
- `ripgrep` (`rg`) for fast code search.
- `fd-find` (`fdfind`) for fast file discovery.
- `bat` for syntax-highlighted file viewing.
- `fzf` for fuzzy history/file selection.
- `jq` and `yq` for JSON/YAML manipulation.
- `tree` for quick directory visualization.
- `shellcheck` and `shfmt` for shell script quality.
- `htop` and `btop` for process/resource inspection.
- `ncdu` for fast disk-usage analysis.
- `tmux` for persistent terminal sessions.

Use `INSTALL_PROFILE_PRODUCTIVITY=1` (or answer Yes at startup) to install this set as part of bootstrap.

---

## Common Copilot tools bundle

Use `INSTALL_COPILOT_TOOLS=1` (or answer Yes at startup) to install a bundle of local tools that are commonly useful when working with Copilot in WSL:

- `git-delta` for readable Git diffs in the terminal
- `universal-ctags` for symbol indexing helpers
- `entr` for file-watching rebuild/test loops
- `cloc` for quick language and size breakdowns
- `sqlite3` for local database inspection
- `direnv` for per-project shell environment loading
- `pipx` for isolated Python CLI tool installs
- `zsh` and `bash-completion` for improved shell/completion support

If `gh` is installed and authenticated, the bootstrap also attempts to install the official `gh-copilot` extension.

Post-install behavior:
- configures `git-delta` as the default Git pager
- prints a reminder for enabling `direnv` in `~/.bashrc` or `~/.zshrc`

This bundle intentionally avoids curl-pipe-to-shell installers. Tools such as `uv`, `ast-grep`, or a Node.js toolchain are left out unless they can be added later with a clearer packaging and trust story.

---

## Troubleshooting

### `code` command not found

From Windows PowerShell:

```powershell
wsl --shutdown
```

Then reopen Ubuntu and rerun bootstrap if needed.

### LLVM package issues

Rerun bootstrap. It validates the full required LLVM package set for the selected major and falls back to `apt.llvm.org` when Ubuntu repositories are incomplete for that major.

For optional LLVM packages (`lld`, `lldb`, `libc++`, `libc++abi`):
- the script first tries exact versioned names (for example `lld-23`),
- then tries exact versioned names after enabling `apt.llvm.org`,
- then tries unversioned fallbacks only if the package major is recent enough (at least requested major minus one).

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
- Added per-extension runtime prompts for VS Code extension installation
- Added productivity profile bundle for common CLI developer utilities
- Added compact resolved-LLVM summary after metadata refresh
- Grouped optional LLVM warnings and added end-of-run warnings recap
- Improved version reporting to show non-zero exits vs unavailable commands
- Added one-line toolchain summary near completion

---

## Updating

```bash
git pull
./bootstrap-wsl-dev.sh
```

---

## License

Use, modify, and distribute as desired.
