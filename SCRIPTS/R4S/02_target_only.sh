#!/bin/bash
clear

# 1. 使用特定的优化与配置
#sed -i 's,-mcpu=generic,-march=armv8-a+crc+crypto,g' include/target.mk
sed -i 's,kmod-r8168,kmod-r8169,g' target/linux/rockchip/image/armv8.mk

# 2. Vermagic 保持官方一致性
latest_version="$(curl -s https://github.com/openwrt/openwrt/tags | grep -Eo "v[0-9\.]+\-*r*c*[0-9]*.tar.gz" | sed -n '/[2-9][5-9]/p' | sed -n 1p | sed 's/v//g' | sed 's/.tar.gz//g')"
wget https://downloads.openwrt.org/releases/${latest_version}/targets/rockchip/armv8/profiles.json
jq -r '.linux_kernel.vermagic' profiles.json >.vermagic
sed -i -e 's/^\(.\).*vermagic$/\1cp $(TOPDIR)\/.vermagic $(LINUX_DIR)\/.vermagic/' include/kernel-defaults.mk

# 3. 预配置一些插件
cp -rf ../PATCH/files ./files

find ./ -name *.orig | xargs rm -f
find ./ -name *.rej | xargs rm -f


# =====================================================================
# 4. 移植你以前的 R4S 1G 内存修复补丁集 (整合至当前编译目录)
# =====================================================================
echo "开始应用 R4S 1G 内存完美修复补丁..."

# 强制删除官方源码中导致 1GB 无法开机的 sd-signalling 冲突补丁
find target/linux/ -name "*nanopi-r4s-sd-signalling*" -delete

# 在 openwrt 源码目录的同级或外层克隆补丁源（这里克隆到 ../patch-src）
if [ -d "../patch-src/.git" ]; then
    cd ../patch-src && git fetch --depth 1 origin && git reset --hard origin/HEAD && cd ../openwrt || cd -
else
    git clone --depth 1 https://github.com/anaelorlinski/OpenWrt-NanoPi-R2S-R4S-Builds.git ../patch-src
fi

# 定义补丁源路径 (注意：如果上游结构变了，这里通常会保留最新稳定版的 patches 目录)
# 如果对方仓库更新了目录，可根据需要调整 openwrt-25.12 字段
PATCHES="../patch-src/openwrt-25.12/patches"

if [ -d "$PATCHES" ]; then
    # 1) 完整替换 uboot-rockchip 包，支持 1G(DDR3)/4G(LPDDR4) 自动识别
    echo "正在替换 uboot-rockchip 包..."
    rm -rf package/boot/uboot-rockchip
    cp -R "$PATCHES/package/uboot-rockchip" package/boot/

    # 2) 提取内核补丁
    KDIR=$(find target/linux/rockchip -maxdepth 1 -type d -name "patches-*" | head -n1)
    echo "内核补丁目标目录: $KDIR"
    
    if [ -n "$KDIR" ]; then
        for p in 103-arm64-dts-rockchip-lower-mmc-speed.patch \
                 402-1-rk3399-fix-pci-phy-reset-on-probe.patch \
                 501-mmc-core-set-initial-signal-voltage-on-power-off.patch; do
            SRC="$PATCHES/target/linux/rockchip/$(basename "$KDIR")/$p"
            if [ -f "$SRC" ]; then
                cp "$SRC" "$KDIR/"
                echo "已成功加入内核补丁: $p"
            else
                echo "提示：没找到 $p，跳过（可能上游内核版本已内置或目录结构变化）"
            fi
        done
    fi

    echo "补丁应用确认："
    ls package/boot/uboot-rockchip/patches/ 2>/dev/null | grep -E "30[0-9]|31[0]" || true
    ls "$KDIR" 2>/dev/null | grep -E "103-|402-1|501-" || true
else
    echo "错误: 未找到补丁源目录 $PATCHES，请检查该仓库的分支结构！"
fi
# =====================================================================

exit 0
