#!/bin/bash

# 自动编译 maixcam 和 maixcam2 平台并打包
# 使用方法: 
#   批量编译(默认): ./build_and_pack.sh [projects目录路径]
#   单项目编译:     ./build_and_pack.sh --single [项目路径]

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印带颜色的信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

title() {
    echo -e "${BLUE}[====]${NC} $1"
}

# 查找 release 目录
find_release_dir() {
    local dist_dir=$1
    local release_dir=$(find "$dist_dir" -maxdepth 1 -type d -name "*_release" | head -n 1)
    if [ -n "$release_dir" ]; then
        echo "$release_dir"
    else
        echo ""
    fi
}

# 从 release 目录名提取二进制文件名
get_binary_name() {
    local release_dir=$1
    local dir_name=$(basename "$release_dir")
    echo "${dir_name%_release}"
}

# 编译并复制
build_platform() {
    local project_path=$1
    local platform=$2
    local is_first=$3
    local output_dir=$4
    local dist_dir="$project_path/dist"
    
    info "开始编译平台: $platform"
    
    cd "$project_path"
    
    # 使用 echo 自动选择平台进行编译
    if [ "$platform" == "maixcam" ]; then
        echo "2" | maixcdk build
    elif [ "$platform" == "maixcam2" ]; then
        echo "3" | maixcdk build
    else
        error "未知平台: $platform"
        return 1
    fi
    
    # 自动查找 release 目录
    local release_dir=$(find_release_dir "$dist_dir")
    
    if [ -z "$release_dir" ] || [ ! -d "$release_dir" ]; then
        error "编译失败，未找到 *_release 目录"
        ls -la "$dist_dir"
        return 1
    fi
    
    local binary_name=$(get_binary_name "$release_dir")
    
    info "找到 release 目录: $release_dir"
    
    # 只复制二进制文件和 dl_lib 到平台目录
    mkdir -p "$output_dir/$platform"
    cp "$release_dir/$binary_name" "$output_dir/$platform/"
    if [ -d "$release_dir/dl_lib" ]; then
        cp -r "$release_dir/dl_lib" "$output_dir/$platform/"
    fi
    
    # 第一次编译时复制共享文件到根目录
    if [ "$is_first" == "true" ]; then
        info "复制共享文件..."
        [ -d "$release_dir/assets" ] && cp -r "$release_dir/assets" "$output_dir/"
        [ -f "$release_dir/app.yaml" ] && cp "$release_dir/app.yaml" "$output_dir/"
        [ -f "$release_dir/README.md" ] && cp "$release_dir/README.md" "$output_dir/"
        [ -f "$release_dir/README_EN.md" ] && cp "$release_dir/README_EN.md" "$output_dir/"
        echo "$binary_name" > "$output_dir/.binary_name"
    fi
    
    info "清理编译缓存..."
    maixcdk distclean
    
    info "平台 $platform 编译完成"
}

# 创建 main.py
create_main_py() {
    local output_dir=$1
    local binary_name=$2
    cat > "$output_dir/main.py" << 'EOF'
from maix import sys
import subprocess

device_name = sys.device_name().lower()

if device_name == 'maixcam2':
    subprocess.run(['chmod', '+x', 'maixcam2/BINARY_NAME'])
    ret = subprocess.run(['maixcam2/BINARY_NAME'])
    if ret.returncode != 0:
        raise RuntimeError(f'Run BINARY_NAME failed! ret:{ret.returncode}')
else:
    subprocess.run(['chmod', '+x', 'maixcam/BINARY_NAME'])
    ret = subprocess.run(['maixcam/BINARY_NAME'])
    if ret.returncode != 0:
        raise RuntimeError(f'Run BINARY_NAME failed! ret:{ret.returncode}')
EOF
    sed -i "s/BINARY_NAME/$binary_name/g" "$output_dir/main.py"
}

