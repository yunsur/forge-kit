#!/usr/bin/env bash
# shellcheck disable=SC1090
# 命令: update / 默认（brew cu 风格）

cmd_check() {
    local auto_upgrade="${1:-false}"
    load_registry

    echo -e "\n${B}检查更新中...${NC}\n"

    local outdated=()
    print_header "工具" "已安装" "最新版本" "状态"

    # 缓存所有工具的最新版本
    local umf="$_ROOT/download/update.manifest"
    mkdir -p "$_ROOT/download"
    : > "$umf"

    # 去重：跳过有 JSON 版本的 shell hook
    local seen=""
    for manifest in "${REGISTRY[@]}"; do
        local name installed latest
        name=$(_meta_get_name "$manifest")
        [ -z "$name" ] && continue
        case "|$seen|" in
            *"|${name}|"*) continue ;;
        esac
        seen="${seen}|${name}"

        installed=$(get_installed "$name")

        latest=$(get_latest_version "$manifest")
        [ -n "$latest" ] && echo "${name}|${latest}" >> "$umf"

        [ -z "$installed" ] && continue
        [ -z "$latest" ] && continue

        if [ "$installed" != "$latest" ]; then
            _pad "$name" 16
            _pad "${Y}${installed}${NC}" 12
            _pad "${G}${latest}${NC}" 12
            _pad "${R}可更新${NC}" 10
            echo ""
            outdated+=("${name}|${installed}|${latest}|${manifest}")
        fi
    done

    if [ ${#outdated[@]} -eq 0 ]; then
        echo -e "\n${G}所有工具均为最新版本。${NC}\n"
        return 0
    fi

    echo -e "\n${Y}${#outdated[@]} 个工具可更新。${NC}"

    if [ "$auto_upgrade" = "true" ]; then
        do_upgrade_list "${outdated[@]}"
    else
        echo ""
        read -r -p "更新全部？[y/N] " choice < /dev/tty
        if [[ "$choice" =~ ^[Yy]$ ]]; then
            do_upgrade_list "${outdated[@]}"
        else
            echo "已取消。"
        fi
    fi
}

do_upgrade_list() {
    local entries=("$@")
    echo ""
    local ok=0 fail=0

    for entry in "${entries[@]}"; do
        IFS='|' read -r name installed latest manifest <<< "$entry"
        echo -e "${B}[升级]${NC} ${BOLD}${name}${NC}  ${installed} → ${G}${latest}${NC}"

        if run_upgrade "$manifest"; then
            set_installed "$name" "$latest"
            echo -e "  ${G}✓${NC} ${name} ${latest}"
            ((ok++)) || true
        else
            echo -e "  ${R}✗${NC} ${name} 失败"
            ((fail++)) || true
        fi
    done

    echo -e "\n${BOLD}完成:${NC} ${G}${ok} 成功${NC}  ${R}${fail} 失败${NC}\n"
}
