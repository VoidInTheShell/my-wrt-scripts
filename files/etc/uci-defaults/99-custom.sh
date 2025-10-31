#!/bin/sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 

uci set firewall.@zone[1].input='ACCEPT'

# 自定义参数

# 自定义路由器后台管理地址
IP_VALUE=10.0.1.1
# 配置PPPOE
enable_pppoe=
pppoe_account=
pppoe_password=
# 自定义背景图链接
THEME_BG_URL=https://free.picui.cn/free/2025/10/30/6902f8d9a084b.png

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 1. 先获取所有物理接口列表
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        ifnames="$ifnames $iface_name"
    fi
done
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

count=$(echo "$ifnames" | wc -w)
echo "Detected physical interfaces: $ifnames" >>$LOGFILE
echo "Interface count: $count" >>$LOGFILE

# 2. 根据板子型号映射WAN和LAN接口
board_name=$(cat /tmp/sysinfo/board_name 2>/dev/null || echo "unknown")
echo "Board detected: $board_name" >>$LOGFILE

wan_ifname=""
lan_ifnames=""
# 此处特殊处理个别开发板网口顺序问题
case "$board_name" in
    "radxa,e20c"|"friendlyarm,nanopi-r5c")
        wan_ifname="eth1"
        lan_ifnames="eth0"
        echo "Using $board_name mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
    *)
        # 默认第一个接口为WAN，其余为LAN
        wan_ifname=$(echo "$ifnames" | awk '{print $1}')
        lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
        echo "Using default mapping: WAN=$wan_ifname LAN=$lan_ifnames" >>"$LOGFILE"
        ;;
esac

# 3. 配置网络
if [ "$count" -eq 1 ]; then
    # 单网口设备，DHCP模式
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway
    uci delete network.lan.dns
    uci commit network
elif [ "$count" -gt 1 ]; then
    # 多网口设备配置
    # 配置WAN
    uci set network.wan=interface
    uci set network.wan.device="$wan_ifname"
    uci set network.wan.proto='dhcp'

    # 配置WAN6
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    uci set network.wan6.proto='dhcpv6'

    # 查找 br-lan 设备 section
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # 删除原有ports
        uci -q delete "network.$section.ports"
        # 添加LAN接口端口
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "Updated br-lan ports: $lan_ifnames" >>$LOGFILE
    fi

    # LAN口设置静态IP
    uci set network.lan.proto='static'
    # 多网口设备 支持修改为别的管理后台地址 在Github Action 的UI上自行输入即可 
    uci set network.lan.netmask='255.255.255.0'
    # 设置路由器管理后台地址
    if [ -n "$IP_VALUE" ] && [ "$IP_VALUE" != "0" ]; then
        CUSTOM_IP=$IP_VALUE
        # 用户在UI上设置的路由器后台管理地址
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
    else
        uci set network.lan.ipaddr='192.168.100.1'
        echo "default router ip is 192.168.100.1" >> $LOGFILE
    fi

    # PPPoE设置
    echo "enable_pppoe value: $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE enabled, configuring..." >>$LOGFILE
        uci set network.wan.proto='pppoe'
        uci set network.wan.username="$pppoe_account"
        uci set network.wan.password="$pppoe_password"
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        uci set network.wan6.proto='none'
        echo "PPPoE config done." >>$LOGFILE
    else
        echo "PPPoE not enabled." >>$LOGFILE
    fi

    uci commit network
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall
    # 追加新的 zone + forwarding 配置
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# ============ PortalWRT 自定义配置开始 ============

