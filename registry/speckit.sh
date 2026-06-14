#!/usr/bin/env bash
# @name: speckit
# shell hook: speckit (pip install)

install_from() {
    local file="$1"
    local dest="$TOOLS_DIR/speckit"
    mkdir -p "$dest"
    _tar_quiet tar -xzf "$file" -C "$dest" --strip-components=1 \
        || { err "speckit 解压失败"; return 1; }

    # 查找可用的 Python
    local python_cmd=""
    local pyenv_root="$RUNTIMES_DIR/pyenv"
    if [ -x "$pyenv_root/bin/pyenv" ]; then
        export PYENV_ROOT="$pyenv_root"
        export PATH="$pyenv_root/bin:$PATH"
        python_cmd="$pyenv_root/bin/pyenv exec python"
    elif command -v python3 &>/dev/null; then
        python_cmd="python3"
    elif command -v python &>/dev/null; then
        python_cmd="python"
    else
        err "需要先安装 Python: forge init tools"
        return 1
    fi

    export PIP_INDEX_URL="http://172.21.3.9:8081/repository/PyPI_group/simple"
    export PIP_TRUSTED_HOST="172.21.3.9"

    (cd "$dest" && $python_cmd -m pip install --target "$dest/lib" .) \
        || { err "speckit 安装失败"; return 1; }

    mkdir -p "$dest/bin"
    local python_bin
    python_bin=$($python_cmd -c "import sys; print(sys.executable)")
    cat > "$dest/bin/specify" << EOF
#!${python_bin}
import sys, os
_script = os.path.abspath(__file__)
if os.path.islink(_script):
    _script = os.path.realpath(_script)
sys.path.insert(0, os.path.join(os.path.dirname(_script), '..', 'lib'))
from specify_cli import main
if __name__ == '__main__':
    main()
EOF
    chmod +x "$dest/bin/specify"
    link_binary "$dest/bin/specify" "specify"
}
