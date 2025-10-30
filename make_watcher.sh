#!/bin/bash

#############################################
# ImmortalWRT 智能编译监测脚本
# 功能：编译进度监测、错误分析、包管理
#############################################

set -e

# ==================== 配置区 ====================

# OpenAI API 配置
OPENAI_API_KEY="${OPENAI_API_KEY:-}"
OPENAI_API_URL="${OPENAI_API_URL:-https://api.openai.com/v1/chat/completions}"
OPENAI_MODEL="${OPENAI_MODEL:-gpt-4}"

# 错误日志配置
ERROR_CONTEXT_LINES="${ERROR_CONTEXT_LINES:-50}"  # 错误上下文行数

# 默认提示词（英文，要求AI用中文回复）
DEFAULT_PROMPT="You are an expert in OpenWRT/ImmortalWRT compilation and troubleshooting. Analyze the following compilation error and system information, then provide:
1. Root cause analysis of the error
2. Specific solutions or fixes
3. Relevant commands or configuration changes needed

Please respond in Chinese (简体中文).

System Information:
{SYSTEM_INFO}

Error Log:
{ERROR_LOG}

Provide a clear, actionable analysis."

CUSTOM_PROMPT="${CUSTOM_PROMPT:-$DEFAULT_PROMPT}"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ==================== 工具函数 ====================

