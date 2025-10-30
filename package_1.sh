#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
git clone https://github.com/sirpdboy/luci-app-watchdog package/watchdog
git clone https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest
git clone https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat
git clone https://github.com/sirpdboy/luci-app-poweroffdevice package/luci-app-poweroffdevice
git clone https://github.com/sirpdboy/luci-app-taskplan package/luci-app-taskplan
git clone https://github.com/sirpdboy/luci-app-advancedplus.git package/luci-app-advancedplus
git clone https://github.com/SunBK201/UA3F.git package/UA3F
git clone https://github.com/Zesuy/UA3F-tproxy.git package/UA3F-tproxy
git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/luci-app-adguardhome
echo 'src-git qmodem https://github.com/FUjr/QModem.git;main' >> feeds.conf.default
#git clone https://github.com/FUjr/QModem.git package/QModem
git clone https://github.com/qianlyun123/luci-app-modem.git package/luci-app-modem
#git clone https://github.com/Kiougar/luci-wrtbwmon.git package/wrtbwmon-1 && mv package/wrtbwmon-1/luci-wrtbwmon package/wrtbwmon && rm -rf package/wrtbwmon-1
#git clone https://github.com/brvphoenix/luci-app-wrtbwmon.git package/luci-app-wrtbwmon-1 && mv package/luci-app-wrtbwmon-1 package/luci-app-wrtbwmon && rm -rf package/luci-app-wrtbwmon-1
./scripts/feeds update -a
./scripts/feeds install -a -f