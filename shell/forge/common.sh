#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2034,SC2329
# 公共函数库（被 manifest、forge 和 init.sh source）

_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FORGE_HOME="${FORGE_HOME:-$HOME/forge}"
TOOLS_DIR="$FORGE_HOME/tools"
RUNTIMES_DIR="$FORGE_HOME/runtimes"
TMP_DIR="$_ROOT/download/.tmp"

OS="${OS:-linux}"
ARCH="${ARCH:-amd64}"

# 开发环境检测：在 forge 仓库内运行时拒绝 init
is_forge_dev() {
    [ -d "$_ROOT/.git" ] && [ "${FORGE_SKIP_DEV_CHECK:-0}" != "1" ]
}

# 颜色
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m'
D='\033[2m' NC='\033[0m' BOLD='\033[1m'

_log()  { echo -e "${B}[$1]${NC} $2"; }
ok()    { echo -e "  ${G}✓${NC} $1"; }
warn()  { echo -e "  ${Y}!${NC} $1" >&2; }
err()   { echo -e "  ${R}✗${NC} $1" >&2; }

# curl 通用选项（代理和 token）— 设置全局数组 _CURL_OPTS
_curl_base_opts() {
    _CURL_OPTS+=(--connect-timeout 10 --retry 3 --retry-delay 2 --retry-all-errors)
    [ -n "${https_proxy:-${HTTPS_PROXY:-}}" ] && _CURL_OPTS+=(--proxy "${https_proxy:-$HTTPS_PROXY}")
    [ -n "${http_proxy:-${HTTP_PROXY:-}}" ] && _CURL_OPTS+=(--proxy "${http_proxy:-$HTTP_PROXY}")
    [ -n "${GITHUB_TOKEN:-}" ] && _CURL_OPTS+=(-H "Authorization: Bearer $GITHUB_TOKEN")
}

# API 请求用（短超时）
_curl_opts() {
    _CURL_OPTS=(-fsSL --max-time 30)
    _curl_base_opts
}

