#!/usr/bin/env bash
# shellcheck disable=SC1090
# 命令: init — 运行环境初始化（需要运行时依赖的工具）
#
# 两阶段安装:
#   forge install   → 安装所有无需运行时依赖的工具（解压+git clone+字体+链接）
#   forge init      → 安装需要环境依赖的工具（pyenv-virtualenv、python、speckit）
#
# 子命令:
#   forge init            全量初始化（环境依赖工具+链接+npm包）
#   forge init tools      仅安装环境依赖工具
#   forge init bins       仅链接二进制
#   forge init npm        仅安装 npm 全局包

# ── tools ───────────────────────────────────────────────────

_init_tools() {
    local manifest_file="$ROOT_DIR/download/download.manifest"
    local downloads="$ROOT_DIR/download"

    mkdir -p "$FORGE_HOME/tools" "$FORGE_HOME/runtimes"

    # 仅处理需要环境依赖的工具（python、speckit）
    local env_deps=(python speckit)

    if [ -f "$manifest_file" ]; then
        _log "init" "安装环境依赖工具（从 download.manifest）"

        declare -A TOOL_FILES
        declare -a TOOL_ORDER
        while IFS='|' read -r tname tver tfile; do
            [ -z "$tname" ] && continue
            # 跳过非环境依赖工具（已在 install 阶段处理）
            local is_env_dep=0
            for dep in "${env_deps[@]}"; do
                [ "$tname" = "$dep" ] && { is_env_dep=1; break; }
            done
            [ "$is_env_dep" -eq 0 ] && continue

            if [ -z "$tfile" ]; then
                tfile="$tver"
                tver=""
            fi
            if [ -z "${TOOL_FILES[$tname]:-}" ]; then
                TOOL_ORDER+=("$tname")
                TOOL_FILES[$tname]="$tfile"
            else
                TOOL_FILES[$tname]="${TOOL_FILES[$tname]} $tfile"
            fi
        done < "$manifest_file"

        local extracted=0 skipped=0 failed=0

        for tool in "${TOOL_ORDER[@]}"; do
            local files="${TOOL_FILES[$tool]}"

            # 增量：已安装且版本一致则跳过
            # 对于 python，需要检查 pyenv 是否真正安装了该版本
            local skip_tool=0
            if [ "$tool" = "python" ]; then
                local pyenv_bin="$FORGE_HOME/runtimes/pyenv/bin/pyenv"
                local dl_ver
                dl_ver=$(grep "^${tool}|" "$manifest_file" 2>/dev/null | tail -1 | cut -d'|' -f2)
                if [ -x "$pyenv_bin" ] && "$pyenv_bin" versions --bare 2>/dev/null | grep -q "^${dl_ver}$"; then
                    skip_tool=1
                fi
            elif [ -d "$FORGE_HOME/tools/$tool" ] || [ -d "$FORGE_HOME/runtimes/$tool" ]; then
                local latest_file=""
                for f in $files; do
                    [ -f "$downloads/$f" ] && latest_file="$f"
                done
                if [ -n "$latest_file" ]; then
                    local dl_ver
                    dl_ver=$(grep "^${tool}|" "$manifest_file" 2>/dev/null | tail -1 | cut -d'|' -f2)
                    local installed_ver
                    installed_ver=$(get_installed "$tool")
                    local dl_norm="${dl_ver#v}" inst_norm="${installed_ver#v}"
                    if [ -n "$installed_ver" ] && [ "$dl_norm" = "$inst_norm" ]; then
                        skip_tool=1
                    fi
                fi
            fi
            if [ $skip_tool -eq 1 ]; then
                ((skipped++)) || true
                continue
            fi

            local mfile=""
            for m in "$REGISTRY_DIR"/*.sh; do
                [ -f "$m" ] || continue
                if grep -q "^# @name: $tool$" "$m" 2>/dev/null; then
                    mfile="$m"
                    break
                fi
            done

            if [ -z "$mfile" ]; then
                warn "未找到 $tool 的 registry manifest，跳过"
                ((skipped++)) || true
                continue
            fi

            if grep -q '^install_from()' "$mfile" 2>/dev/null; then
                for fname in $files; do
                    local fpath="$downloads/$fname"
                    if [ -f "$fpath" ]; then
                        if (
                            source "$mfile"
                            install_from "$fpath"
                        ); then
                            ((extracted++)) || true
                        else
                            err "$tool 安装失败: $fname"
                            ((failed++)) || true
                        fi
                    else
                        warn "$tool 文件不存在: $fpath"
                        ((failed++)) || true
                    fi
                done
            else
                warn "$tool 无 install_from()，跳过"
                ((skipped++)) || true
            fi
        done

        ok "环境依赖工具: ${extracted} 成功  ${skipped} 跳过  ${failed} 失败"
    else
        _log "init" "未发现 download.manifest，跳过环境依赖工具安装"
    fi
}

# ── dirs ────────────────────────────────────────────────────

_init_dirs() {
    _log "init" "创建基础目录"
    mkdir -p "$FORGE_HOME/bin" "$FORGE_HOME/tools" "$FORGE_HOME/runtimes" "$FORGE_HOME/tmp"
    # env.sh 已在 forge install 阶段部署，此处仅确保目录存在
    ok "目录就绪"
}

# ── bins ────────────────────────────────────────────────────

_init_bins() {
    mkdir -p "$FORGE_HOME/bin"

    # 清理断裂的符号链接
    local cleaned=0
    for link in "$FORGE_HOME/bin"/*; do
        [ -L "$link" ] || continue
        if [ ! -e "$link" ]; then
            rm -f "$link"
            ((cleaned++)) || true
        fi
    done
    [ $cleaned -gt 0 ] && _log "init" "清理断裂链接: ${cleaned} 个"

    _log "init" "链接工具二进制"

    # 从 JSON manifest 读取 binaries 列表
    _tool_bins() {
        local tool="$1"
        local manifest
        manifest=$(find_manifest "$tool")
        if [ -n "$manifest" ] && [ "${manifest##*.}" = "json" ]; then
            jq -r '.binaries // [] | .[]' "$manifest" 2>/dev/null | tr '\n' ' '
        fi
    }

    local linked=0

    for tool_dir in "$FORGE_HOME/tools"/*/; do
        [ -d "$tool_dir" ] || continue
        local tool_name
        tool_name=$(basename "$tool_dir")
        local bins
        bins=$(_tool_bins "$tool_name")
        [ -z "$bins" ] && continue

        for bin_rel in $bins; do
            local src="$tool_dir/$bin_rel"
            local bname
            bname=$(basename "$bin_rel")
            if [ -f "$src" ] && [ ! -L "$FORGE_HOME/bin/$bname" ]; then
                ln -sf "$src" "$FORGE_HOME/bin/$bname"
                ((linked++)) || true
            fi
        done
    done

    for rt_dir in "$FORGE_HOME/runtimes"/*/; do
        [ -d "$rt_dir" ] || continue
        local rt_name
        rt_name=$(basename "$rt_dir")
        local bins
        bins=$(_tool_bins "$rt_name")
        [ -z "$bins" ] && continue

        for bin_rel in $bins; do
            local src="$rt_dir/$bin_rel"
            local bname
            bname=$(basename "$bin_rel")
            if [ -f "$src" ] && [ ! -L "$FORGE_HOME/bin/$bname" ]; then
                ln -sf "$src" "$FORGE_HOME/bin/$bname"
                ((linked++)) || true
            fi
        done
    done

    ok "新链接: ${linked} 个二进制 → ${FORGE_HOME}/bin/"

    # 自定义脚本
    if [ -d "$ROOT_DIR/bin" ]; then
        local custom=0
        for f in "$ROOT_DIR/bin"/*; do
            [ -f "$f" ] || continue
            local bname
            bname=$(basename "$f")
            if [ ! -L "$FORGE_HOME/bin/$bname" ]; then
                ln -sf "$f" "$FORGE_HOME/bin/$bname"
                ((custom++)) || true
            fi
        done
        [ $custom -gt 0 ] && ok "自定义脚本: ${custom} 个"
    fi
}

# ── npm 全局包 ────────────────────────────────────────────

_init_npm_packages() {
    local npm_bin="$FORGE_HOME/tools/node/bin/npm"
    if [ ! -f "$npm_bin" ]; then
        warn "node 未安装，跳过 npm 包安装"
        return 0
    fi

    # 确保 npm 全局安装到 forge 目录下
    export NPM_CONFIG_PREFIX="$FORGE_HOME/tools/node"
    "$npm_bin" config set prefix "$FORGE_HOME/tools/node" 2>/dev/null || true

    local pkg_file="$ROOT_DIR/config/npm-packages.txt"
    if [ ! -f "$pkg_file" ]; then
        _log "init" "未发现 npm-packages.txt，跳过 npm 包安装"
        return 0
    fi

    _log "init" "安装全局 npm 包"

    local installed=0 skipped=0 failed=0

    while IFS= read -r line; do
        # 跳过注释和空行
        line=$(echo "$line" | sed 's/#.*//' | xargs)
        [ -z "$line" ] && continue

        if "$npm_bin" ls -g "$line" &>/dev/null; then
            ((skipped++)) || true
            continue
        fi

        if "$npm_bin" install -g "$line" &>/dev/null; then
            ok "$line"
            ((installed++)) || true
        else
            err "$line 安装失败"
            ((failed++)) || true
        fi
    done < "$pkg_file"

    ok "npm 包: ${installed} 成功  ${skipped} 跳过  ${failed} 失败"
}

