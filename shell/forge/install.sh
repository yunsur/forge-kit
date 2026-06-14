#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016
# 命令: install — 安装环境无关的工具
#
# 两阶段安装:
#   forge install   → 安装所有无需运行时依赖的工具
#   forge init      → 安装需要环境依赖的工具（python、speckit）+ 链接+npm包
#
# 子命令:
#   forge install              全量安装环境无关工具
#   forge install <tool...>    安装指定工具

# 默认不安装的工具（需手动指定，如 forge install rust）
OPTIONAL_TOOLS=(rust go)

# 检查工具是否为可选工具（全量安装时跳过）
_is_optional() {
    local tool="$1"
    for opt in "${OPTIONAL_TOOLS[@]}"; do
        [ "$tool" = "$opt" ] && return 0
    done
    return 1
}

# ── install tools ────────────────────────────────────────────

_install_tools() {
    local manifest_file="$_ROOT/download/download.manifest"
    local downloads="$_ROOT/download"

    mkdir -p "$AI_HOME/tools" "$AI_HOME/runtimes" "$AI_HOME/bin"

    # 从 download.manifest 解压
    if [ -f "$manifest_file" ]; then
        _log "install" "安装工具（从 download.manifest）"

        # 收集待处理的工具列表（跳过环境依赖）
        local tools=()
        while IFS='|' read -r tname _ _; do
            [ -z "$tname" ] && continue
            _is_env_dep "$tname" && continue
            _is_optional "$tname" && continue
            # 去重
            local found=0
            for t in "${tools[@]}"; do
                [ "$t" = "$tname" ] && found=1 && break
            done
            [ "$found" -eq 0 ] && tools+=("$tname")
        done < "$manifest_file"

        if [ ${#tools[@]} -gt 0 ]; then
            local n
            n=$(_parallel_count)
            local result_file
            mkdir -p "$TMP_DIR"
            result_file=$(mktemp "${TMP_DIR}/.install_result_XXXXXX")

            printf '%s\n' "${tools[@]}" | \
                xargs -P "$n" -I {} bash -c '
                    source "'"$ROOT_DIR"'/shell/forge/common.sh"
                    result=$(_install_one_target "{}")
                    echo "$result" >> "'"$result_file"'"
                '

            local installed=0 skipped=0 failed=0
            if [ -f "$result_file" ]; then
                installed=$(grep -c "^ok$" "$result_file" 2>/dev/null || echo 0)
                skipped=$(grep -c "^skip$" "$result_file" 2>/dev/null || echo 0)
                failed=$(grep -c "^fail$" "$result_file" 2>/dev/null || echo 0)
                rm -f "$result_file"
            fi

            ok "安装: ${installed} 成功  ${skipped} 跳过  ${failed} 失败"
        fi
    else
        _log "install" "未发现 download.manifest，跳过工具安装"
    fi

    # 字体文件从 download/ 解压
    if [ -d "$downloads/jetbrains-mono-nf" ]; then
        local font_file
        font_file=$(find "$downloads" -maxdepth 1 -name "JetBrainsMono*.zip" | head -1)
        if [ -n "$font_file" ]; then
            local mfile=""
            mfile=$(find_manifest "jetbrains-mono-nf")
            [ -n "$mfile" ] && run_install_from "$mfile" "$font_file"
        fi
    fi
}

# ── 主入口 ──────────────────────────────────────────────────

cmd_install() {
    # 开发环境安全防护
    if is_forge_dev; then
        err "当前为开发环境（forge 仓库内），禁止执行 install"
        echo -e "  ${D}如需强制执行: FORGE_SKIP_DEV_CHECK=1 forge install${NC}"
        return 1
    fi

    load_registry

    # 支持指定工具列表
    local targets=()
    for arg in "$@"; do
        case "$arg" in
            --force|-f) ;;  # TODO: 支持强制重装
            *) targets+=("$arg") ;;
        esac
    done

    if [ ${#targets[@]} -gt 0 ]; then
        # 解析依赖顺序
        local resolved=()
        for tool in "${targets[@]}"; do
            local deps
            deps=$(_resolve_deps "$tool")
            for dep in $deps; do
                local found=0
                for r in "${resolved[@]+"${resolved[@]}"}"; do
                    [ "$r" = "$dep" ] && found=1 && break
                done
                [ "$found" -eq 0 ] && resolved+=("$dep")
            done
        done

        mkdir -p "$AI_HOME/tools" "$AI_HOME/runtimes" "$AI_HOME/bin"

        local n
        n=$(_parallel_count)
        local result_file
        mkdir -p "$TMP_DIR"
        result_file=$(mktemp "${TMP_DIR}/.install_result_XXXXXX")

        printf '%s\n' "${resolved[@]+"${resolved[@]}"}" | \
            xargs -P "$n" -I {} bash -c '
                source "'"$ROOT_DIR"'/shell/forge/common.sh"
                result=$(_install_one_target "{}")
                echo "$result" >> "'"$result_file"'"
            '

        local installed=0 skipped=0 failed=0
        if [ -f "$result_file" ]; then
            installed=$(grep -c "^ok$" "$result_file" 2>/dev/null || echo 0)
            skipped=$(grep -c "^skip$" "$result_file" 2>/dev/null || echo 0)
            failed=$(grep -c "^fail$" "$result_file" 2>/dev/null || echo 0)
            rm -f "$result_file"
        fi

        ok "安装: ${installed} 成功  ${skipped} 跳过  ${failed} 失败"
        _init_bins
    else
        # 全量安装
        _install_tools
        _init_bins
    fi
}
