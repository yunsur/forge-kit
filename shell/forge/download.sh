#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2329
# 命令: download

cmd_download() {
    load_registry
    local force=0 nodeps=0
    local targets=()
    for arg in "$@"; do
        case "$arg" in
            --force|-f) force=1 ;;
            --no-deps) nodeps=1 ;;
            *) targets+=("$arg") ;;
        esac
    done

    if [ ${#targets[@]} -eq 0 ]; then
        targets=()
        local seen=""
        for manifest in "${REGISTRY[@]}"; do
            local name
            name=$(_meta_get_name "$manifest")
            [ -z "$name" ] && continue
            case "|$seen|" in
                *"|${name}|"*) continue ;;
            esac
            seen="${seen}|${name}"
            targets+=("$name")
        done
    fi

    [ ${#targets[@]} -eq 0 ] && { echo "没有可下载的工具。"; return; }

    # 解析依赖顺序
    local resolved=()
    for tool in "${targets[@]}"; do
        if [ "$nodeps" -eq 1 ]; then
            resolved+=("$tool")
        else
            local deps
            deps=$(_resolve_deps "$tool")
            for dep in $deps; do
                local found=0
                for r in "${resolved[@]+"${resolved[@]}"}"; do
                    [ "$r" = "$dep" ] && found=1 && break
                done
                [ "$found" -eq 0 ] && resolved+=("$dep")
            done
        fi
    done

    # 准备下载目录和 manifest
    mkdir -p "$_ROOT/download"

    echo ""
    local resolved_count=${#resolved[*]}
    _log "download" "下载 ${resolved_count} 个工具"

    # 并行下载
    local n
    n=$(_parallel_count)
    # 下载限制并行数（避免 GitHub API 限流）
    [ "$n" -gt 4 ] && n=4

    local result_file
    mkdir -p "$TMP_DIR"
    result_file=$(mktemp "${TMP_DIR}/.download_result_XXXXXX")

    printf '%s\n' "${resolved[@]+"${resolved[@]}"}" | \
        xargs -P "$n" -I {} bash -c "
            source '$ROOT_DIR/shell/forge/common.sh'
            result=\$(_download_one_target '{}' '$force')
            echo \"\$result\" >> '$result_file'
        "

    local ok=0 skip=0 fail=0
    if [ -f "$result_file" ]; then
        ok=$(grep -c "^ok$" "$result_file" 2>/dev/null || true);   ok=${ok:-0}
        skip=$(grep -c "^skip$" "$result_file" 2>/dev/null || true); skip=${skip:-0}
        fail=$(grep -c "^fail$" "$result_file" 2>/dev/null || true); fail=${fail:-0}
        rm -f "$result_file"
    fi

    echo -e "\n${BOLD}完成:${NC} ${G}${ok} 成功${NC}  ${D}${skip} 跳过${NC}  ${R}${fail} 失败${NC}"
    echo -e "${D}文件保存在 download/，执行 forge install 完成安装${NC}\n"
}