# ── 主入口 ──────────────────────────────────────────────────

cmd_init() {
    # 开发环境安全防护：禁止在 forge 仓库内生成 ai/
    if is_forge_dev; then
        err "当前为开发环境（forge 仓库内），禁止执行 init"
        echo -e "  ${D}如需强制执行: FORGE_SKIP_DEV_CHECK=1 forge init${NC}"
        return 1
    fi

    # 加载源配置（install 阶段已部署），确保 pip/npm 能找到内网源安装 speckit
    export PIP_CONFIG_FILE="$FORGE_HOME/config/pip/pip.conf"
    export NPM_CONFIG_REGISTRY="http://172.21.3.9:8081/repository/npm_group"
    [ -f "$FORGE_HOME/config/go/env" ] && source "$FORGE_HOME/config/go/env"

    case "${1:-}" in
        tools)          _init_tools ;;
        bins)           _init_bins ;;
        npm)            _init_npm_packages ;;
        "")
            _init_tools
            _init_dirs
            _init_bins
            _init_npm_packages

            echo ""
            echo -e "${G}${BOLD}初始化完成！${NC}"
            echo ""
            echo -e "  ${D}环境依赖工具（python、speckit）+ npm 包已安装${NC}"
            echo ""
            echo -e "  持久化环境（添加到 shell 配置）:"
            echo -e "  ${B}echo 'source ${FORGE_HOME}/env.sh' >> ~/.${BASH_VERSION:+bashrc}${ZSH_VERSION:+zshrc}${NC}"
            echo ""
            echo -e "  或临时加载:  ${B}forge start${NC}"
            echo -e "  检查环境:    ${B}forge doctor${NC}"
            echo ""
            ;;
        *)
            err "未知子命令: forge init $1"
            echo "用法: forge init [tools|bins]"
            return 1
            ;;
    esac
}