# 文件下载用（无 max-time 限制）
_curl_download_opts() {
    _CURL_OPTS=(-fSL --retry-max-time 0)
    _curl_base_opts
    _CURL_OPTS+=(-H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/136.0.0.0 Safari/537.36")
}

# GitHub API: 获取最新 release tag
github_latest() {
    local repo="$1" version=""
    _curl_opts
    version=$(curl "${_CURL_OPTS[@]}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null \
        | grep '"tag_name"' | head -1 \
        | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)
    if [ -z "$version" ]; then
        _curl_opts
        version=$(curl "${_CURL_OPTS[@]}" "https://github.com/${repo}/releases/latest" 2>/dev/null \
            | grep -o 'releases/tag/[^"]*' \
            | sed -E 's|releases/tag/||' \
            | grep '[0-9]' | head -1 || true)
    fi
    echo "$version"
}

# 下载 + 解压到 tools/<name>
fetch() {
    local name="$1" url="$2" format="$3" mode="${4:-}" binary_name="${5:-}"
    _log "下载" "$name"
    local dest="$TOOLS_DIR/$name" tmp="$TMP_DIR/$name"
    mkdir -p "$dest" "$TMP_DIR"
    _curl_download_opts; curl "${_CURL_OPTS[@]}" -o "$tmp" "$url"
    _extract "$tmp" "$dest" "$format" "$mode" "$binary_name"
    rm -f "$tmp"
    ok "$name"
}

# 下载 + 解压到指定目录
fetch_to() {
    local dest="$1" url="$2" format="$3" mode="${4:-}" binary_name="${5:-}"
    local tmp="$TMP_DIR/_fetch_$$"
    mkdir -p "$dest" "$TMP_DIR"
    _curl_download_opts; curl "${_CURL_OPTS[@]}" -o "$tmp" "$url"
    _extract "$tmp" "$dest" "$format" "$mode" "$binary_name"
    rm -f "$tmp"
}

# 抑制 macOS LIBARCHIVE xattr 警告（GNU tar 不认识这些头）
_tar_quiet() { "$@" 2> >(grep -v 'LIBARCHIVE.xattr' >&2); }

_extract() {
    local tmp="$1" dest="$2" format="$3" mode="$4" binary_name="$5"
    case "$format" in
        tar.xz|txz)
            case "$mode" in
                strip1) _tar_quiet tar -xJf "$tmp" -C "$dest" --strip-components=1 || return 1 ;;
                flat)   _tar_quiet tar -xJf "$tmp" -C "$dest" || return 1 ;;
                *) _tar_quiet tar -xJf "$tmp" -C "$dest" || return 1 ;;
            esac
            ;;
        tar.gz|tgz)
            case "$mode" in
                strip1) _tar_quiet tar -xzf "$tmp" -C "$dest" --strip-components=1 || return 1 ;;
                flat)   _tar_quiet tar -xzf "$tmp" -C "$dest" || return 1 ;;
                flat-binary)
                    _tar_quiet tar -xzf "$tmp" -C "$dest" || return 1
                    local bin
                    bin=$(find "$dest" -type f -name "$binary_name" | head -1)
                    if [ -z "$bin" ]; then
                        bin=$(find "$dest" -type f -name "${binary_name}_*" | head -1)
                    fi
                    if [ -n "$bin" ] && [ "$bin" != "$dest/$binary_name" ]; then
                        mv "$bin" "$dest/$binary_name"
                    fi
                    # 清理多余文件
                    find "$dest" -mindepth 1 -maxdepth 1 ! -name "$binary_name" -exec rm -rf {} + 2>/dev/null
                    [ -f "$dest/$binary_name" ] && chmod +x "$dest/$binary_name"
                    ;;
                *) _tar_quiet tar -xzf "$tmp" -C "$dest" || return 1 ;;
            esac
            ;;
        zip)
            unzip -q -o "$tmp" -d "$dest" || return 1
            if [ "$mode" = "flat-binary" ] && [ -n "$binary_name" ]; then
                local bin
                bin=$(find "$dest" -type f -name "$binary_name" | head -1)
                if [ -n "$bin" ] && [ "$bin" != "$dest/$binary_name" ]; then
                    mv "$bin" "$dest/$binary_name"
                    find "$dest" -mindepth 1 ! -name "$binary_name" -exec rm -rf {} + 2>/dev/null
                fi
                chmod +x "$dest/$binary_name"
            fi
            ;;
        binary)
            cp "$tmp" "$dest/$binary_name"
            chmod +x "$dest/$binary_name"
            ;;
    esac
}

# 将二进制链接到 ai/bin/
link_binary() {
    local src="$1" name="${2:-$(basename "$1")}"
    [ -f "$src" ] || return 0
    mkdir -p "$FORGE_HOME/bin"
    ln -sf "$src" "$FORGE_HOME/bin/$name"
}

# 更新脚本中的 VERSION 变量
update_script_version() {
    local script="$1" version="$2"
    if [ -f "$script" ] && grep -q '^VERSION=' "$script" 2>/dev/null; then
        sed -i.bak "s|^VERSION=.*|VERSION=\"${version}\"|" "$script"
        rm -f "${script}.bak"
    fi
}

# ── 下载专用函数（forge download 使用）────────────────────

# 只下载不解压，保存到 download/
download_only() {
    local name="$1" url="$2" filename="${3:-}"
    [ -z "$filename" ] && filename=$(basename "$url" | sed 's/?.*//')
    local dest="$_ROOT/download"
    mkdir -p "$dest"
    _log "下载" "$name → $filename"
    _curl_download_opts; curl "${_CURL_OPTS[@]}" -o "$dest/$filename" "$url"
    ok "$name"
}

# 从本地文件解压（供 manifest 的 install_from() 调用）
install_from_file() {
    local file="$1" name="$2" format="$3" mode="$4" binary_name="${5:-}"
    local dest="$TOOLS_DIR/$name"
    mkdir -p "$dest"
    _extract "$file" "$dest" "$format" "$mode" "$binary_name"
}

