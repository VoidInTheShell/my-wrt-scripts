#!/bin/sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE

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
