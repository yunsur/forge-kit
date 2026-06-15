#!/usr/bin/env bash
# 命令: cleanup — 清理旧版本下载文件

cmd_cleanup() {
    local downloads="$_ROOT/download"
    local manifest="$downloads/download.manifest"

    if [ ! -f "$manifest" ]; then
        echo -e "${D}没有需要清理的文件${NC}"
        return 0
    fi

    echo -e "\n${B}清理旧版本下载文件${NC}\n"

    local cleaned=0 freed=0

    # 收集当前 manifest 中的文件列表
    local current_files=""
    while IFS='|' read -r _ _ file; do
        [ -n "$file" ] && current_files="${current_files}|${file}"
    done < "$manifest"

    # 查找 download/ 中不在 manifest 里的文件
    for f in "$downloads"/*; do
        [ -f "$f" ] || continue
        local fname
        fname=$(basename "$f")

        # 跳过 manifest 文件和临时文件
        case "$fname" in
            *.manifest|*.tmp|.DS_Store) continue ;;
        esac

        # 如果文件不在当前 manifest 中，删除
        case "|$current_files|" in
            *"|${fname}"*) continue ;;
        esac

        local size
        size=$(stat -f%z "$f" 2>/dev/null || stat -c%s "$f" 2>/dev/null || echo 0)
        rm -f "$f"
        ((cleaned++)) || true
        ((freed+=size)) || true
        echo -e "  ${Y}删除${NC} $fname"
    done

    # 格式化释放空间
    local freed_human
    if [ "$freed" -gt 1048576 ]; then
        freed_human="$((freed / 1048576))MB"
    elif [ "$freed" -gt 1024 ]; then
        freed_human="$((freed / 1024))KB"
    else
        freed_human="${freed}B"
    fi

    if [ "$cleaned" -gt 0 ]; then
        echo -e "\n${G}清理完成${NC}: 删除 ${cleaned} 个文件，释放 ${freed_human}"
    else
        echo -e "\n${G}无需清理${NC}"
    fi
    echo ""
}