# ── 下载辅助函数（供并行调用）─────────────────────────────

_version_eq() {
    local a="${1#v}" b="${2#v}"
    [ "$a" = "$b" ]
}

_cleanup_old_versions() {
    local name="$1"
    local dest="$_ROOT/download"
    local mf="$dest/download.manifest"
    [ -f "$mf" ] || return 0

    while IFS='|' read -r tname _ tfile; do
        [ "$tname" = "$name" ] && [ -n "$tfile" ] && [ -f "$dest/$tfile" ] && rm -f "$dest/$tfile"
    done < "$mf"
}

# download 专用：覆盖 fetch/fetch_to/link_binary，只下载不安装
_fetch_for_download() {
    local name="$1" url="$2"
    local filename="${_DOWNLOAD_FILENAME:-}"
    [ -z "$filename" ] && filename=$(basename "$url" | sed 's/?.*//')
    local dest="$_ROOT/download"
    mkdir -p "$dest"

    # 删除该工具的旧版本文件
    local mf="$_ROOT/download/download.manifest"
    if [ -f "$mf" ]; then
        while IFS='|' read -r tname _ tfile; do
            [ "$tname" = "$name" ] && [ -n "$tfile" ] && [ -f "$dest/$tfile" ] && rm -f "$dest/$tfile"
        done < "$mf"
    fi

    # 删除同名文件（不产生 .1 .2）
    [ -f "$dest/$filename" ] && rm -f "$dest/$filename"

    _log "下载" "$name → $filename"
    _curl_download_opts; curl "${_CURL_OPTS[@]}" -o "$dest/$filename" "$url"
    # 更新 install manifest（name|version|filename，去除旧条目）
    [ -f "$mf" ] && sed -i.bak "/^${name}|/d" "$mf" && rm -f "$mf.bak"
    echo "${name}|${_DOWNLOAD_VERSION:-?}|${filename}" >> "$mf"
    ok "$name"
}

_fetch_to_for_download() {
    local dest="$1" url="$2"
    local filename
    filename=$(basename "$url" | sed 's/?.*//')
    local dl_dest="$_ROOT/download"
    mkdir -p "$dl_dest"

    # 删除同名文件（不产生 .1 .2）
    [ -f "$dl_dest/$filename" ] && rm -f "$dl_dest/$filename"

    _curl_download_opts; curl "${_CURL_OPTS[@]}" -o "$dl_dest/$filename" "$url"
    local ver="${filename%.tar.gz}"; ver="${ver%.tgz}"; ver="${ver%.tar.xz}"; ver="${ver%.zip}"
    echo "$(basename "$dest")|${ver}|${filename}" >> "$_ROOT/download/download.manifest"
}

# JSON manifest: 下载专用 upgrade（纯声明式，hook 仅用于安装）
_json_download_upgrade() {
    local manifest="$1"
    local name repo

    name=$(_json_get "$manifest" "name")
    repo=$(_json_get "$manifest" "repo")

    # 声明式 upgrade
    local tag
    tag=$(_json_get_latest "$manifest")
    [ -z "$tag" ] && { err "无法获取 $name 最新版本"; return 1; }

    # arch 映射
    local target_arch
    target_arch=$(_json_get_arch "$manifest" "$ARCH")
    [ -z "$target_arch" ] && target_arch="$ARCH"

    # URL 模板
    local url_template
    url_template=$(_json_get "$manifest" "url")
    [ -z "$url_template" ] && { err "$name 无 URL 模板"; return 1; }

    local url
    url=$(_resolve_url "$url_template" "$tag" "$repo" "$tag" "$target_arch")

    # 下载
    _fetch_for_download "$name" "$url"
}