# 获取编译日期（从build.sh传入，如果没有则使用当前日期）
BUILD_DATE="${BUILD_DATE:-$(date +%y-%m-%d)}"
echo "Build date: $BUILD_DATE" >>$LOGFILE

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="PortalWRT-$BUILD_DATE"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 修改固件版本信息
if [ -f "$FILE_PATH" ]; then
    sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"
    # 替换 ImmortalWrt 为 PortalWRT
    sed -i "s/ImmortalWrt/PortalWRT/g" "$FILE_PATH"
    sed -i "s/IMMORTALWRT/PORTALWRT/g" "$FILE_PATH"
    # 替换版本号格式（r开头的版本号替换为编译日期）
    sed -i "s/ r[0-9]*-[0-9a-f]*/ $BUILD_DATE/g" "$FILE_PATH"
    echo "Firmware version updated to PortalWRT $BUILD_DATE" >>$LOGFILE
fi

# 设置系统主机名
uci set system.@system[0].hostname="GLaDOS"
uci set system.@system[0].timezone="CST-8"
uci set system.@system[0].zonename="Asia/Shanghai"

# 若luci-app-advancedplus (进阶设置)已安装 则去除zsh的调用 防止命令行报 /usb/bin/zsh: not found的提示
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
fi

echo "Creating dynamic banner script..." >>$LOGFILE

cat > /etc/profile.d/portal-banner.sh << 'BANNEREOF'
#!/bin/sh

get_lan_ip()
{
    ip -4 addr show br-lan 2>/dev/null | grep -oE 'inet [0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | awk '{print $2}' | head -n1
}

