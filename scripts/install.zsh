#!/bin/zsh
# Build reviewed source locally and install it. No downloads, credentials, or sudo.
set -euo pipefail

project_dir=${0:A:h:h}
app_name='保持清醒.app'
expected_bundle='org.keepawake.macos'
install_dir="$HOME/Applications"
launch_after_install=false

fail() {
    print -u2 -- "错误：$*"
    exit 1
}

while (( $# > 0 )); do
    case "$1" in
        --destination)
            (( $# >= 2 )) || fail '--destination 后需要一个目标文件夹。'
            install_dir=$2
            shift 2
            ;;
        --launch)
            launch_after_install=true
            shift
            ;;
        --help|-h)
            print -- '用法：./scripts/install.zsh [--launch] [--destination 文件夹]'
            print -- '默认安装到 ~/Applications；可用 --launch 在安装后打开。'
            print -- '不会覆盖同名但 bundle identifier 不同的应用。'
            exit 0
            ;;
        *) fail "未知参数：$1" ;;
    esac
done

[[ $(uname -s) == Darwin ]] || fail '这个安装脚本只能在 Mac 上运行。'
[[ $EUID != 0 ]] || fail '请用当前用户运行，不需要 sudo。'
if ! /usr/bin/xcode-select -p >/dev/null 2>&1 || ! /usr/bin/xcrun --find swiftc >/dev/null 2>&1; then
    fail '未找到 Apple Swift 编译工具。请先由本人安装 Xcode 或 Command Line Tools（xcode-select --install），安装完成后重试；脚本不会自动下载安装。'
fi
install_dir=${install_dir:A}
target_app="$install_dir/$app_name"

# Decide before building. A pre-existing app with a different identity is never touched.
check_existing_target() {
    [[ ! -L $target_app ]] || fail '目标位置是符号链接，已停止且未改动。'
    if [[ -e $target_app ]]; then
        [[ -d $target_app && -f "$target_app/Contents/Info.plist" ]] || fail '目标位置已有非应用文件，已停止且未改动。'
        local bundle
        bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$target_app/Contents/Info.plist" 2>/dev/null) \
            || fail '无法验证已有应用的身份，已停止且未改动。'
        [[ $bundle == $expected_bundle ]] \
            || fail '已有同名应用属于其他 bundle identifier，已停止且未覆盖。可用 --destination 选择另一个文件夹，或先自行处理旧应用。'
    fi
}
check_existing_target

"$project_dir/scripts/build.sh"
local_app="$project_dir/build/local/$app_name"
"$project_dir/scripts/verify-app.sh" --local "$local_app"
mkdir -p "$install_dir"
staging_dir=$(mktemp -d "$install_dir/.keep-awake-install.XXXXXX")
trap 'rm -rf "$staging_dir"' EXIT
/usr/bin/ditto "$local_app" "$staging_dir/$app_name"
"$project_dir/scripts/verify-app.sh" --local "$staging_dir/$app_name"
check_existing_target

backup_app=''
if [[ -e $target_app ]]; then
    mkdir -p "$install_dir/.keep-awake-backups"
    backup_dir=$(mktemp -d "$install_dir/.keep-awake-backups/previous.XXXXXX")
    backup_app="$backup_dir/$app_name"
    mv "$target_app" "$backup_app"
fi
if ! mv "$staging_dir/$app_name" "$target_app"; then
    if [[ -n $backup_app && ! -e $target_app ]]; then
        mv "$backup_app" "$target_app" || fail '安装和还原都失败；旧版仍保存在目标文件夹的 .keep-awake-backups 中。'
    fi
    fail '安装失败，已还原旧版（如有）。'
fi
print -- '安装完成：保持清醒.app（Apple silicon + Intel，本机编译）。'
[[ -z $backup_app ]] || print -- '同一项目的旧版已保存在目标文件夹的 .keep-awake-backups 中。'
if $launch_after_install; then
    /usr/bin/open "$target_app"
else
    print -- '尚未启动；在目标文件夹中双击应用即可。'
fi
