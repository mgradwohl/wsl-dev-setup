# WSL C++ Development Bootstrap

A reproducible bootstrap for a modern **C++23** development environment
on **Ubuntu WSL** using **VS Code**, **Clang/LLVM**, **CMake**, and
**Ninja**.

## Features

-   Ubuntu 24.04 and 26.04 aware
-   Installs LLVM/Clang (defaults to LLVM 22)
-   Configures `clang`, `clang++`, `clangd`, `clang-tidy`,
    `clang-format`
-   Uses Ubuntu packages when available and falls back to the official
    LLVM repository when needed
-   Installs:
    -   CMake
    -   Ninja
    -   Git + Git LFS
    -   Python + venv + pip
    -   ccache
    -   GDB
    -   LLDB (only when dependency-compatible)
    -   libc++, libc++abi
    -   ripgrep, fd, bat, tree, jq
    -   Doxygen, Graphviz
    -   Valgrind
    -   Heaptrack
    -   Google gperftools
    -   Include-What-You-Use (IWYU)
-   Installs Windows VS Code (if needed)
-   Installs recommended VS Code extensions
-   Configures Git defaults
-   Configures ccache

------------------------------------------------------------------------

# Requirements

-   Windows 11
-   WSL2
-   Ubuntu 24.04 LTS or newer
-   Administrator rights (for machine-wide VS Code installation)

------------------------------------------------------------------------

# Installation

Clone:

``` bash
git clone https://github.com/<your-account>/wsl-bootstrap.git
cd wsl-bootstrap
chmod +x bootstrap-wsl-dev.sh
```

Run:

``` bash
./bootstrap-wsl-dev.sh
```

------------------------------------------------------------------------

# After Installation

Verify:

``` bash
clang --version
clangd --version
cmake --version
ninja --version
python3 --version
```

Open VS Code:

``` bash
code .
```

------------------------------------------------------------------------

# Recommended Project Layout

    ~/src/
        TaskSmack/
        LibraryA/
        LibraryB/

Avoid keeping active source code under `/mnt/c` because builds and
filesystem operations are generally much slower than using the native
Linux filesystem.

------------------------------------------------------------------------

# Recommended CMake Configure

``` bash
cmake -S . -B build \
    -G Ninja \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++ \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON
```

Build:

``` bash
cmake --build build --parallel
```

Test:

``` bash
ctest --test-dir build --output-on-failure
```

------------------------------------------------------------------------

# Useful Tools

## clang-tidy

``` bash
run-clang-tidy -p build
```

## IWYU

``` bash
iwyu_tool.py -p build
```

## Heaptrack

``` bash
heaptrack ./build/MyProgram
```

## gperftools

``` bash
CPUPROFILE=profile.out ./build/MyProgram
```

## perf

``` bash
perf record -g ./build/MyProgram
```

## Hotspot

``` bash
hotspot perf.data
```

------------------------------------------------------------------------

# Updating

``` bash
git pull
./bootstrap-wsl-dev.sh
```

The script is designed to be safely re-run.

------------------------------------------------------------------------

# Environment Variables

  Variable                      Default   Description
  ----------------------------- --------- -------------------------
  `LLVM_VERSION`                `22`      LLVM major version
  `INSTALL_WINDOWS_VSCODE`      `1`       Install VS Code
  `INSTALL_VSCODE_EXTENSIONS`   `1`       Install extensions
  `INSTALL_IWYU`                `1`       Build/install IWYU
  `INSTALL_PROFILING_TOOLS`     `1`       Install profiling tools

Example:

``` bash
LLVM_VERSION=23 ./bootstrap-wsl-dev.sh
```

------------------------------------------------------------------------

# Troubleshooting

## code not found

Restart WSL:

``` powershell
wsl --shutdown
```

Then reopen Ubuntu.

## Broken LLVM packages

Re-run the bootstrap script. It repairs stale LLVM repositories before
installing packages.

## perf unavailable

Some WSL kernels do not fully support Linux `perf`. The script warns and
continues.

------------------------------------------------------------------------

# Suggested Improvements

Ideas for future enhancements:

-   [ ] Install and configure `sccache` as an alternative to `ccache`
-   [ ] Install Conan 2 (optional)
-   [ ] Install vcpkg (optional)
-   [ ] Install CPM.cmake helper
-   [ ] Install Catch2 and GoogleTest templates
-   [ ] Generate a default `CMakePresets.json`
-   [ ] Generate a default `.clangd`
-   [ ] Generate a default `.clang-format`
-   [ ] Generate a default `.editorconfig`
-   [ ] Configure pre-commit hooks
-   [ ] Configure Git commit signing (SSH or GPG)
-   [ ] Optional Docker/Podman installation
-   [ ] Optional tmux + zoxide + fzf
-   [ ] Optional mold linker
-   [ ] Optional Benchmark library
-   [ ] Optional Tracy profiler
-   [ ] GitHub Actions template for CMake + Clang + clang-tidy
-   [ ] Optional Dev Container support
-   [ ] Self-test mode that validates every installed tool
-   [ ] Automatic backup/restore of VS Code settings and extensions

------------------------------------------------------------------------

# License

Use, modify, and distribute as desired.
