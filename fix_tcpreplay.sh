#!/bin/bash

# ImmortalWRT tcpreplay 依赖修复脚本
# 用于修复 tcpbridge 缺少 libbpf 依赖的问题
# 使用方法: ./fix_tcpreplay_deps.sh

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否在正确的目录
check_directory() {
    if [ ! -f "feeds.conf.default" ] || [ ! -d "package" ]; then
        print_error "请在 ImmortalWRT 源码根目录下运行此脚本!"
        exit 1
    fi
    print_info "检测到 ImmortalWRT 源码目录"
}

# 备份原始文件
backup_file() {
    local file=$1
    if [ -f "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$file" "$backup"
        print_info "已备份: $backup"
    fi
}

# 修复 tcpreplay Makefile
fix_tcpreplay_makefile() {
    local makefile="feeds/packages/net/tcpreplay/Makefile"
    
    if [ ! -f "$makefile" ]; then
        print_error "未找到 $makefile"
        print_warn "请先运行: ./scripts/feeds update -a && ./scripts/feeds install -a"
        exit 1
    fi
    
    print_info "检查 $makefile..."
    
    # 检查是否已经添加了 libbpf 依赖
    if grep -q "+libbpf" "$makefile"; then
        print_info "依赖已修复,无需重复操作"
        return 0
    fi
    
    # 备份原始文件
    backup_file "$makefile"
    
    # 查找 DEPENDS 行并添加 +libbpf
    if grep -q "DEPENDS:=.*+libpcap" "$makefile"; then
        # 方法1: 如果有 libpcap,在其后添加
        sed -i 's/\(DEPENDS:=.*+libpcap\)/\1 +libbpf/' "$makefile"
        print_info "已在 libpcap 后添加 +libbpf 依赖"
    elif grep -q "DEPENDS:=" "$makefile"; then
        # 方法2: 如果有 DEPENDS 行但没有 libpcap
        sed -i 's/\(DEPENDS:=\)\(.*\)/\1\2 +libbpf/' "$makefile"
        print_info "已添加 +libbpf 依赖"
    else
        # 方法3: 如果没有 DEPENDS 行,在 PKG_NAME 后添加
        sed -i '/^PKG_NAME:=/a DEPENDS:=+libbpf' "$makefile"
        print_info "已创建 DEPENDS 行并添加 +libbpf"
    fi
    
    # 验证修改
    if grep -q "+libbpf" "$makefile"; then
        print_info "✓ 修复成功!"
        print_info "修改后的 DEPENDS 行:"
        grep "DEPENDS:=" "$makefile" | head -1
    else
        print_error "✗ 修复失败,请手动检查"
        exit 1
    fi
}

# 检查 libbpf 包是否可用
check_libbpf() {
    print_info "检查 libbpf 包..."
    
    if [ -d "feeds/packages/libs/libbpf" ]; then
        print_info "✓ libbpf 包存在"
    else
        print_warn "未找到 libbpf 包,尝试更新 feeds..."
        ./scripts/feeds update packages
        ./scripts/feeds install libbpf
    fi
}

# 清理之前的编译
clean_tcpreplay() {
    print_info "清理 tcpreplay 之前的编译..."
    make package/tcpreplay/clean > /dev/null 2>&1 || true
    print_info "✓ 清理完成"
}

# 显示后续步骤
show_next_steps() {
    echo ""
    print_info "========================================"
    print_info "修复完成! 后续步骤:"
    echo ""
    echo "  1. 配置编译选项:"
    echo "     make menuconfig"
    echo ""
    echo "  2. 确保在 menuconfig 中选中:"
    echo "     Libraries -> libbpf"
    echo "     Network -> tcpreplay (如果需要)"
    echo ""
    echo "  3. 开始编译:"
    echo "     make download -j8"
    echo "     make -j\$(nproc) V=s"
    echo ""
    echo "  或单独编译 tcpreplay 验证:"
    echo "     make package/tcpreplay/compile V=s"
    print_info "========================================"
}

# 主函数
main() {
    print_info "开始修复 tcpreplay 依赖问题..."
    echo ""
    
    check_directory
    check_libbpf
    fix_tcpreplay_makefile
    clean_tcpreplay
    
    echo ""
    print_info "✓ 所有修复操作完成!"
    show_next_steps
}

# 运行主函数
main