#!/bin/bash
# QoSmate 集成脚本 - 用于 OpenWRT 编译流程
# 此脚本在编译前运行，将 QoSmate 包添加到编译系统中

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

echo "=========================================="
echo "开始集成 QoSmate 到编译流程"
echo "=========================================="

# 定义 QoSmate 仓库信息
QOSMATE_REPO="https://github.com/hudra0/qosmate.git"
LUCI_QOSMATE_REPO="https://github.com/hudra0/luci-app-qosmate.git"

# 清理旧的 QoSmate 包（如果存在）
echo "清理旧的 QoSmate 包..."
rm -rf package/qosmate package/luci-app-qosmate

# 克隆 QoSmate 后端包
echo "克隆 QoSmate 后端包..."
if git clone "$QOSMATE_REPO" package/qosmate; then
    echo "✓ QoSmate 后端包克隆成功"
else
    echo "✗ QoSmate 后端包克隆失败"
    exit 1
fi

# 克隆 QoSmate 前端包（LuCI 界面）
echo "克隆 QoSmate 前端包..."
if git clone "$LUCI_QOSMATE_REPO" package/luci-app-qosmate; then
    echo "✓ QoSmate 前端包克隆成功"
else
    echo "✗ QoSmate 前端包克隆失败"
    exit 1
fi

# 更新 feeds
echo "更新 feeds..."
./scripts/feeds update -a

# 安装 feeds
echo "安装 feeds..."
./scripts/feeds install -a -f

echo "=========================================="
echo "QoSmate 集成完成"
echo "=========================================="
echo ""
echo "注意事项："
echo "1. QoSmate 需要 OpenWrt 23.05 或更高版本"
echo "2. 需要启用以下内核模块："
echo "   - kmod-sched-core (流量控制核心)"
echo "   - kmod-ifb (IFB 虚拟接口)"
echo "   - kmod-sched-cake (CAKE qdisc，可选)"
echo "3. 需要安装 tc 工具包"
echo "4. 如需动态 IP 集功能，需要 dnsmasq-full"
echo ""
echo "编译时请在 menuconfig 中选择："
echo "  Network -> qosmate"
echo "  LuCI -> Applications -> luci-app-qosmate"
echo ""
