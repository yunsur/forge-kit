#!/usr/bin/env bash
# 帮助信息

show_help() {
    cat << 'EOF'

forge - AI 工具版本管理器

用法:
  forge                                    检查并提示更新
  forge -a                                 检查并更新全部

  forge list                               显示所有工具状态
  forge update                             仅检查可用更新
  forge download [--force]                 只下载不解压（--force 强制重新下载）
  forge install [tool...]                  安装环境无关工具（解压+链接，无需运行时）
  forge start                              加载工作站环境（source ~/forge/env.sh）
  forge init                               初始化环境依赖工具+链接+npm包
  forge init tools                         仅安装环境依赖工具
  forge init bins                          仅链接二进制
  forge init npm                           仅安装 npm 全局包（config/npm-packages.txt）
  forge uninstall                          卸载指定工具
  forge info <tool>                        显示工具详情

  forge bundle install [Brewfile]          从清单批量安装
  forge bundle dump                        导出已安装工具到 Brewfile
  forge cleanup                            清理旧版本下载文件
  forge pack                               打包用于迁移

  forge doctor                             环境检查

EOF
}
