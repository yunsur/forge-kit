#!/usr/bin/env bash
# shellcheck disable=SC2115
# 命令: uninstall

cmd_uninstall() {
    load_registry
    local targets=("$@")
    [ ${#targets[@]} -eq 0 ] && { echo "用法: forge uninstall <tool> [tool...]"; return; }

    echo ""
    for tool in "${targets[@]}"; do
        local installed
        installed=$(get_installed "$tool")
        [ -z "$installed" ] && { echo -e "${Y}[跳过]${NC} $tool 未安装"; continue; }

        [ -d "$TOOLS_DIR/$tool" ] && rm -rf "$TOOLS_DIR/$tool" && echo -e "  删除: $TOOLS_DIR/$tool"
        [ -d "$RUNTIMES_DIR/$tool" ] && rm -rf "$RUNTIMES_DIR/$tool" && echo -e "  删除: $RUNTIMES_DIR/$tool"

        # 清理 ai/bin/ 中的失效 symlink
        find "$AI_HOME/bin" -type l ! -exec test -e {} \; -delete 2>/dev/null

        [ -f "$LOCK_FILE" ] && sed -i.bak "/^${tool}|/d" "$LOCK_FILE" && rm -f "$LOCK_FILE.bak"

        echo -e "${G}[卸载]${NC} $tool ($installed)"
    done
    echo ""
}