# 单工具下载（供并行调用）
_download_one_target() {
    local tool="$1"
    local force="${2:-0}"

    local manifest
    manifest=$(find_manifest "$tool")
    [ -z "$manifest" ] && { echo "fail"; return; }

    local latest
    latest=$(get_latest_version "$manifest")
    [ -z "$latest" ] && { echo "fail"; return; }

    local installed
    installed=$(get_installed "$tool")
    if [ "$force" -ne 1 ] && [ -n "$installed" ] && _version_eq "$installed" "$latest"; then
        echo "skip"
        return
    fi

    # 版本不同，删除旧版本文件
    [ -n "$installed" ] && ! _version_eq "$installed" "$latest" && _cleanup_old_versions "$tool"

    # 下载
    _DOWNLOAD_NAME="$tool"
    _DOWNLOAD_VERSION="$latest"

    local success=0
    case "$manifest" in
        *.json) _json_download_upgrade "$manifest" && success=1 ;;
        *.sh)
            if (
                source "$manifest"
                fetch() { _fetch_for_download "$@"; }
                fetch_to() { _fetch_to_for_download "$@"; }
                link_binary() { :; }
                type upgrade &>/dev/null && upgrade
            ); then
                success=1
            fi
            ;;
    esac

    if [ "$success" -eq 1 ]; then
        set_installed "$tool" "$latest"
        echo "ok"
    else
        echo "fail"
    fi
}

# ── Forge CLI 共享函数 ────────────────────────────────────

REGISTRY_DIR="${REGISTRY_DIR:-$_ROOT/registry}"
LOCK_FILE="${LOCK_FILE:-$_ROOT/download/versions.lock}"

# 需要环境依赖的工具列表（跳过，留给 init 处理）
ENV_DEPS_TOOLS=(python speckit)

# 检查工具是否在环境依赖列表中
_is_env_dep() {
    local tool="$1"
    for dep in "${ENV_DEPS_TOOLS[@]}"; do
        [ "$tool" = "$dep" ] && return 0
    done
    return 1
}

# 单工具安装（供并行调用）
_install_one_target() {
    local tool="$1"
    local downloads="$_ROOT/download"

    # 跳过环境依赖工具
    _is_env_dep "$tool" && { echo "skip"; return; }

    # 字体特殊处理
    if [ "$tool" = "jetbrains-mono-nf" ]; then
        local font_file
        font_file=$(find "$downloads" -maxdepth 1 -name "JetBrainsMono*.zip" | head -1)
        if [ -n "$font_file" ]; then
            local mfile
            mfile=$(find_manifest "jetbrains-mono-nf")
            if [ -n "$mfile" ] && run_install_from "$mfile" "$font_file"; then
                echo "ok"
                return
            fi
        fi
        echo "fail"
        return
    fi

    # 查找 manifest
    local mfile
    mfile=$(find_manifest "$tool")
    [ -z "$mfile" ] && { echo "skip"; return; }

    # 查找 download 文件
    local files=""
    if [ -f "$downloads/download.manifest" ]; then
        while IFS='|' read -r tname _ tfile; do
            [ "$tname" = "$tool" ] && [ -n "$tfile" ] && files="${files:+$files }$tfile"
        done < "$downloads/download.manifest"
    fi

    # fallback
    if [ -z "$files" ]; then
        files=$(find "$downloads" -maxdepth 1 -name "*${tool}*" -not -name "*.manifest" -not -name "*.tmp" -type f 2>/dev/null | head -1)
        [ -n "$files" ] && files=$(basename "$files")
    fi

    [ -z "$files" ] && { echo "skip"; return; }

    # 安装
    for fname in $files; do
        local fpath="$downloads/$fname"
        if [ -f "$fpath" ] && run_install_from "$mfile" "$fpath"; then
            echo "ok"
            return
        fi
    done

    echo "fail"
}

# JSON manifest 辅助函数
_json_get() {
    local file="$1" key="$2" default="${3:-}"
    local val
    val=$(jq -r ".$key // empty" "$file" 2>/dev/null) || true
    [ -z "$val" ] && val="$default"
    echo "$val"
}

