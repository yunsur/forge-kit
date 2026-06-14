#!/usr/bin/env bash
# 命令: list

cmd_list() {
    load_registry

    # 去重：跳过有 JSON 版本的 shell hook
    local seen=""
    local -a unique_registry=()
    for manifest in "${REGISTRY[@]}"; do
        local name
        name=$(_meta_get_name "$manifest")
        [ -z "$name" ] && continue
        case "|$seen|" in
            *"|${name}|"*) continue ;;
        esac
        seen="${seen}|${name}"
        unique_registry+=("$manifest")
    done

    print_header "工具" "当前版本" "最新版本"

    local umf="$_ROOT/download/update.manifest"
    mkdir -p "$_ROOT/download"

    for manifest in "${unique_registry[@]}"; do
        local name current latest
        name=$(_meta_get_name "$manifest")
        current=$(get_installed "$name")
        [ -z "$current" ] && current=$(get_downloaded "$name")
        latest=$(get_latest_version "$manifest")
        [ -n "$latest" ] && echo "${name}|${latest}" >> "$umf"
        [ -z "$latest" ] && latest=$(get_downloaded "$name")

        if [ -z "$current" ] && [ -z "$latest" ]; then
            _pad "$name" 20
            _pad "-" 12
            _pad "-" 12
            echo ""
        elif [ -n "$current" ] && [ -n "$latest" ] && [ "$current" != "$latest" ]; then
            _pad "$name" 20
            _pad "$current" 12
            _pad "${Y}${latest}${NC}" 12
            echo ""
        else
            _pad "$name" 20
            _pad "${current:--}" 12
            _pad "${latest:--}" 12
            echo ""
        fi
    done
    echo ""
}
