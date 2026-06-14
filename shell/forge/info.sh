#!/usr/bin/env bash
# shellcheck disable=SC1090
# 命令: info — 显示工具详情

cmd_info() {
    local tool="${1:-}"

    if [ -z "$tool" ]; then
        echo "用法: forge info <tool>"
        return 1
    fi

    load_registry

    local manifest
    manifest=$(find_manifest "$tool")
    if [ -z "$manifest" ]; then
        err "未知工具: $tool"
        return 1
    fi

    echo -e "\n${BOLD}${tool}${NC}\n"

    case "$manifest" in
        *.json)
            _json_info "$manifest"
            ;;
        *.sh)
            _shell_info "$manifest"
            ;;
    esac
}

_json_info() {
    local manifest="$1"

    # 基本信息
    local desc repo
    desc=$(_json_get "$manifest" "desc")
    repo=$(_json_get "$manifest" "repo")

    [ -n "$desc" ] && echo -e "  ${D}描述:${NC} $desc"
    [ -n "$repo" ] && echo -e "  ${D}仓库:${NC} https://github.com/$repo"

    # 依赖
    local deps
    deps=$(jq -r '.depends_on // [] | .[]' "$manifest" 2>/dev/null)
    if [ -n "$deps" ]; then
        echo -e "  ${D}依赖:${NC} $deps"
    fi

    # 版本信息
    local installed latest
    installed=$(get_installed "$tool")
    latest=$(get_latest_version "$manifest")

    if [ -n "$installed" ]; then
        echo -e "  ${D}已安装:${NC} ${G}$installed${NC}"
    else
        echo -e "  ${D}已安装:${NC} ${Y}未安装${NC}"
    fi

    if [ -n "$latest" ]; then
        echo -e "  ${D}最新版本:${NC} $latest"
        if [ -n "$installed" ] && [ "$installed" != "$latest" ]; then
            echo -e "  ${D}状态:${NC} ${Y}可更新${NC}"
        elif [ -n "$installed" ]; then
            echo -e "  ${D}状态:${NC} ${G}最新${NC}"
        fi
    fi

    # 下载信息
    local download_file=""
    if [ -f "$_ROOT/download/download.manifest" ]; then
        download_file=$(grep "^${tool}|" "$_ROOT/download/download.manifest" 2>/dev/null | tail -1 | cut -d'|' -f3)
    fi

    if [ -n "$download_file" ] && [ -f "$_ROOT/download/$download_file" ]; then
        local size
        size=$(stat -f%z "$_ROOT/download/$download_file" 2>/dev/null || stat -c%s "$_ROOT/download/$download_file" 2>/dev/null || echo 0)
        local size_human
        if [ "$size" -gt 1048576 ]; then
            size_human="$((size / 1048576))MB"
        elif [ "$size" -gt 1024 ]; then
            size_human="$((size / 1024))KB"
        else
            size_human="${size}B"
        fi
        echo -e "  ${D}下载文件:${NC} $download_file ($size_human)"
    fi

    # 安装目录
    local install_to
    install_to=$(_json_get "$manifest" "install_to")
    if [ -n "$install_to" ]; then
        install_to=$(eval echo "$install_to")
        echo -e "  ${D}安装目录:${NC} $install_to"
    elif [ -d "$TOOLS_DIR/$tool" ]; then
        echo -e "  ${D}安装目录:${NC} $TOOLS_DIR/$tool"
    fi

    echo ""
}

_shell_info() {
    local manifest="$1"
    local name
    name=$(_meta_get_name "$manifest")

    # 版本信息
    local installed latest
    installed=$(get_installed "$name")
    latest=$(get_latest_version "$manifest")

    echo -e "  ${D}类型:${NC} Shell hook"

    if [ -n "$installed" ]; then
        echo -e "  ${D}已安装:${NC} ${G}$installed${NC}"
    else
        echo -e "  ${D}已安装:${NC} ${Y}未安装${NC}"
    fi

    if [ -n "$latest" ]; then
        echo -e "  ${D}最新版本:${NC} $latest"
        if [ -n "$installed" ] && [ "$installed" != "$latest" ]; then
            echo -e "  ${D}状态:${NC} ${Y}可更新${NC}"
        elif [ -n "$installed" ]; then
            echo -e "  ${D}状态:${NC} ${G}最新${NC}"
        fi
    fi

    echo ""
}
