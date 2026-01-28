#!/bin/bash

# 自动编译 maixcam 和 maixcam2 平台并打包
# 使用方法: ./build_and_pack.sh [项目路径]

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# 获取项目路径
if [ -n "$1" ]; then
    PROJECT_PATH="$1"
else
    PROJECT_PATH="$(pwd)"
fi

# 进入项目目录
cd "$PROJECT_PATH"
info "项目路径: $PROJECT_PATH"

# 获取项目名称（从目录名提取）
PROJECT_NAME=$(basename "$PROJECT_PATH")
info "项目名称: $PROJECT_NAME"

# 定义目录
DIST_DIR="$PROJECT_PATH/dist"
OUTPUT_DIR="$PROJECT_PATH/release_all"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ZIP_NAME="${PROJECT_NAME}_release_${TIMESTAMP}.zip"

# 查找 release 目录
find_release_dir() {
    local release_dir=$(find "$DIST_DIR" -maxdepth 1 -type d -name "*_release" | head -n 1)
    if [ -n "$release_dir" ]; then
        echo "$release_dir"
    else
        echo ""
    fi
}

# 从 release 目录名提取二进制文件名（如 camera_release -> camera）
get_binary_name() {
    local release_dir=$1
    local dir_name=$(basename "$release_dir")
    echo "${dir_name%_release}"
}

# 编译并复制
build_platform() {
    local platform=$1
    local is_first=$2
    
    info "========================================="
    info "开始编译平台: $platform"
    info "========================================="
    
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
    local release_dir=$(find_release_dir)
    
    if [ -z "$release_dir" ] || [ ! -d "$release_dir" ]; then
        error "编译失败，未找到 *_release 目录"
        ls -la "$DIST_DIR"
        return 1
    fi
    
    local binary_name=$(get_binary_name "$release_dir")
    
    info "找到 release 目录: $release_dir"
    info "二进制文件名: $binary_name"
    info "编译成功，复制文件..."
    
    # 只复制二进制文件和 dl_lib 到平台目录
    mkdir -p "$OUTPUT_DIR/$platform"
    cp "$release_dir/$binary_name" "$OUTPUT_DIR/$platform/"
    if [ -d "$release_dir/dl_lib" ]; then
        cp -r "$release_dir/dl_lib" "$OUTPUT_DIR/$platform/"
    fi
    
    # 第一次编译时复制共享文件到根目录，并保存二进制名
    if [ "$is_first" == "true" ]; then
        info "复制共享文件..."
        [ -d "$release_dir/assets" ] && cp -r "$release_dir/assets" "$OUTPUT_DIR/"
        [ -f "$release_dir/app.yaml" ] && cp "$release_dir/app.yaml" "$OUTPUT_DIR/"
        [ -f "$release_dir/README.md" ] && cp "$release_dir/README.md" "$OUTPUT_DIR/"
        [ -f "$release_dir/README_EN.md" ] && cp "$release_dir/README_EN.md" "$OUTPUT_DIR/"
        # 保存二进制名供后续使用
        echo "$binary_name" > "$OUTPUT_DIR/.binary_name"
    fi
    
    info "清理编译缓存..."
    maixcdk distclean
    
    info "平台 $platform 编译完成"
    echo ""
}

# 创建 main.py
create_main_py() {
    local binary_name=$1
    cat > "$OUTPUT_DIR/main.py" << 'EOF'
from maix import sys
import subprocess

device_name = sys.device_name().lower()

if device_name == 'maixcam2':
    ret = subprocess.run(['maixcam2/BINARY_NAME'])
    if ret.returncode != 0:
        raise RuntimeError(f'Run BINARY_NAME failed! ret:{ret.returncode}')
else:
    ret = subprocess.run(['maixcam/BINARY_NAME'])
    if ret.returncode != 0:
        raise RuntimeError(f'Run BINARY_NAME failed! ret:{ret.returncode}')
EOF
    # 替换二进制文件名
    sed -i "s/BINARY_NAME/$binary_name/g" "$OUTPUT_DIR/main.py"
    info "已创建 main.py"
}

# 主流程
main() {
    info "开始自动编译流程"
    info "时间戳: $TIMESTAMP"
    echo ""
    
    # 清理之前的输出
    if [ -d "$OUTPUT_DIR" ]; then
        warn "清理之前的输出目录..."
        rm -rf "$OUTPUT_DIR"
    fi
    mkdir -p "$OUTPUT_DIR"
    
    # 编译 maixcam（第一次，复制共享文件）
    build_platform "maixcam" "true"
    
    # 编译 maixcam2
    build_platform "maixcam2" "false"
    
    # 获取二进制文件名
    local binary_name=$(cat "$OUTPUT_DIR/.binary_name")
    rm -f "$OUTPUT_DIR/.binary_name"
    info "二进制文件名: $binary_name"
    
    # 创建 main.py
    create_main_py "$binary_name"
    
    # 重命名为 app 名称（使用二进制名）
    local app_dir="$PROJECT_PATH/$binary_name"
    mv "$OUTPUT_DIR" "$app_dir"
    
    # 打包
    info "========================================="
    info "开始打包..."
    info "========================================="
    
    cd "$PROJECT_PATH"
    zip -r "$ZIP_NAME" "$binary_name"
    
    info "打包完成: $PROJECT_PATH/$ZIP_NAME"
    
    # 显示打包内容
    info "打包内容:"
    unzip -l "$ZIP_NAME"
    
    # 清理临时目录
    rm -rf "$app_dir"
    
    echo ""
    info "========================================="
    info "全部完成!"
    info "输出文件: $PROJECT_PATH/$ZIP_NAME"
    info "========================================="
}

# 运行主流程
main