# 编译单个项目
build_single_project() {
    local project_path=$1
    local output_zip_dir=$2  # 可选，指定zip输出目录
    
    local project_name=$(basename "$project_path")
    local output_dir="$project_path/release_all"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local zip_name="${project_name}_release_${timestamp}.zip"
    
    title "编译项目: $project_name"
    info "项目路径: $project_path"
    
    # 清理之前的输出
    [ -d "$output_dir" ] && rm -rf "$output_dir"
    mkdir -p "$output_dir"
    
    # 编译两个平台
    build_platform "$project_path" "maixcam" "true" "$output_dir"
    build_platform "$project_path" "maixcam2" "false" "$output_dir"
    
    # 获取二进制文件名并创建 main.py
    local binary_name=$(cat "$output_dir/.binary_name")
    rm -f "$output_dir/.binary_name"
    create_main_py "$output_dir" "$binary_name"
    
    # 重命名为 app 名称
    local app_dir="$project_path/$binary_name"
    mv "$output_dir" "$app_dir"
    
    # 打包
    info "打包中..."
    cd "$project_path"
    zip -rq "$zip_name" "$binary_name"
    
    # 清理临时目录
    rm -rf "$app_dir"
    
    # 如果指定了输出目录，移动zip
    if [ -n "$output_zip_dir" ]; then
        mv "$zip_name" "$output_zip_dir/"
        info "输出文件: $output_zip_dir/$zip_name"
    else
        info "输出文件: $project_path/$zip_name"
    fi
    
    echo ""
}

# 批量编译所有项目
build_all_projects() {
    local projects_dir=$1
    local build_dir="$projects_dir/build"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    
    title "========================================="
    title "批量编译模式"
    title "Projects 目录: $projects_dir"
    title "========================================="
    echo ""
    
    # 创建 build 目录
    mkdir -p "$build_dir"
    info "输出目录: $build_dir"
    echo ""
    
    # 统计
    local total=0
    local success=0
    local failed=0
    local failed_list=""
    
    # 遍历所有子目录
    for project in "$projects_dir"/*/; do
        # 跳过 build 目录
        if [ "$(basename "$project")" == "build" ]; then
            continue
        fi
        
        # 检查是否是有效项目（包含 app.yaml 或 CMakeLists.txt）
        if [ ! -f "$project/app.yaml" ] && [ ! -f "$project/CMakeLists.txt" ]; then
            warn "跳过非项目目录: $project"
            continue
        fi
        
        total=$((total + 1))
        project_path="${project%/}"  # 去掉末尾斜杠
        
        # 编译项目（捕获错误继续）
        if build_single_project "$project_path" "$build_dir"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
            failed_list="$failed_list\n  - $(basename "$project_path")"
            error "项目 $(basename "$project_path") 编译失败，继续下一个..."
        fi
    done
    
    # 输出统计
    echo ""
    title "========================================="
    title "批量编译完成!"
    title "========================================="
    info "总计: $total 个项目"
    info "成功: $success 个"
    if [ $failed -gt 0 ]; then
        error "失败: $failed 个"
        echo -e "失败项目:$failed_list"
    fi
    info "输出目录: $build_dir"
    echo ""
    ls -la "$build_dir"
}

# 主入口
main() {
    if [ "$1" == "--single" ] || [ "$1" == "-s" ]; then
        # 单项目编译模式
        local project_path="${2:-$(pwd)}"
        if [ ! -d "$project_path" ]; then
            error "目录不存在: $project_path"
            exit 1
        fi
        build_single_project "$project_path"
    else
        # 默认：批量编译模式
        local projects_dir="${1:-$(pwd)}"
        if [ ! -d "$projects_dir" ]; then
            error "目录不存在: $projects_dir"
            exit 1
        fi
        build_all_projects "$projects_dir"
    fi
}

# 显示帮助
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "使用方法:"
    echo "  批量编译(默认): $0 [projects目录路径]"
    echo "  单项目编译:     $0 --single [项目路径]"
    echo ""
    echo "示例:"
    echo "  $0                                          # 批量编译当前目录下所有项目"
    echo "  $0 /root/MaixCDK/projects                   # 批量编译指定目录下所有项目"
    echo "  $0 --single                                 # 编译当前目录项目"
    echo "  $0 --single /root/MaixCDK/projects/app_camera  # 编译指定项目"
    exit 0
fi

main "$@"