# 检测 WSL2 环境
detect_wsl2() {
    if grep -qEi "(Microsoft|WSL)" /proc/version &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# 配置 WSL2 环境
configure_wsl2_environment() {
    print_header "WSL2 环境配置"
    
    print_info "检测到 WSL2 环境，正在配置编译环境..."
    
    # 保存原始 PATH
    export ORIGINAL_PATH="$PATH"
    
    # 设置适合 OpenWRT 编译的 PATH
    export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
    
    print_success "PATH 已临时修改为: $PATH"
    print_info "原始 PATH 已保存，脚本结束后将恢复"
    
    # 检查 Windows 路径污染
    if echo "$ORIGINAL_PATH" | grep -q "/mnt/c"; then
        print_warning "检测到 Windows 路径混入，已清理"
    fi
    
    # WSL2 特殊配置建议
    echo ""
    print_info "WSL2 编译建议："
    echo "  - 确保源码在 Linux 文件系统（如 ~/immortalwrt）而非 /mnt/c/"
    echo "  - WSL2 磁盘空间可能有限，建议至少预留 50GB"
    echo "  - 可以使用 'df -h ~' 检查可用空间"
    
    # 检查文件系统类型
    local fs_type=$(df -T . | tail -1 | awk '{print $2}')
    if [ "$fs_type" != "ext4" ] && [ "$fs_type" != "ext3" ]; then
        print_warning "当前目录文件系统为 $fs_type"
        print_warning "强烈建议在 ext4 文件系统上编译（如 ~/immortalwrt）"
        echo -n "是否继续？(y/N): "
        read -r continue_anyway
        if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
            print_error "已取消编译"
            exit 1
        fi
    fi
    
    echo ""
}

# 恢复原始环境
restore_environment() {
    if [ -n "$ORIGINAL_PATH" ]; then
        export PATH="$ORIGINAL_PATH"
        print_info "环境变量已恢复"
    fi
}

print_header() {
    echo -e "${CYAN}${BOLD}========================================${NC}"
    echo -e "${CYAN}${BOLD}$1${NC}"
    echo -e "${CYAN}${BOLD}========================================${NC}"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检测系统信息
detect_system_info() {
    print_header "系统信息检测"
    
    local cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    local cpu_cores=$(nproc)
    local total_mem=$(free -h | awk '/^Mem:/ {print $2}')
    local available_mem=$(free -h | awk '/^Mem:/ {print $7}')
    local disk_space=$(df -h . | awk 'NR==2 {print $4}')
    local os_info=$(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)
    local gcc_version=$(gcc --version 2>/dev/null | head -1 || echo "未安装")
    
    # WSL2 检测
    local is_wsl2="否"
    if detect_wsl2; then
        is_wsl2="是 (WSL2)"
        local wsl_version=$(cat /proc/version | grep -oP "WSL\d+" || echo "WSL2")
    fi
    
    echo -e "${BOLD}运行环境:${NC} $is_wsl2"
    echo -e "${BOLD}CPU:${NC} $cpu_model"
    echo -e "${BOLD}核心数:${NC} $cpu_cores"
    echo -e "${BOLD}总内存:${NC} $total_mem"
    echo -e "${BOLD}可用内存:${NC} $available_mem"
    echo -e "${BOLD}剩余磁盘空间:${NC} $disk_space"
    echo -e "${BOLD}操作系统:${NC} $os_info"
    echo -e "${BOLD}GCC版本:${NC} $gcc_version"
    
    # 显示文件系统类型（WSL2 重要）
    if detect_wsl2; then
        local fs_type=$(df -T . | tail -1 | awk '{print $2}')
        local current_path=$(pwd)
        echo -e "${BOLD}文件系统:${NC} $fs_type"
        echo -e "${BOLD}当前路径:${NC} $current_path"
        
        # 警告检查
        if [[ "$current_path" == /mnt/* ]]; then
            print_warning "当前在 Windows 文件系统，编译速度会很慢！"
        fi
    fi
    
    echo ""
    
    # 保存系统信息用于错误分析
    SYSTEM_INFO="Environment: $is_wsl2
CPU: $cpu_model ($cpu_cores cores)
Memory: $total_mem (Available: $available_mem)
Disk Space: $disk_space
OS: $os_info
GCC: $gcc_version"
    
    if detect_wsl2; then
        local fs_type=$(df -T . | tail -1 | awk '{print $2}')
        SYSTEM_INFO="$SYSTEM_INFO
Filesystem: $fs_type
Path: $(pwd)"
    fi
    
    echo "$cpu_cores"
}

# 检测已配置的包
detect_packages() {
    print_header "软件包状态检测"
    
    if [ ! -f ".config" ]; then
        print_error "未找到 .config 文件，请先运行 make menuconfig"
        exit 1
    fi
    
    print_info "正在分析已选择的软件包..."
    
    # 获取所有选中的包
    local selected_packages=$(grep "=y\|=m" .config | grep -v "^#" | grep "CONFIG_PACKAGE" | wc -l)
    
    # 检测已编译的包
    local compiled_packages=0
    local uncompiled_list=()
    
    while IFS= read -r line; do
        if [[ $line =~ CONFIG_PACKAGE_([^=]+)= ]]; then
            local pkg_name="${BASH_REMATCH[1]}"
            # 简化检查：查看是否存在对应的 ipk 文件
            if find bin/packages -name "${pkg_name}_*.ipk" 2>/dev/null | grep -q .; then
                ((compiled_packages++))
            else
                uncompiled_list+=("$pkg_name")
            fi
        fi
    done < <(grep "=y\|=m" .config | grep -v "^#" | grep "CONFIG_PACKAGE")
    
    local uncompiled_count=${#uncompiled_list[@]}
    
    echo -e "${BOLD}已选择软件包总数:${NC} $selected_packages"
    echo -e "${GREEN}${BOLD}已编译:${NC} $compiled_packages"
    echo -e "${YELLOW}${BOLD}未编译:${NC} $uncompiled_count"
    echo ""
    
    # 返回未编译的包列表
    printf '%s\n' "${uncompiled_list[@]}"
}

# 交互选择线程数
select_thread_count() {
    local max_threads=$1
    local default_threads=$max_threads
    
    echo -e "${BOLD}请选择编译线程数 (1-${max_threads}):${NC}"
    echo -e "  ${GREEN}推荐:${NC} $default_threads (最大值)"
    echo -e "  ${YELLOW}提示:${NC} 使用更少线程可降低系统负载"
    echo -n "请输入 [默认: $default_threads]: "
    
    read -r user_input
    
    if [ -z "$user_input" ]; then
        echo "$default_threads"
    elif [[ "$user_input" =~ ^[0-9]+$ ]] && [ "$user_input" -ge 1 ] && [ "$user_input" -le "$max_threads" ]; then
        echo "$user_input"
    else
        print_warning "无效输入，使用默认值: $default_threads"
        echo "$default_threads"
    fi
}

# 交互选择要预编译的包
select_packages_to_precompile() {
    local -n pkg_list=$1
    
    if [ ${#pkg_list[@]} -eq 0 ]; then
        print_info "没有可选择的未编译包"
        return
    fi
    
    print_header "选择要预编译的软件包"
    
    local selected=()
    local i=1
    
    echo -e "${BOLD}可选软件包列表:${NC}"
    for pkg in "${pkg_list[@]}"; do
        echo "  [$i] $pkg"
        ((i++))
    done
    echo ""
    echo -e "${YELLOW}提示:${NC} 输入包编号 (空格分隔), 或输入 'all' 选择全部, 或按回车跳过"
    echo -n "请选择: "
    
    read -r selection
    
    if [ -z "$selection" ]; then
        return
    fi
    
    if [ "$selection" = "all" ]; then
        selected=("${pkg_list[@]}")
    else
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "${#pkg_list[@]}" ]; then
                selected+=("${pkg_list[$((num-1))]}")
            fi
        done
    fi
    
    if [ ${#selected[@]} -gt 0 ]; then
        print_success "已选择 ${#selected[@]} 个包进行预编译"
        printf '%s\n' "${selected[@]}"
    fi
}

# 预编译选定的包
precompile_packages() {
    local -n packages=$1
    local threads=$2
    
    if [ ${#packages[@]} -eq 0 ]; then
        return
    fi
    
    print_header "开始预编译软件包"
    
    local total=${#packages[@]}
    local current=0
    local success=0
    local failed=0
    
    for pkg in "${packages[@]}"; do
        ((current++))
        print_info "[$current/$total] 正在编译: $pkg"
        
        if make package/${pkg}/compile -j${threads} V=s 2>&1 | tee /tmp/build_${pkg}.log | grep -E "package/.*compiled|ERROR"; then
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                print_success "✓ $pkg 编译完成"
                ((success++))
            else
                print_error "✗ $pkg 编译失败"
                ((failed++))
                
                # 调用错误分析
                analyze_error "/tmp/build_${pkg}.log" "$pkg"
            fi
        fi
    done
    
    echo ""
    print_header "预编译完成"
    echo -e "${GREEN}成功: $success${NC} | ${RED}失败: $failed${NC} | 总计: $total"
    echo ""
}

# 监测编译进度
monitor_build_progress() {
    local threads=$1
    local log_file="/tmp/immortalwrt_build_$(date +%Y%m%d_%H%M%S).log"
    
    print_header "开始完整编译"
    print_info "日志文件: $log_file"
    print_info "编译线程: $threads"
    echo ""
    
    # 定义编译阶段
    local current_stage="准备阶段"
    local start_time=$(date +%s)
    
    # 启动编译并实时监测
    make -j${threads} V=s 2>&1 | tee "$log_file" | while IFS= read -r line; do
        # 检测编译阶段
        if echo "$line" | grep -q "tools/.*compile"; then
            if [ "$current_stage" != "编译工具链" ]; then
                current_stage="编译工具链"
                print_info "阶段: ${CYAN}$current_stage${NC}"
            fi
        elif echo "$line" | grep -q "toolchain/.*compile"; then
            if [ "$current_stage" != "编译交叉编译器" ]; then
                current_stage="编译交叉编译器"
                print_info "阶段: ${CYAN}$current_stage${NC}"
            fi
        elif echo "$line" | grep -q "target/linux/.*compile"; then
            if [ "$current_stage" != "编译内核" ]; then
                current_stage="编译内核"
                print_info "阶段: ${CYAN}$current_stage${NC}"
            fi
        elif echo "$line" | grep -q "package/.*compile"; then
            if [ "$current_stage" != "编译软件包" ]; then
                current_stage="编译软件包"
                print_info "阶段: ${CYAN}$current_stage${NC}"
            fi
            # 显示正在编译的包
            if [[ $line =~ package/([^/]+)/compile ]]; then
                echo -e "  ${BLUE}→${NC} 编译: ${BASH_REMATCH[1]}"
            fi
        elif echo "$line" | grep -q "target/linux/.*install"; then
            if [ "$current_stage" != "生成固件" ]; then
                current_stage="生成固件"
                print_info "阶段: ${CYAN}$current_stage${NC}"
            fi
        fi
        
        # 检测错误
        if echo "$line" | grep -qE "Error|ERROR|error:|失败"; then
            print_error "检测到编译错误！"
            echo "$line"
        fi
        
        # 格式化关键输出
        if echo "$line" | grep -qE "compiled|installed|cleaned"; then
            echo -e "  ${GREEN}✓${NC} $line"
        fi
    done
    
    local exit_code=${PIPESTATUS[0]}
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    
    if [ $exit_code -eq 0 ]; then
        print_header "编译成功完成！"
        echo -e "${GREEN}${BOLD}耗时: $(format_duration $duration)${NC}"
        echo -e "${GREEN}${BOLD}固件位置: bin/targets/${NC}"
    else
        print_header "编译失败"
        echo -e "${RED}${BOLD}耗时: $(format_duration $duration)${NC}"
        print_error "正在分析错误..."
        analyze_error "$log_file" "主编译"
    fi
    
    return $exit_code
}

# 格式化时长
format_duration() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [ $hours -gt 0 ]; then
        echo "${hours}小时${minutes}分${secs}秒"
    elif [ $minutes -gt 0 ]; then
        echo "${minutes}分${secs}秒"
    else
        echo "${secs}秒"
    fi
}

# 提取错误日志关键部分
extract_error_context() {
    local log_file=$1
    local context_lines=$2
    
    # 查找错误关键字并提取上下文
    local error_line=$(grep -n -E "Error|ERROR|error:|make.*failed" "$log_file" | tail -1 | cut -d: -f1)
    
    if [ -z "$error_line" ]; then
        # 如果没有找到明确的错误，返回最后几行
        tail -n "$context_lines" "$log_file"
    else
        # 提取错误行前后的上下文
        local start=$((error_line - context_lines / 2))
        [ $start -lt 1 ] && start=1
        
        sed -n "${start},$((error_line + context_lines / 2))p" "$log_file"
    fi
}

# 使用 OpenAI API 分析错误
analyze_error() {
    local log_file=$1
    local component=$2
    
    print_header "AI 错误分析"
    
    if [ -z "$OPENAI_API_KEY" ]; then
        print_warning "未配置 OPENAI_API_KEY，跳过 AI 分析"
        print_info "请设置环境变量: export OPENAI_API_KEY='your-api-key'"
        return
    fi
    
    print_info "正在提取错误上下文..."
    local error_context=$(extract_error_context "$log_file" "$ERROR_CONTEXT_LINES")
    
    print_info "正在调用 AI 分析..."
    
    # 构建提示词
    local prompt="${CUSTOM_PROMPT//\{SYSTEM_INFO\}/$SYSTEM_INFO}"
    prompt="${prompt//\{ERROR_LOG\}/$error_context}"
    
    # 构建 JSON 请求
    local json_payload=$(jq -n \
        --arg model "$OPENAI_MODEL" \
        --arg prompt "$prompt" \
        '{
            model: $model,
            messages: [
                {
                    role: "user",
                    content: $prompt
                }
            ],
            temperature: 0.7
        }')
    
    # 调用 API
    local response=$(curl -s -X POST "$OPENAI_API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        -d "$json_payload")
    
    # 提取回复
    local ai_analysis=$(echo "$response" | jq -r '.choices[0].message.content // "API调用失败"')
    
    echo ""
    print_header "AI 分析结果"
    echo -e "${CYAN}组件:${NC} $component"
    echo ""
    echo "$ai_analysis"
    echo ""
    
    # 保存分析结果
    local analysis_file="error_analysis_$(date +%Y%m%d_%H%M%S).txt"
    {
        echo "=== ImmortalWRT 编译错误分析 ==="
        echo "时间: $(date)"
        echo "组件: $component"
        echo ""
        echo "=== 系统信息 ==="
        echo "$SYSTEM_INFO"
        echo ""
        echo "=== 错误日志 ==="
        echo "$error_context"
        echo ""
        echo "=== AI 分析 ==="
        echo "$ai_analysis"
    } > "$analysis_file"
    
    print_success "分析结果已保存至: $analysis_file"
}

# ==================== 主流程 ====================

main() {
    clear
    print_header "ImmortalWRT 智能编译监测脚本"
    echo ""
    
    # 检查是否在 ImmortalWRT 目录
    if [ ! -f "feeds.conf.default" ] || [ ! -d "package" ]; then
        print_error "请在 ImmortalWRT 源码根目录下运行此脚本"
        exit 1
    fi
    
    # WSL2 环境配置
    if detect_wsl2; then
        configure_wsl2_environment
    fi
    
    # 设置退出时恢复环境
    trap restore_environment EXIT
    
    # 1. 检测系统信息
    local cpu_cores=$(detect_system_info)
    
    # WSL2 线程数建议
    if detect_wsl2; then
        print_info "WSL2 环境建议使用较少线程以避免系统卡顿"
        local recommended_threads=$((cpu_cores * 3 / 4))
        if [ $recommended_threads -lt 1 ]; then
            recommended_threads=1
        fi
        print_info "推荐线程数: $recommended_threads (75% 核心数)"
        echo ""
    fi
    
    # 2. 检测软件包状态
    mapfile -t uncompiled_packages < <(detect_packages)
    local uncompiled_count=${#uncompiled_packages[@]}
    
    # 3. 交互：是否显示未编译的包
    if [ $uncompiled_count -gt 0 ]; then
        echo -n "是否显示所有未编译的软件包? (y/N): "
        read -r show_uncompiled
        
        if [[ "$show_uncompiled" =~ ^[Yy]$ ]]; then
            echo ""
            print_header "未编译软件包列表"
            printf '  - %s\n' "${uncompiled_packages[@]}"
            echo ""
            
            # 4. 交互：是否预编译
            echo -n "是否要预编译部分软件包? (y/N): "
            read -r do_precompile
            
            if [[ "$do_precompile" =~ ^[Yy]$ ]]; then
                # 5. 选择要预编译的包
                mapfile -t selected_packages < <(select_packages_to_precompile uncompiled_packages)
                
                if [ ${#selected_packages[@]} -gt 0 ]; then
                    # 选择预编译线程数
                    echo ""
                    print_info "预编译配置"
                    local precompile_threads=$(select_thread_count "$cpu_cores")
                    
                    # 开始预编译
                    echo ""
                    precompile_packages selected_packages "$precompile_threads"
                fi
            fi
        fi
    fi
    
    # 6. 选择主编译线程数
    echo ""
    print_info "主编译配置"
    local build_threads=$(select_thread_count "$cpu_cores")
    
    # 7. 开始完整编译
    echo ""
    echo -n "按回车键开始编译，或 Ctrl+C 取消..."
    read -r
    
    monitor_build_progress "$build_threads"
}

# 执行主函数
main "$@"