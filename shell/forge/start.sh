#!/usr/bin/env bash
# shellcheck disable=SC1090
# 命令: start — 加载 AI 工作站环境

cmd_start() {
    local env_file="$HOME/forge/env.sh"
    if [ -f "$env_file" ]; then
        source "$env_file"
        echo -e "${G}环境已加载${NC}  source $env_file"
    else
        echo -e "${Y}环境未初始化${NC}，请先运行: forge init"
        return 1
    fi
}