_json_get_arch() {
    local file="$1" arch="$2"
    jq -r ".arch[\"$arch\"] // empty" "$file" 2>/dev/null || true
}

# 加载注册表（JSON + Shell）
load_registry() {
    REGISTRY=()
    # JSON manifests
    for f in "$REGISTRY_DIR"/*.json; do
        [ -f "$f" ] || continue
        REGISTRY+=("$f")
    done
    # Shell hook manifests
    for f in "$REGISTRY_DIR"/*.sh; do
        [ -f "$f" ] || continue
        REGISTRY+=("$f")
    done
}

# 获取 manifest 的 name（兼容 JSON 和 Shell）
_meta_get_name() {
    local manifest="$1"
    case "$manifest" in
        *.json) _json_get "$manifest" "name" ;;
        *.sh)   grep "^# @name:" "$manifest" 2>/dev/null | head -1 | sed 's/^# @name: *//' || true ;;
    esac
}

# 获取工具的依赖列表（仅 JSON manifest）
_get_dependencies() {
    local name="$1"
    local manifest
    manifest=$(find_manifest "$name")
    if [ -n "$manifest" ] && [ "${manifest##*.}" = "json" ]; then
        jq -r '.depends_on // [] | .[]' "$manifest" 2>/dev/null
    fi
}

# 拓扑排序：解析依赖顺序（返回从底到顶的安装顺序）
_resolve_deps() {
    local name="$1"
    local visited="${2:-}"
    local deps

    # 防止循环依赖
    case "|$visited|" in
        *"|${name}|"*) return ;;
    esac
    visited="${visited}|${name}"

    deps=$(_get_dependencies "$name")
    for dep in $deps; do
        _resolve_deps "$dep" "$visited"
    done
    echo "$name"
}

# 获取 manifest 的 repo（兼容 JSON 和 Shell）
_meta_get_repo() {
    local manifest="$1"
    case "$manifest" in
        *.json) _json_get "$manifest" "repo" ;;
        *.sh)   grep "^# @repo:" "$manifest" 2>/dev/null | head -1 | sed 's/^# @repo: *//' || true ;;
    esac
}

meta_get() {
    local manifest="$1" key="$2"
    case "$manifest" in
        *.json) _json_get "$manifest" "$key" ;;
        *.sh)   grep "^# @${key}:" "$manifest" 2>/dev/null | head -1 | sed "s/^# @${key}: *//" || true ;;
    esac
}

get_installed() {
    [ -f "$LOCK_FILE" ] && grep "^${1}|" "$LOCK_FILE" 2>/dev/null | tail -1 | cut -d'|' -f2 || true
}

