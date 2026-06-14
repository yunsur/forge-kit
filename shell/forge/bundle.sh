#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2329
# 命令: bundle — 批量安装（Brewfile 风格）

cmd_bundle() {
    local subcmd="${1:-}"
    shift 2>/dev/null || true

    case "$subcmd" in
        install) _bundle_install "$@" ;;
        dump)    _bundle_dump ;;
        ""|help) _bundle_help ;;
        *)       _bundle_help ;;
    esac
}

_bundle_help() {
    cat << 'EOF'
用法:
  forge bundle install [Brewfile]   从清单批量安装（默认 ./Brewfile）
  forge bundle dump                 导出当前已安装工具到 Brewfile

Brewfile 格式:
  # 注释行
  rg
  fd
  fzf
  python          # 会自动安装依赖 pyenv
  speckit         # 会自动安装依赖 python, pyenv
EOF
}

_bundle_install() {
    local brewfile="${1:-Brewfile}"

    if [ ! -f "$brewfile" ]; then
        err "未找到 $brewfile"
        return 1
    fi

    load_registry

    local targets=()
    while IFS= read -r line; do
        # 跳过注释和空行
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [ -z "$line" ] && continue
        targets+=("$line")
    done < "$brewfile"

    if [ ${#targets[@]} -eq 0 ]; then
        warn "Brewfile 为空"
        return 0
    fi

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

    local resolved_count=${#resolved[*]}
    echo -e "\n${B}Bundle 安装${NC} (${resolved_count} 个工具)\n"

    # 并行下载
    _log "bundle" "下载中..."
    local n
    n=$(_parallel_count)
    [ "$n" -gt 4 ] && n=4

    local dl_result
    mkdir -p "$TMP_DIR"
    dl_result=$(mktemp "${TMP_DIR}/.bundle_dl_XXXXXX")

    printf '%s\n' "${resolved[@]+"${resolved[@]}"}" | \
        xargs -P "$n" -I {} bash -c "
            source '$ROOT_DIR/shell/forge/common.sh'
            result=\$(_download_one_target '{}' 0)
            echo \"\$result\" >> '$dl_result'
        "

    local dl_ok=0 dl_skip=0 dl_fail=0
    if [ -f "$dl_result" ]; then
        dl_ok=$(grep -c "^ok$" "$dl_result" 2>/dev/null || echo 0)
        dl_skip=$(grep -c "^skip$" "$dl_result" 2>/dev/null || echo 0)
        dl_fail=$(grep -c "^fail$" "$dl_result" 2>/dev/null || echo 0)
        rm -f "$dl_result"
    fi

    ok "下载: ${dl_ok} 成功  ${dl_skip} 跳过  ${dl_fail} 失败"

    # 并行安装
    echo -e "\n${B}安装中...${NC}\n"

    mkdir -p "$AI_HOME/tools" "$AI_HOME/runtimes" "$AI_HOME/bin"

    local inst_result
    inst_result=$(mktemp "${TMP_DIR}/.bundle_inst_XXXXXX")

    printf '%s\n' "${resolved[@]+"${resolved[@]}"}" | \
        xargs -P "$n" -I {} bash -c "
            source '$ROOT_DIR/shell/forge/common.sh'
            result=\$(_install_one_target '{}')
            echo \"\$result\" >> '$inst_result'
        "

    local inst_ok=0 inst_skip=0 inst_fail=0
    if [ -f "$inst_result" ]; then
        inst_ok=$(grep -c "^ok$" "$inst_result" 2>/dev/null || echo 0)
        inst_skip=$(grep -c "^skip$" "$inst_result" 2>/dev/null || echo 0)
        inst_fail=$(grep -c "^fail$" "$inst_result" 2>/dev/null || echo 0)
        rm -f "$inst_result"
    fi

    ok "安装: ${inst_ok} 成功  ${inst_skip} 跳过  ${inst_fail} 失败"
    _init_bins
    echo ""
}

_bundle_dump() {
    load_registry
    echo "# Forge Brewfile — $(date +%Y-%m-%d)"
    echo "# 用法: forge bundle install"
    echo ""
    local seen=""
    for manifest in "${REGISTRY[@]}"; do
        local name
        name=$(_meta_get_name "$manifest")
        [ -z "$name" ] && continue
        case "|$seen|" in
            *"|${name}|"*) continue ;;
        esac
        seen="${seen}|${name}"
        local installed
        installed=$(get_installed "$name")
        [ -n "$installed" ] && echo "$name"
    done
}
