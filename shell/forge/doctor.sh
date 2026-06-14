#!/usr/bin/env bash
# 命令: doctor

cmd_doctor() {
    echo -e "\n${BOLD}forge doctor${NC} — 环境检查\n"
    local ok=0 warn=0 fail=0

    # 加载 ai/bin 到 PATH
    [ -d "$AI_HOME/bin" ] && PATH="$AI_HOME/bin:$PATH"
    [ -d "$AI_HOME/runtimes/pyenv/bin" ] && PATH="$AI_HOME/runtimes/pyenv/bin:$PATH"
    [ -d "$AI_HOME/cache/cargo/bin" ] && PATH="$AI_HOME/cache/cargo/bin:$PATH"

    # 1. 检查 ai/bin 中的工具
    echo -e "${B}[工具链]${NC}"
    for cmd in rg fd fzf jq yq bat eza delta lazygit sg just uv node python3 go rustc cargo claude codex bun; do
        if command -v "$cmd" &>/dev/null; then
            local ver="ok"
            set +e
            case "$cmd" in
                rg)       ver=$(rg --version 2>/dev/null | head -1 | awk '{print $2}') ;;
                python3)  ver=$(python3 --version 2>/dev/null | awk '{print $2}') ;;
                node)     ver=$(node --version 2>/dev/null) ;;
                go)       ver=$(go version 2>/dev/null | awk '{print $3}' | sed 's/go//') ;;
                rustc)    ver=$(rustc --version 2>/dev/null | awk '{print $2}') ;;
                claude)   ver=$(claude --version 2>/dev/null | head -1) ;;
                codex)    ver=$(codex --version 2>/dev/null | head -1) ;;
                bun)      ver=$(bun --version 2>/dev/null) ;;
            esac
            set -e
            printf "  ${G}✓${NC} %-14s %s\n" "$cmd" "$ver"
            ((ok++)) || true
        else
            printf "  ${R}✗${NC} %-14s 未找到\n" "$cmd"
            ((fail++)) || true
        fi
    done

    # 2. 检查代理连通性
    echo -e "\n${B}[网络]${NC}"
    local targets=("https://github.com" "https://registry.npmmirror.com" "https://mirrors.aliyun.com" "https://goproxy.cn" "https://rsproxy.cn")
    for url in "${targets[@]}"; do
        if curl -sI --connect-timeout 5 "$url" &>/dev/null; then
            printf "  ${G}✓${NC} %s\n" "$url"
            ((ok++)) || true
        else
            printf "  ${Y}!${NC} %s 不可达\n" "$url"
            ((warn++)) || true
        fi
    done

    # 3. 检查目录结构
    echo -e "\n${B}[目录]${NC}"
    local dirs=("$AI_HOME/bin" "$AI_HOME/tools" "$AI_HOME/runtimes")
    for d in "${dirs[@]}"; do
        if [ -d "$d" ]; then
            local count
            count=$(find "$d" -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
            printf "  ${G}✓${NC} %-30s (%s 项)\n" "${d#"$HOME"/}" "$count"
            ((ok++)) || true
        else
            printf "  ${Y}!${NC} %-30s 不存在\n" "${d#"$HOME"/}"
            ((warn++)) || true
        fi
    done

    echo -e "\n${BOLD}结果:${NC} ${G}${ok} 通过${NC}  ${Y}${warn} 警告${NC}  ${R}${fail} 失败${NC}\n"
}
