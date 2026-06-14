# Forge

离线 AI 工作站 — 一个自包含的 AI 开发环境，支持内网迁移。

## 快速开始

```bash
# 1. 下载工具包
./forge download

# 2. 安装环境无关工具（解压+链接，无需运行时）
./forge install

# 3. 加载环境（使 pyenv/node 等可用）
./forge start

# 4. 初始化环境依赖工具+链接+npm包
./forge init

# 5. 持久化环境（添加到 shell 配置）
echo 'source ~/ai/env.sh' >> ~/.zshrc

# 6. 检查环境
forge doctor
```

## 目录结构

```
forge/
├── forge                # CLI 入口
├── shell/
│   ├── env.sh           # 环境变量（source 加载）
│   └── forge/*.sh       # 命令模块
├── registry/            # 工具清单（每个工具一个 .sh）
├── config/
│   └── npm-packages.txt # npm 全局包列表
├── download/            # 下载缓存与 manifest
│   └── versions.lock    # 已安装版本记录
└── ai/                  # 运行时（gitignore）
    ├── bin/             # 工具符号链接
    ├── tools/           # 工具安装目录
    ├── runtimes/        # 运行时（pyenv, python）
    └── cache/           # 缓存（pip, cargo, npm）
```

## forge 命令

| 命令 | 说明 |
|------|------|
| `forge` | 检查并提示更新 |
| `forge -a` | 检查并更新全部 |
| `forge list` | 显示工具状态（3 列对齐） |
| `forge update` | 仅检查可用更新 |
| `forge download [tool...]` | 下载工具到 `download/`（不解压） |
| `forge install [tool...]` | 安装环境无关工具（解压+链接） |
| `forge start` | 加载环境（source ~/ai/env.sh） |
| `forge init [tools\|bins\|npm]` | 初始化环境依赖工具+链接+npm包 |
| `forge uninstall <tool>` | 卸载工具 |
| `forge doctor` | 环境检查 |
| `forge pack` | 打包整站用于内网迁移 |

## 工具清单

### 环境无关（`forge install`）

| 工具 | 说明 |
|------|------|
| rg (ripgrep) | 快速搜索 |
| fd | 文件查找 |
| fzf | 模糊搜索 |
| jq / yq | JSON/YAML 处理 |
| bat | 语法高亮 cat |
| eza | 现代 ls |
| delta | git diff 增强 |
| lazygit | git TUI |
| ast-grep (sg) | AST 搜索 |
| just | 任务运行器 |
| uv | Python 包管理器 |
| node / npm / npx | Node.js |
| go | Go 工具链 |
| rust / cargo | Rust 工具链 |
| claude | Claude Code CLI |
| codex | OpenAI Codex CLI |
| rtk | LLM token 压缩代理 |
| starship | 跨 shell 提示符 |
| bun | JavaScript 运行时 |
| pyenv | Python 版本管理 |
| pyenv-virtualenv | pyenv 虚拟环境插件 |
| jetbrains-mono-nf | JetBrains Mono Nerd Font |

### 环境依赖（`forge init`，需要 pyenv）

| 工具 | 依赖 | 说明 |
|------|------|------|
| python | pyenv | CPython 源码缓存 |
| speckit | pyenv python | GitHub Spec Kit |

### npm 全局包（`forge init npm`）

编辑 `config/npm-packages.txt` 添加包名：

```
# 每行一个包名，# 开头为注释
openspec
```

## 代理配置

编辑 `shell/env.sh` 取消注释对应的代理行：

```bash
export HTTP_PROXY="http://127.0.0.1:7890"
export HTTPS_PROXY="http://127.0.0.1:7890"
```

## 软件源

内网源配置在 `shell/env.sh` 顶部：

- pip/uv: `http://172.21.3.9:8081/repository/PyPI_group/simple`
- npm: `http://172.21.3.9:8081/repository/npm_group`
- go: `http://172.21.3.9:8081/repository/golang_group,direct`
- cargo: `http://172.21.3.13:8081/repository/cargo_group/`

## 内网迁移

```bash
# 有网机器：打包
./forge pack

# 传输到内网
scp forge-*.tgz target:~/

# 内网机器：解压并初始化
tar xzf forge-*.tgz
cd forge
./forge install
./forge start
./forge init
```

## 添加新工具

1. 创建 `registry/<工具名>.sh`，实现 `get_latest()`、`upgrade()` 和 `install_from()`
2. `forge download <工具名>` — 下载到 `download/`
3. `forge install <工具名>` — 安装

示例 manifest：

```bash
#!/usr/bin/env bash
_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SCRIPT_DIR/../shell/forge/common.sh"

# @name: mytool
# @repo: owner/repo

get_latest() { github_latest "owner/repo"; }

upgrade() {
    local latest; latest=$(get_latest)
    fetch "mytool" "https://github.com/owner/repo/releases/download/${latest}/mytool-linux-amd64.tar.gz" "tar.gz" "strip1"
    link_binary "$TOOLS_DIR/mytool/mytool"
}

install_from() {
    local file="$1"
    install_from_file "$file" "mytool" "tar.gz" "strip1"
    link_binary "$TOOLS_DIR/mytool/mytool"
}
```
