#!/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
sed -i '/src-git qmodem https:\/\/github\.com\/FUjr\/QModem\.git;main/d' feeds.conf.default
rm -rf package/qosmate package/luci-app-qosmate
rm -rf package/watchdog package/netspeedtest package/luci-theme-kucat package/luci-app-poweroffdevice package/luci-app-taskplan package/luci-app-advancedplus package/UA3F package/UA-Mask package/luci-app-adguardhome package/QModem package/luci-app-modem
echo 'src-git qmodem https://github.com/FUjr/QModem.git;main' >> feeds.conf.default
git clone https://github.com/danchexiaoyang/luci-app-onliner.git package/luci-app-onliner
git clone https://github.com/hudra0/qosmate.git package/qosmate
git clone https://github.com/hudra0/luci-app-qosmate.git package/luci-app-qosmate
git clone https://github.com/sirpdboy/luci-app-watchdog package/watchdog
git clone https://github.com/sirpdboy/luci-app-netspeedtest package/netspeedtest
git clone https://github.com/sirpdboy/luci-theme-kucat.git package/luci-theme-kucat
git clone https://github.com/sirpdboy/luci-app-poweroffdevice package/luci-app-poweroffdevice
git clone https://github.com/sirpdboy/luci-app-taskplan package/luci-app-taskplan
git clone https://github.com/sirpdboy/luci-app-advancedplus.git package/luci-app-advancedplus
git clone https://github.com/SunBK201/UA3F.git package/UA3F
git clone https://github.com/Zesuy/UA-Mask.git package/UA-Mask
git clone https://github.com/sirpdboy/luci-app-adguardhome.git package/luci-app-adguardhome
git clone https://github.com/qianlyun123/luci-app-modem.git package/luci-app-modem
echo "python3-disutils依赖问题直接注释"
echo "BandIX:luci-app-bandix+bandix===无法与硬件加速共存"
echo "Onliner:luci-app-onliner===实时数据不正确"
echo "qosmate:luci-app-qosmate+base-system---qosmate"
echo "netspeedtest---poweroffdevice---taskplan---advancedplus---watchdog===建议默认选中"
echo "5G模组驱动USB和MHI按需选择"
echo "quectel-CM-5G依赖如果有问题则改为quectel-CM-5G-M或quectel-cm或注释"
./scripts/feeds update -a
./scripts/feeds install -a -f