# 查找 manifest（JSON 优先）
find_manifest() {
    local name="$1"
    # 优先查找 JSON
    for m in "$REGISTRY_DIR"/*.json; do
        [ -f "$m" ] || continue
        [ "$(_json_get "$m" "name")" = "$name" ] && { echo "$m"; return; }
    done
    # 回退到 Shell
    for m in "$REGISTRY_DIR"/*.sh; do
        [ -f "$m" ] || continue
        if grep -q "^# @name: $name$" "$m" 2>/dev/null; then
            echo "$m"
            return
        fi
    done
}

# 解析 URL 模板
_resolve_url() {
    local template="$1" tag="$2" repo="$3" version="$4" arch="$5"
    local url="$template"
    url="${url//\{tag\}/$tag}"
    url="${url//\{repo\}/$repo}"
    url="${url//\{version\}/$version}"
    url="${url//\{arch\}/$arch}"
    echo "$url"
}

# JSON manifest: 获取最新版本
_json_get_latest() {
    local manifest="$1"
    local repo source_type tag_strip version_cmd version_url

    repo=$(_json_get "$manifest" "repo")
    source_type=$(_json_get "$manifest" "source" "github")
    tag_strip=$(_json_get "$manifest" "tag_strip")
    version_cmd=$(_json_get "$manifest" "version_cmd")
    version_url=$(_json_get "$manifest" "version_url")

    if [ -n "$version_cmd" ]; then
        # 自定义命令获取版本
        eval "$version_cmd" 2>/dev/null || true
    elif [ "$source_type" = "github" ] && [ -n "$repo" ]; then
        local tag
        tag=$(github_latest "$repo")
        if [ -n "$tag" ] && [ -n "$tag_strip" ]; then
            tag="${tag#"$tag_strip"}"
        fi
        echo "$tag"
    elif [ "$source_type" = "custom" ] && [ -n "$version_url" ]; then
        _curl_opts
        curl "${_CURL_OPTS[@]}" "$version_url" 2>/dev/null || true
    fi
}

# JSON manifest: 执行 upgrade
_json_run_upgrade() {
    local manifest="$1"
    local name repo tag_strip arch_map format strip_mode binaries install_to hook

    name=$(_json_get "$manifest" "name")
    repo=$(_json_get "$manifest" "repo")
    tag_strip=$(_json_get "$manifest" "tag_strip")
    format=$(_json_get "$manifest" "format")
    strip_mode=$(_json_get "$manifest" "strip")
    install_to=$(_json_get "$manifest" "install_to")
    hook=$(_json_get "$manifest" "hook")

    # 如果有 hook，执行 shell hook
    if [ -n "$hook" ]; then
        local hook_file="$REGISTRY_DIR/$hook"
        if [ -f "$hook_file" ]; then
            (
                source "$hook_file"
                type upgrade &>/dev/null && upgrade
            )
            return $?
        fi
    fi

    # 声明式 upgrade
    local tag
    tag=$(_json_get_latest "$manifest")
    [ -z "$tag" ] && { err "无法获取 $name 最新版本"; return 1; }

    # arch 映射
    local target_arch
    target_arch=$(_json_get_arch "$manifest" "$ARCH")
    [ -z "$target_arch" ] && target_arch="$ARCH"

    # URL 模板
    local url_template
    url_template=$(_json_get "$manifest" "url")
    [ -z "$url_template" ] && { err "$name 无 URL 模板"; return 1; }

    local url
    url=$(_resolve_url "$url_template" "$tag" "$repo" "$tag" "$target_arch")

    # binaries
    binaries=$(jq -r '.binaries // [] | .[]' "$manifest" 2>/dev/null | tr '\n' ' ')

    # 安装目录
    local dest
    [ -n "$install_to" ] && dest=$(eval echo "$install_to") || dest="$TOOLS_DIR/$name"

    _log "下载" "$name"
    local tmp="$TMP_DIR/$name"
    mkdir -p "$dest" "$TMP_DIR"
    _curl_download_opts; curl "${_CURL_OPTS[@]}" -o "$tmp" "$url"
    _extract "$tmp" "$dest" "$format" "$strip_mode" "$(echo "$binaries" | awk '{print $1}')"
    rm -f "$tmp"

    # 链接二进制
    for bin in $binaries; do
        local src="$dest/$bin"
        [ -f "$src" ] && link_binary "$src" "$(basename "$bin")"
    done

    # 后置命令
    local post_install
    post_install=$(_json_get "$manifest" "post_install")
    [ -n "$post_install" ] && eval "$post_install" 2>/dev/null

    ok "$name"
}

# JSON manifest: 从本地文件安装
_json_install_from() {
    local manifest="$1" file="$2"
    local name format strip_mode binaries install_to hook

    name=$(_json_get "$manifest" "name")
    format=$(_json_get "$manifest" "format")
    strip_mode=$(_json_get "$manifest" "strip")
    install_to=$(_json_get "$manifest" "install_to")
    hook=$(_json_get "$manifest" "hook")

    # 如果有 hook，执行 shell hook
    if [ -n "$hook" ]; then
        local hook_file="$REGISTRY_DIR/$hook"
        if [ -f "$hook_file" ]; then
            (
                source "$hook_file"
                type install_from &>/dev/null && install_from "$file"
            )
            return $?
        fi
    fi

    # 声明式 install
    binaries=$(jq -r '.binaries // [] | .[]' "$manifest" 2>/dev/null | tr '\n' ' ')
    local dest
    [ -n "$install_to" ] && dest=$(eval echo "$install_to") || dest="$TOOLS_DIR/$name"
    mkdir -p "$dest"
    _extract "$file" "$dest" "$format" "$strip_mode" "$(echo "$binaries" | awk '{print $1}')"

    # 链接二进制
    for bin in $binaries; do
        local src="$dest/$bin"
        [ -f "$src" ] && link_binary "$src" "$(basename "$bin")"
    done

    # 后置命令
    local post_install
    post_install=$(_json_get "$manifest" "post_install")
    [ -n "$post_install" ] && eval "$post_install" 2>/dev/null

    return 0
}

# 获取最新版本（兼容 JSON 和 Shell）
get_latest_version() {
    local manifest="$1"
    case "$manifest" in
        *.json) _json_get_latest "$manifest" ;;
        *.sh)
            (
                source "$manifest"
                type get_latest &>/dev/null && get_latest
            )
            ;;
    esac
}

# 执行 upgrade（兼容 JSON 和 Shell）
run_upgrade() {
    local manifest="$1"
    case "$manifest" in
        *.json) _json_run_upgrade "$manifest" ;;
        *.sh)
            (
                source "$manifest"
                type upgrade &>/dev/null && upgrade
            )
            ;;
    esac
}

# 从文件安装（兼容 JSON 和 Shell）
run_install_from() {
    local manifest="$1" file="$2"
    case "$manifest" in
        *.json) _json_install_from "$manifest" "$file" ;;
        *.sh)
            (
                source "$manifest"
                type install_from &>/dev/null && install_from "$file"
            )
            ;;
    esac
}

# 单个工具安装函数（供并行调用）
_install_one_tool() {
    local tool="$1" manifest_file="$2" downloads="$3" registry_dir="$4"

    # 读取该工具的所有文件
    local files=""
    while IFS='|' read -r tname tver tfile; do
        [ -z "$tname" ] && continue
        [ "$tname" != "$tool" ] && continue
        if [ -z "$tfile" ]; then
            files="${files:+$files }$tver"
        else
            files="${files:+$files }$tfile"
        fi
    done < "$manifest_file"

    if [ -z "$files" ]; then
        echo "skip"
        return
    fi

    # 增量：目录存在且版本一致则跳过
    if [ -d "$FORGE_HOME/tools/$tool" ] || [ -d "$FORGE_HOME/runtimes/$tool" ]; then
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
                echo "skip"
                return
            fi
        fi
    fi

    # 查找 registry manifest
    local mfile=""
    mfile=$(find_manifest "$tool")

    if [ -z "$mfile" ]; then
        echo "skip"
        return
    fi

    # 检查是否有 install_from
    case "$mfile" in
        *.json)
            local hook
            hook=$(_json_get "$mfile" "hook")
            if [ -n "$hook" ]; then
                local hook_file="$registry_dir/$hook"
                if [ ! -f "$hook_file" ] || ! grep -q '^install_from()' "$hook_file" 2>/dev/null; then
                    echo "skip"
                    return
                fi
            fi
            ;;
        *.sh)
            if ! grep -q '^install_from()' "$mfile" 2>/dev/null; then
                echo "skip"
                return
            fi
            ;;
    esac

    # 执行安装
    for fname in $files; do
        local fpath="$downloads/$fname"
        if [ -f "$fpath" ]; then
            if run_install_from "$mfile" "$fpath"; then
                # 更新版本锁
                local dl_ver
                dl_ver=$(grep "^${tool}|" "$manifest_file" 2>/dev/null | tail -1 | cut -d'|' -f2)
                [ -n "$dl_ver" ] && set_installed "$tool" "$dl_ver"
                echo "ok"
                return
            else
                echo "fail"
                return
            fi
        else
            echo "fail"
            return
        fi
    done

    echo "skip"
}

set_installed() {
    mkdir -p "$(dirname "$LOCK_FILE")"
    if [ -f "$LOCK_FILE" ] && grep -q "^${1}|" "$LOCK_FILE" 2>/dev/null; then
        sed -i.bak "s#^${1}|.*#${1}|${2}|$(date +%Y-%m-%d)#" "$LOCK_FILE"
        rm -f "$LOCK_FILE.bak"
    else
        echo "${1}|${2}|$(date +%Y-%m-%d)" >> "$LOCK_FILE"
    fi
}

get_downloaded() {
    local manifest="$_ROOT/download/download.manifest"
    [ -f "$manifest" ] && grep "^${1}|" "$manifest" 2>/dev/null | tail -1 | cut -d'|' -f2 || true
}

get_latest_cached() {
    local manifest="$_ROOT/download/update.manifest"
    [ -f "$manifest" ] && grep "^${1}|" "$manifest" 2>/dev/null | tail -1 | cut -d'|' -f2 || true
}

# 获取并行数
_parallel_count() {
    local n
    n=$(sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4)
    [ "$n" -gt 8 ] && n=8
    echo "$n"
}

# 并行执行任务
# 用法: _parallel_run <item1> <item2> ... -- <function_name> [args...]
# function_name 会被每个 item 调用，返回 ok/skip/fail
_parallel_run() {
    local -a items=()
    local func=""

    # 解析参数
    while [ $# -gt 0 ]; do
        case "$1" in
            --) shift; func="$1"; shift; items+=("${@}") ; break ;;
            *)  items+=("$1"); shift ;;
        esac
    done

    [ ${#items[@]} -eq 0 ] && return 0
    [ -z "$func" ] && return 1

    local n
    n=$(_parallel_count)
    local result_file
    mkdir -p "$TMP_DIR"
    result_file=$(mktemp "${TMP_DIR}/.parallel_result_XXXXXX")

    printf '%s\n' "${items[@]}" | \
        xargs -P "$n" -I {} bash -c "
            source '$ROOT_DIR/shell/forge/common.sh'
            result=\$($func '{}')
            echo \"\$result\" >> '$result_file'
        "

    # 统计结果
    local ok=0 skip=0 fail=0
    if [ -f "$result_file" ]; then
        ok=$(grep -c "^ok$" "$result_file" 2>/dev/null || echo 0)
        skip=$(grep -c "^skip$" "$result_file" 2>/dev/null || echo 0)
        fail=$(grep -c "^fail$" "$result_file" 2>/dev/null || echo 0)
        rm -f "$result_file"
    fi

    echo "$ok $skip $fail"
}

# 计算字符串显示宽度（CJK=2, ASCII=1, 忽略 ANSI 颜色码）
_dw() {
    local clean
    clean=$(printf '%b' "$1" | sed $'s/\033\\[[0-9;]*m//g')
    local w=0 c
    for ((i=0; i<${#clean}; i++)); do
        c="${clean:$i:1}"
        case "$c" in
            [a-zA-Z0-9_.~-]) ((w++)) || true ;;
            " "|\!) ((w++)) || true ;;
            *) ((w+=2)) || true ;;
        esac
    done
    echo "$w"
}

# 带 ANSI 颜色的安全填充（基于显示宽度）
_pad() {
    local text="$1" width="$2"
    local vis
    vis=$(_dw "$text")
    local pad=$((width - vis))
    [ $pad -lt 0 ] && pad=0
    printf '%b' "$text"
    printf '%'"${pad}"'s' ""
}

print_header() {
    local widths=(20 12 12 10 6)
    echo ""
    local i=0
    for arg in "$@"; do
        _pad "${BOLD}${arg}${NC}" "${widths[$i]:-12}"
        ((i++)) || true
    done
    echo ""
    i=0
    for arg in "$@"; do
        local w=${widths[$i]:-12}
        printf '%.0s─' $(seq 1 "$w")
        ((i++)) || true
    done
    echo ""
}
