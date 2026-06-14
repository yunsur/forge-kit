#!/usr/bin/env bash
# @name: python
# shell hook: python (pyenv 编译安装)

VERSION="3.11.6"
PYTHON_ORG="https://www.python.org/ftp/python"

get_latest() { echo "$VERSION"; }

upgrade() {
    local ver="$VERSION"
    local dest="$RUNTIMES_DIR/python"
    mkdir -p "$dest"
    fetch_to "$dest" \
        "${PYTHON_ORG}/${ver}/Python-${ver}.tar.xz" \
        "binary" "" "Python-${ver}.tar.xz"
    echo ""
    echo "  安装: PYTHON_BUILD_CACHE_PATH=${dest} pyenv install ${ver}"
}

install_from() {
    local file="$1"
    local dest="$RUNTIMES_DIR/python"
    mkdir -p "$dest"
    cp "$file" "$dest/Python-${VERSION}.tar.xz"

    local pyenv_root="$RUNTIMES_DIR/pyenv"
    if [ -x "$pyenv_root/bin/pyenv" ]; then
        export PYENV_ROOT="$pyenv_root"
        export PATH="$pyenv_root/bin:$PATH"
        export PYTHON_BUILD_CACHE_PATH="$dest"

        if ! "$pyenv_root/bin/pyenv" versions --bare 2>/dev/null | grep -q "^${VERSION}$"; then
            echo "  编译安装 Python ${VERSION}..."
            "$pyenv_root/bin/pyenv" install "$VERSION" || {
                err "Python ${VERSION} 安装失败"
                return 1
            }
        fi

        "$pyenv_root/bin/pyenv" global "$VERSION" 2>/dev/null || true
        unset PYTHON_BUILD_CACHE_PATH
    else
        warn "pyenv 未安装，跳过 Python 编译（请先安装 pyenv）"
    fi
}
