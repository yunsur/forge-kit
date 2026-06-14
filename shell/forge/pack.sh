#!/usr/bin/env bash
# shellcheck disable=SC2155
# 命令: pack

cmd_pack() {
    local target="${1:-full}"
    local out="forge_$(date +%Y%m%d%H).tgz"
    local staging
    staging=$(mktemp -d)
    local dest="$staging/forge"
    mkdir -p "$dest"

    case "$target" in
        full|*)
            # 全量打包（所有内容）
            echo -e "${B}[打包]${NC} $out"
            # 复制 download/（下载的压缩包和 git 工具）
            if [ -d "$_ROOT/download" ]; then
                cp -r "$_ROOT/download" "$dest/"
            fi
            # 项目文件（shell/ 已包含 env.sh 和 forge 模块）
            for d in shell registry; do
                [ -d "$_ROOT/$d" ] && cp -r "$_ROOT/$d" "$dest/"
            done
            [ -f "$_ROOT/forge" ] && cp "$_ROOT/forge" "$dest/"
            ;;
    esac
    # 去除 macOS 特殊文件
    find "$staging" -name '.DS_Store' -delete 2>/dev/null
    find "$staging" -name '._*' -delete 2>/dev/null
    find "$staging" -name '__MACOSX' -type d -exec rm -rf {} + 2>/dev/null
    # 打包（只含 forge/ 目录，COPYFILE_DISABLE 阻止 macOS xattr 写入）
    COPYFILE_DISABLE=1 tar -czf "$out" -C "$staging" forge/
    rm -rf "$staging"
    local size
    size=$(du -h "$out" | cut -f1)
    md5 -q "$out" > "${out}.md5"
    echo -e "${G}[完成]${NC} $out ($size)"
    echo -e "${D}校验: md5 -c $(basename "${out}.md5")${NC}"
    echo -e "${D}目标机器: tar xzf $(basename "$out") && cd forge && ./forge init${NC}"
}
