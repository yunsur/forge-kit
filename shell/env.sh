#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────
# AI 工作站环境
# 用法: source $AI_HOME/env.sh
# ─────────────────────────────────────────────────────────

AI_HOME="${AI_HOME:-$HOME/forge}"
RUNTIMES="$AI_HOME/runtimes"

# 注意：env.sh 仅负责环境变量设置，不执行任何文件操作

# ── 内网源 ───────────────────────────────────────────────
export PIP_INDEX_URL="http://172.21.3.9:8081/repository/PyPI_group/simple"
export PIP_TRUSTED_HOST="172.21.3.9"
export NPM_CONFIG_REGISTRY="http://172.21.3.9:8081/repository/npm_group"
export GOPROXY="http://172.21.3.9:8081/repository/golang_group,direct"

# ── pyenv（最高优先级，确保 python/pip 使用 pyenv 版本）───
export PYENV_ROOT="$RUNTIMES/pyenv"
if [ -d "$PYENV_ROOT/bin" ]; then
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)"
    pyenv commands -q virtualenv-init 2>/dev/null && eval "$(pyenv virtualenv-init -)"

    # 激活已安装的 Python 版本（优先 global → local → 第一个已安装版本）
    _pyenv_version=""
    if [ -f "$PYENV_ROOT/version" ]; then
        _pyenv_version=$(cat "$PYENV_ROOT/version")
    elif [ -f ".python-version" ]; then
        _pyenv_version=$(cat ".python-version")
    else
        # 取已安装版本列表中最新的非系统版本
        _pyenv_version=$("$PYENV_ROOT/bin/pyenv" versions --bare 2>/dev/null | grep -v '^system' | tail -1)
    fi
    if [ -n "$_pyenv_version" ]; then
        pyenv shell "$_pyenv_version" 2>/dev/null || true
    fi
    unset _pyenv_version
fi

# ── nvm ──────────────────────────────────────────────────
export NVM_DIR="$RUNTIMES/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# ── Go ───────────────────────────────────────────────────
if command -v go &>/dev/null; then
    export GOPATH="$AI_HOME/cache/go"
    export GOPROXY="https://goproxy.cn,direct"
fi

# ── Rust ─────────────────────────────────────────────────
if command -v cargo &>/dev/null; then
    export CARGO_HOME="$AI_HOME/cache/cargo"
    export RUSTUP_HOME="$AI_HOME/cache/rustup"
    export RUSTUP_DIST_SERVER="https://rsproxy.cn"
    export RUSTUP_UPDATE_ROOT="https://rsproxy.cn/rustup"
    export CARGO_REGISTRIES_CRATES_IO_PROTOCOL="sparse"
    export CARGO_REGISTRIES_CRATES_IO_INDEX="sparse+http://172.21.3.13:8081/repository/cargo_group/"
    [ -d "$CARGO_HOME/bin" ] && PATH="$CARGO_HOME/bin:$PATH"
fi

# ── 工具二进制 ────────────────────────────────────────────
[ -d "$AI_HOME/bin" ] && PATH="$AI_HOME/bin:$PATH"

# ── 导出 ─────────────────────────────────────────────────
export PATH
export AI_HOME
export TMPDIR="$AI_HOME/tmp"
export LD_LIBRARY_PATH

# ── PyPI ─────────────────────────────────────────────────
export PIP_CACHE_DIR="$AI_HOME/cache/pip"
export UV_CACHE_DIR="$AI_HOME/cache/uv"

# ── Node.js ──────────────────────────────────────────────
_node_bin="$AI_HOME/tools/node/bin"
if [ -d "$_node_bin" ]; then
    PATH="$_node_bin:$PATH"
    [ -d "$AI_HOME/tools/node/lib/node_modules" ] && export NODE_PATH="$AI_HOME/tools/node/lib/node_modules"
fi
unset _node_bin

# ── OpenSpec ──────────────────────────────────────────────
export OPENSPEC_TELEMETRY=0
export DO_NOT_TRACK=1

# ── git + delta ──────────────────────────────────────────
if command -v delta &>/dev/null; then
    export GIT_PAGER="delta"
    export DELTA_FEATURES="line-numbers side-by-side"
fi

# ── fzf ──────────────────────────────────────────────────
if command -v fzf &>/dev/null; then
    export FZF_DEFAULT_OPTS="--height 40% --layout=reverse --border"
    command -v fd &>/dev/null && export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
    alias preview="fzf --preview 'bat --color=always {}'"
fi

# ── eza ──────────────────────────────────────────────────
if command -v eza &>/dev/null; then
    alias ls="eza --icons"
    alias ll="eza -la --icons --git"
    alias tree="eza --tree --icons --level=3"
fi

# ── starship ──────────────────────────────────────────────
if command -v starship &>/dev/null; then
    eval "$(starship init "${ZSH_VERSION:+zsh}${BASH_VERSION:+bash}")"
fi

# ── 快速导航 ─────────────────────────────────────────────
alias forge="cd \$AI_HOME"
alias ..="cd .."
alias ...="cd ../.."

# ── git ──────────────────────────────────────────────────
alias g="git"
alias gs="git status -sb"
alias gd="git diff"
alias gds="git diff --staged"
alias gl="git log --oneline -20"
alias gp="git pull --rebase"
alias gc="git commit"
alias gco="git checkout"
alias gb="git branch -a"

# 快速搜索文件内容
ff() { rg --color=always "$@" 2>/dev/null || grep -rn "$@" .; }

# 创建目录并进入
mkcd() { mkdir -p "$1" && cd "$1" || return; }

# 查看环境变量
envs() { env | grep -i "${1:-}" | sort; }