get_wan_ip()
{
    local ip
    ip=$(wget -qO- --timeout=3 -T 3 http://ipinfo.io/ip 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
    if [ -z "$ip" ]; then
        ip=$(wget -qO- --timeout=3 -T 3 http://ip.sb 2>/dev/null | grep -oE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$')
    fi
    if [ -z "$ip" ]; then
        ip="N/A"
    fi
    echo "$ip"
}

get_uptime()
{
    local uptime_sec
    uptime_sec=$(cut -d. -f1 /proc/uptime)
    local days=$((uptime_sec / 86400))
    local hours=$(((uptime_sec % 86400) / 3600))
    local mins=$(((uptime_sec % 3600) / 60))
    
    if [ $days -gt 0 ]; then
        echo "${days}d ${hours}h ${mins}m"
    elif [ $hours -gt 0 ]; then
        echo "${hours}h ${mins}m"
    else
        echo "${mins}m"
    fi
}

get_portal_version()
{
    grep "DISTRIB_DESCRIPTION" /etc/openwrt_release 2>/dev/null | cut -d"'" -f2 | sed 's/PortalWRT //'
}

get_openwrt_version()
{
    grep "DISTRIB_RELEASE" /etc/openwrt_release 2>/dev/null | cut -d"'" -f2
}

clear
cat << 'LOGO'
............-=+****++=..........................................................................................................
........=**--+%@@@@@@@:=#+:.....................................................................................................
.....:+%@@@@%*--+%@@@@*:@@@#=...................................................................................................
....=%@@@@@@@@@#=.-+%@%.*@@@@#:.................................................................................................
...+%##*++=-::.......-+--@@@@@+.:::........::::::......::::::::....:::::::.....:::::::::...:::.....::....:::::::......::::::::..
..-==+*###=..............%@@@=-%@@@+......#@@%%@@@*...=@@@%%%%%...=@@%%%@@%=..*@@@@@@@@%:.:@@@:...*@@=...%@@%%@@@*...:@@@%%%%%:.
..@@@@@@#:...............+@#:=@%--@%.....-@@%...@@%:..#@@.........#@@-..*@@=.....#@@-.....+@@*...:@@%...=@@*..-@@#...+@@+.......
.-@@@@@*.................:+.*@%%%%@@-....*@@%%%%@%=..-@@@%%%%*...-@@@##%@#-.....-@@%......%@@:...+@@+...#@@%##@%=....%@@%%%%#...
.-@@@%=-#.................:#@@%--%@@*...:@@%.........*@@.........*@@+--@@@:.....*@@=.....-@@%...:%@%:..-@@#--#@@*...=@@*:::::...
..%@#:+@@-...............-%@#----+@@@...+@@+........:@@@#####:..:@@%..:@@@:....:@@%......:%@@#*#@@#:...*@@=..#@@+...%@@%####=...
..=+:#@@@*...............---......---:..---:........:--------...:---...---.....:---........-====-:.....---...---:...--------:...
...:%@@@@%.++-......::-=++*##%%:...+.......-+-....-+--=....=--==...:+--+.....=+:...:-+=-...:=--=:...==-==...=:...+---...:=--=...
....=%@@@@=-@@%+::+%@@@@@@@@@*:....#......-#-#-...-*-=*...-+...#...:#-=*....+*-#:....+:....*:..:*...+=-+=...+-...#--:...:==-+...
.....:+%@@#.%@@@@%+-=*@@@@@#-......=--..:=...=:..:=--=....=--=-....=..=...:-...=....-:....:=--=:...-:.:=...-:...+---...:=--=...
........-*#:+@@@@@@@%+-=*+:.....................................................................................................
............:=++***+==:.........................................................................................................
________________________________________________________________________________________________________________________________
LOGO

LAN_IP=$(get_lan_ip)
[ -z "$LAN_IP" ] && LAN_IP="N/A"
WAN_IP=$(get_wan_ip)
UPTIME=$(get_uptime)
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")
PORTAL_VER=$(get_portal_version)
[ -z "$PORTAL_VER" ] && PORTAL_VER="Unknown"
OPENWRT_VER=$(get_openwrt_version)
[ -z "$OPENWRT_VER" ] && OPENWRT_VER="Unknown"

printf "\n"
printf " %-42s %-42s %-42s\n" "  LAN IP: $LAN_IP" "  WAN IP: $WAN_IP" "  Uptime: $UPTIME"
printf " %-42s %-42s %-42s\n" "  Time: $CURRENT_TIME" "  PortalWRT: $PORTAL_VER" "  OpenWrt: $OPENWRT_VER"
printf "\n"

LINE="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
printf "    %s\n" "$LINE"

TEXT="Powered by APERTURE Science"
printf "%50s%s\n" "" "$TEXT"

printf "    %s\n" "$LINE"
printf "\n"
BANNEREOF

chmod +x /etc/profile.d/portal-banner.sh
echo "Dynamic banner script created" >>$LOGFILE

# 3. 配置主题背景图片

if [ -n "$THEME_BG_URL" ]; then
    echo "Configuring theme background from: $THEME_BG_URL" >>$LOGFILE
    
    # 下载背景图片
    BG_DIR="/www/luci-static/resources/view/themes"
    mkdir -p "$BG_DIR"
    
    # 尝试下载背景图片
    if wget -qO /tmp/portal-bg.jpg "$THEME_BG_URL" 2>>$LOGFILE; then
        echo "Background image downloaded successfully" >>$LOGFILE
        
        # 为 Argon 主题配置背景
        ARGON_BG_DIR="/www/luci-static/argon/img"
        if [ -d "$ARGON_BG_DIR" ]; then
            cp /tmp/portal-bg.jpg "$ARGON_BG_DIR/bg1.jpg"
            echo "Argon theme background configured" >>$LOGFILE
        fi
        
        # 为 Kucat 主题配置背景
        KUCAT_BG_DIR="/www/luci-static/kucat/img"
        if [ -d "$KUCAT_BG_DIR" ]; then
            cp /tmp/portal-bg.jpg "$KUCAT_BG_DIR/bg1.jpg"
            echo "Kucat theme background configured" >>$LOGFILE
        fi
        
        # 清理临时文件
        rm -f /tmp/portal-bg.jpg
    else
        echo "Failed to download background image" >>$LOGFILE
    fi
else
    echo "No theme background URL provided, skipping..." >>$LOGFILE
fi

# ============ PortalWRT 自定义配置结束 ============

uci commit system

echo "99-custom.sh completed at $(date)" >>$LOGFILE
exit 0
