#!/bin/bash

URL="$1"              # 移植包下载地址
VENDOR_URL="$2"       # 底包下载地址
GITHUB_ENV="$3"       # 输出环境变量
GITHUB_WORKSPACE="$4" # 工作目录

Red='\033[1;31m'    # 粗体红色
Yellow='\033[1;33m' # 粗体黄色
Blue='\033[1;34m'   # 粗体蓝色
Green='\033[1;32m'  # 粗体绿色

device=munch # 设备代号

port_os_version=$(echo ${URL} | cut -d"/" -f4)                   # 移植包的 OS 版本号
port_zip_name=$(echo ${URL} | cut -d"/" -f5)                     # 移植包的 zip 名称
vendor_os_version=$(echo ${VENDOR_URL} | cut -d"/" -f4)          # 底包的 OS 版本号
vendor_zip_name=$(echo ${VENDOR_URL} | cut -d"/" -f5)            # 底包的 zip 名称
android_version=$(echo ${URL} | cut -d"." -f12 | cut -d"-" -f3) # Android 版本号
build_time=$(date) && build_utc=$(date -d "$build_time" +%s)   # 构建时间

# 工具路径
magiskboot="$GITHUB_WORKSPACE"/tools/magiskboot
a7z="$GITHUB_WORKSPACE"/tools/7zzs
payload_extract="$GITHUB_WORKSPACE"/tools/payload_extract
erofs_extract="$GITHUB_WORKSPACE"/tools/extract.erofs
erofs_mkfs="$GITHUB_WORKSPACE"/tools/mkfs.erofs
lpmake="$GITHUB_WORKSPACE"/tools/lpmake

sudo chmod -R 777 "$GITHUB_WORKSPACE"/tools

Start_Time() {
  Start_s=$(date +%s)
  Start_ns=$(date +%N)
}

End_Time() {
  local End_s End_ns time_s time_ns
  End_s=$(date +%s)
  End_ns=$(date +%N)
  time_s=$((10#$End_s - 10#$Start_s))
  time_ns=$((10#$End_ns - 10#$Start_ns))
  if ((time_ns < 0)); then
    ((time_s--))
    ((time_ns += 1000000000))
  fi
 
  local ns ms sec min hour
  ns=$((time_ns % 1000000))
  ms=$((time_ns / 1000000))
  sec=$((time_s % 60))
  min=$((time_s / 60 % 60))
  hour=$((time_s / 3600))

  if ((hour > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$hour小时$min分$sec秒$ms毫秒"
  elif ((min > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$min分$sec秒$ms毫秒"
  elif ((sec > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$sec秒$ms毫秒"
  elif ((ms > 0)); then
    echo -e "${Green}- 本次$1用时: ${Blue}$ms毫秒"
  else
    echo -e "${Green}- 本次$1用时: ${Blue}$ns纳秒"
  fi
}

### 系统包下载
echo -e "${Red}- 开始下载系统包"
Start_Time
echo -e "${Yellow}- 开始下载底包"
aria2c -x16 -s16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" ${VENDOR_URL}
End_Time 下载底包
echo -e "${Yellow}- 开始下载移植包"
Start_Time
aria2c -x16 -s16 -j$(nproc) -U "Mozilla/5.0" -d "$GITHUB_WORKSPACE" ${URL}
End_Time 下载移植包
### 系统包下载结束

### 解包
echo -e "${Red}- 开始解压系统包"
mkdir -p "$GITHUB_WORKSPACE"/"${device}"
mkdir -p "$GITHUB_WORKSPACE"/images/config
mkdir -p "$GITHUB_WORKSPACE"/zip

echo -e "${Yellow}- 开始解压底包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${vendor_zip_name} -o"$GITHUB_WORKSPACE"/"${device}" payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${vendor_zip_name}
End_Time 解压底包

mkdir -p "$GITHUB_WORKSPACE"/Extra_dir
echo -e "${Red}- 开始解底包 Payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/Extra_dir/ -i "$GITHUB_WORKSPACE"/"${device}"/payload.bin -X mi_ext,system,product -e -T0
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/payload.bin

echo -e "${Yellow}- 开始解压移植包"
Start_Time
$a7z x "$GITHUB_WORKSPACE"/${port_zip_name} -o"$GITHUB_WORKSPACE"/images payload.bin >/dev/null
rm -rf "$GITHUB_WORKSPACE"/${port_zip_name}
End_Time 解压移植包

echo -e "${Red}- 开始分解底包 Images"
for i in system_ext odm vendor; do
  echo -e "${Yellow}- 正在分解底包: $i.img"
  cd "$GITHUB_WORKSPACE"/"${device}"
  sudo $erofs_extract -i "$GITHUB_WORKSPACE"/Extra_dir/$i.img -x -s
  rm -rf "$GITHUB_WORKSPACE"/Extra_dir/$i.img
done

sudo mkdir -p "$GITHUB_WORKSPACE"/"${device}"/firmware-update/
sudo cp -rf "$GITHUB_WORKSPACE"/Extra_dir/* "$GITHUB_WORKSPACE"/"${device}"/firmware-update/

cd "$GITHUB_WORKSPACE"/images
echo -e "${Red}- 开始解移植包 Payload"
$payload_extract -s -o "$GITHUB_WORKSPACE"/images/ -i "$GITHUB_WORKSPACE"/images/payload.bin -X mi_ext,product,system,system_ext,odm -T0
sudo rm -rf "$GITHUB_WORKSPACE"/images/payload.bin

echo -e "${Red}- 开始分解移植包 Images"
for i in mi_ext product system system_ext odm; do
  echo -e "${Yellow}- 正在分解移植包: $i"
  sudo $erofs_extract -i "$GITHUB_WORKSPACE"/images/$i.img -x -s
  rm -rf "$GITHUB_WORKSPACE"/images/$i.img
done
### 解包结束

### 写入变量
echo -e "${Red}- 开始写入变量"

echo "build_time=$build_time" >> "$GITHUB_ENV"
echo -e "${Blue}- 构建日期: $build_time"

odm_build_prop="$GITHUB_WORKSPACE/images/odm/etc/build.prop"
model=$(grep '^ro.product.odm.marketname=' "$odm_build_prop" | head -n1 | cut -d'=' -f2-)

{
  echo "model<<EOF"
  echo "$model"
  echo "EOF"
} >> "$GITHUB_ENV"

echo -e "${Blue}- 移植包机型: $model"

echo "port_os_version=$port_os_version" >> "$GITHUB_ENV"
echo -e "${Blue}- 移植包版本: $port_os_version"

echo "vendor_os_version=$vendor_os_version" >> "$GITHUB_ENV"

system_build_prop=$(find "$GITHUB_WORKSPACE/images/system/system/" -maxdepth 1 -type f -name "build.prop" | head -n 1)

port_security_patch=$(grep '^ro.build.version.security_patch=' "$system_build_prop" | cut -d'=' -f2-)
echo -e "${Blue}- 移植包安全补丁版本: $port_security_patch"
echo "port_security_patch=$port_security_patch" >> "$GITHUB_ENV"

vendor_build_prop="$GITHUB_WORKSPACE/${device}/vendor/build.prop"
vendor_security_patch=$(grep '^ro.vendor.build.security_patch=' "$vendor_build_prop" | cut -d'=' -f2-)
echo -e "${Blue}- 底包安全补丁版本: $vendor_security_patch"
echo "vendor_security_patch=$vendor_security_patch" >> "$GITHUB_ENV"

port_base_line=$(grep '^ro.system.build.id=' "$system_build_prop" | cut -d'=' -f2-)
echo -e "${Blue}- 移植包基线版本: $port_base_line"
echo "port_base_line=$port_base_line" >> "$GITHUB_ENV"

system_ext_build_prop="$GITHUB_WORKSPACE/${device}/system_ext/etc/build.prop"
origin_base_line=$(grep '^ro.system_ext.build.id=' "$system_ext_build_prop" | cut -d'=' -f2-)
echo -e "${Blue}- 底包基线版本: $origin_base_line"
echo "origin_base_line=$origin_base_line" >> "$GITHUB_ENV"

vendor_base_line=$(grep '^ro.vendor.build.id=' "$vendor_build_prop" | cut -d'=' -f2-)
echo -e "${Blue}- 底包vendor基线版本: $vendor_base_line"
echo "vendor_base_line=$vendor_base_line" >> "$GITHUB_ENV"

### 功能修复
echo -e "${Red}- 开始功能修复"
Start_Time

# 去除 AVB2.0 校验
echo -e "${Red}- 去除 AVB2.0 校验"
"$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vbmeta.img
"$GITHUB_WORKSPACE"/tools/vbmeta-disable-verification "$GITHUB_WORKSPACE"/"${device}"/firmware-update/vbmeta_system.img

# 替换 fstab (EROFS 版本)
mv -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom.erofs "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom

# 移除 mi_ext 和 pangu (fstab)
echo -e "${Yellow}- 移除 mi_ext 和 pangu (fstab)"
sudo sed -i "/mi_ext/d" "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom
sudo sed -i "/overlay/d" "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom

# 替换 Vendor 的 fstab
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/fstab.qcom "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/fstab.qcom

# 处理 AnyKernel3 内核包
echo -e "${Red}- 解压 AnyKernel3 内核包"
mkdir -p "$GITHUB_WORKSPACE/kernel"
unzip -o "$GITHUB_WORKSPACE/"${device}"_files/"${device}"_kernel.zip" -d "$GITHUB_WORKSPACE/kernel"

# 解包 boot
echo -e "${Red}- 解包 boot.img"
mkdir -p "$GITHUB_WORKSPACE/boot_unpack"
cd "$GITHUB_WORKSPACE/boot_unpack"
"$magiskboot" unpack "$GITHUB_WORKSPACE/${device}/firmware-update/boot.img"

# 解包 vendor_boot
echo -e "${Red}- 解包 vendor_boot.img"
mkdir -p "$GITHUB_WORKSPACE/vendor_boot_unpack"
cd "$GITHUB_WORKSPACE/vendor_boot_unpack"
"$magiskboot" unpack "$GITHUB_WORKSPACE/${device}/firmware-update/vendor_boot.img"

# 替换 kernel
echo -e "${Red}- 替换 kernel"
cd "$GITHUB_WORKSPACE/boot_unpack"
[ -f "$GITHUB_WORKSPACE/kernel/Image" ] && cp -f "$GITHUB_WORKSPACE/kernel/Image" kernel

# 替换 dtb
echo -e "${Red}- 替换 dtb"
cd "$GITHUB_WORKSPACE/vendor_boot_unpack"
[ -f "$GITHUB_WORKSPACE/kernel/dtb" ] && cp -f "$GITHUB_WORKSPACE/kernel/dtb" dtb

# 重新打包 boot.img
echo -e "${Red}- 重新打包 boot.img"
cd "$GITHUB_WORKSPACE/boot_unpack"
"$magiskboot" repack "$GITHUB_WORKSPACE/${device}/firmware-update/boot.img"
mv -f new-boot.img "$GITHUB_WORKSPACE/${device}/firmware-update/boot.img"

# 重新打包 vendor_boot.img
echo -e "${Red}- 重新打包 vendor_boot.img"
cd "$GITHUB_WORKSPACE/vendor_boot_unpack"
"$magiskboot" repack "$GITHUB_WORKSPACE/${device}/firmware-update/vendor_boot.img"
mv -f new-boot.img "$GITHUB_WORKSPACE/${device}/firmware-update/vendor_boot.img"

# 替换 dtbo
echo -e "${Red}- 替换 dtbo.img"
[ -f "$GITHUB_WORKSPACE/kernel/dtbo.img" ] && cp -f "$GITHUB_WORKSPACE/kernel/dtbo.img" "$GITHUB_WORKSPACE/${device}/firmware-update/dtbo.img"

# 内置 Recovery
echo -e "${Red}- 内置 Recovery"
if [ -f "$GITHUB_WORKSPACE"/"${device}"_files/"${device}"_recovery.zip ]; then
  echo -e "${Yellow}- 解压 Recovery 镜像"
  mkdir -p "$GITHUB_WORKSPACE"/recovery_temp
  unzip -o "$GITHUB_WORKSPACE"/"${device}"_files/"${device}"_recovery.zip -d "$GITHUB_WORKSPACE"/recovery_temp
  
  if [ -f "$GITHUB_WORKSPACE"/recovery_temp/recovery.img ]; then
    echo -e "${Yellow}- 解包 Recovery 镜像获取 ramdisk.cpio"
    cd "$GITHUB_WORKSPACE"/recovery_temp
    "$magiskboot" unpack recovery.img
    cp -f "$GITHUB_WORKSPACE"/recovery_temp/ramdisk.cpio "$GITHUB_WORKSPACE"/tools/ramdisk.cpio
    cd "$GITHUB_WORKSPACE"
    
    mkdir -p "$GITHUB_WORKSPACE"/rec_boot
    cp -f "$GITHUB_WORKSPACE/${device}/firmware-update/boot.img" "$GITHUB_WORKSPACE"/rec_boot/
    cp -f "$magiskboot" "$GITHUB_WORKSPACE"/rec_boot/
    chmod +x "$GITHUB_WORKSPACE"/rec_boot/magiskboot
    cd "$GITHUB_WORKSPACE"/rec_boot || exit
    ./magiskboot unpack boot.img
    cp -f "$GITHUB_WORKSPACE"/tools/ramdisk.cpio ./ramdisk.cpio
    ./magiskboot repack boot.img boot_rec.img
    cd "$GITHUB_WORKSPACE" || exit
    cp -f "$GITHUB_WORKSPACE"/rec_boot/boot_rec.img "$GITHUB_WORKSPACE/${device}/firmware-update/boot.img"
    rm -rf "$GITHUB_WORKSPACE"/rec_boot
    rm -rf "$GITHUB_WORKSPACE"/recovery_temp
    rm -f "$GITHUB_WORKSPACE"/tools/ramdisk.cpio
  else
    echo -e "${Yellow}- 警告: recovery.img 不存在，跳过内置 Recovery"
    rm -rf "$GITHUB_WORKSPACE"/recovery_temp
  fi
else
  echo -e "${Yellow}- 警告: ${device}_recovery.zip 不存在，跳过内置 Recovery"
fi

# 清理临时目录
rm -rf "$GITHUB_WORKSPACE"/boot_unpack
rm -rf "$GITHUB_WORKSPACE"/vendor_boot_unpack
rm -rf "$GITHUB_WORKSPACE"/kernel

# 替换 Overlay 叠加层
echo -e "${Red}- 替换 Overlay 叠加层"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/overlay.zip -d "$GITHUB_WORKSPACE"/images/product/overlay

# 添加 device_features 文件
echo -e "${Red}- 添加 device_features 文件"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/device_features/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/features.zip -d "$GITHUB_WORKSPACE"/images/product/etc/device_features/

# 添加 zram 1:1 白名单
echo -e "${Red}- 添加 zram 1:1 白名单"
sudo rm -rf "$GITHUB_WORKSPACE"/images/system_ext/etc/perfinit_bdsize_zram.conf
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/perfinit_bdsize_zram.conf "$GITHUB_WORKSPACE"/images/system_ext/etc

### 统一 build.prop
echo -e "${Red}- 统一 build.prop"

sudo sed -i \
  -e "s/^ro\.build\.maintainer=.*/ro.build.maintainer=AviderMin/" \
  -e "s/^ro\.build\.contributors=.*/ro.build.contributors=YuKongA,Kyuofox,lingqiqi5211/" \
  "$GITHUB_WORKSPACE/images/system/build.prop"

### 批量处理
sudo find "$GITHUB_WORKSPACE/images/" \
  -path "$GITHUB_WORKSPACE/images/mi_ext" -prune -o \
  -type f -name 'build.prop' -print | while read -r port_build_prop; do

  sudo sed -i \
    -e "s/^build\.date=.*/build.date=${build_time}/" \
    -e "s/^build\.date\.utc=.*/build.date.utc=${build_utc}/" \
    -e "s|${port_os_version}|${vendor_os_version}|g" \
    -e "s|${port_base_line}|${origin_base_line}|g" \
    -e "s/^ro\.product\.product\.name=.*/ro.product.product.name=${device}/" \
    "$port_build_prop"

done

# EROFS 特定修改
for erofs_build_prop in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ext4' | sort); do
  sudo sed -i 's/ext4//g' "$erofs_build_prop"
done

for vendor_build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/ -type f -name "*build.prop"); do
  sudo sed -i 's/build.date=[^*]*/build.date='"${build_time}"'/' "${vendor_build_prop}"
  sudo sed -i 's/build.date.utc=[^*]*/build.date.utc='"${build_utc}"'/' "${vendor_build_prop}"
done

mi_ext_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -name "build.prop")
mod_device=$(grep '^ro\.product\.mod_device=' "$mi_ext_build_prop" | cut -d'=' -f2-)
sudo find "$GITHUB_WORKSPACE"/images/product/ -name 'build.prop' | while read -r build_prop; do
    sed -i "s/\(.*\.build\.fingerprint=.*\/\)$mod_device\(\/.*\)/\1munch\2/g" "$build_prop"
done

# 清除套壳应用
mi_ext_build_iick=$(find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl "ro.miui.support.system.app.uninstall.v2=true" | sort)
if [ -n "$mi_ext_build_iick" ]; then
  echo -e "${Red}- 开始清除套壳应用"
  for ext_build in $(find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl "ro.miui.support.system.app.uninstall.v2" | sort); do
    echo -e "${Yellow}- 定位到文件: $ext_build"
    sed -i "/ro.miui.support.system.app.uninstall.v2/d" "$ext_build"
  done
  find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -iname "*miui-uninstall*" -exec rm -f {} \;
  find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -iname "*sec_overlay*" -exec rm -f {} \;
  for files in MIUISecurityManager MIUIThemeStore; do
    appsui=$(find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${files}*")
    if [ -n "$appsui" ]; then
      echo -e "${Yellow}- 得到精简目录: $appsui"
      rm -rf "$appsui"
    fi
  done
fi

# 添加性能等级支持
for odm_build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/odm -type f -name "build.prop"); do
  sudo sed -i ''"$(sudo sed -n '/ro.odm.build.version.sdk/=' "$odm_build_prop")"'a ro.odm.build.media_performance_class=33' "$odm_build_prop"
done

rom_security=$(sudo cat "$GITHUB_WORKSPACE"/images/system/system/build.prop | grep 'ro.build.version.security_patch=' | cut -d '=' -f 2)
sudo sed -i 's/ro.vendor.build.security_patch=[^*]*/ro.vendor.build.security_patch='"$rom_security"'/' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop

rom_name=$(sudo cat "$GITHUB_WORKSPACE"/images/product/etc/build.prop | grep 'ro.product.product.name=' | cut -d '=' -f 2)
sudo sed -i 's/'"$rom_name"'/munch/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop

# 替换小米 13 的部分震动效果
echo -e "${Red}- 移植小米 13 的清理震动效果"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/vibrator_firmware.zip -d "$GITHUB_WORKSPACE"/"${device}"/vendor/firmware/

# 精简部分应用
echo -e "${Red}- 精简部分应用"
apps=("MIGalleryLockscreen" "MIpay" "MIUIDriveMode" "MIUIDuokanReader" "MIUIGameCenter" "MIUINewHome" "MIUIYoupin" "MIUIHuanJi" "MIUIMiDrive" "MIUIVirtualSim" "ThirdAppAssistant" "XMRemoteController" "MIUIVipAccount" "MiuiScanner" "Xinre" "SmartHome" "MiShop" "MiRadio" "MIUICompass" "BaiduIME" "iflytek.inputmethod" "MIService" "MIUIEmail" "MIUIVideo" "MIUIMusicT" "Health" "iFlytekIME" "OS2VipAccount")
for app in "${apps[@]}"; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/data-app/ -type d -iname "*${app}*")
  if [[ -n $appsui ]]; then
    echo -e "${Yellow}- 找到精简目录: $appsui"
    sudo rm -rf "$appsui"
  fi
done

# 移除无用组件
echo -e "${Red}- 移除无用组件"
apps=("MiAONService" "messaging" "EidService" "BSGameCenter" "subscreencenter")
for app in "${apps[@]}"; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/app/ -type d -iname "*${app}*")
  if [[ -n $appsui ]]; then
    echo -e "${Yellow}- 找到精简目录: $appsui"
    sudo rm -rf "$appsui"
  fi
done

# 分辨率修改
Find_character() {
  FIND_FILE="$1"
  FIND_STR="$2"
  if grep -q "$FIND_STR" "$FIND_FILE"; then
    Character_present=true
    echo -e "${Yellow}- 找到指定字符: $2"
  else
    Character_present=false
    echo -e "${Yellow}- !未找到指定字符: $2"
  fi
}

Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop persist.miui.density_v2
if [[ $Character_present == true ]]; then
  sudo sed -i 's/persist.miui.density_v2=[^*]*/persist.miui.density_v2=440/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a persist.miui.density_v2=440' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi

# Millet 修复
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop ro.millet.netlink
if [[ $Character_present == true ]]; then
  sudo sed -i 's/ro.millet.netlink=[^*]*/ro.millet.netlink=30/' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
else
  sudo sed -i ''"$(sudo sed -n '/ro.miui.notch/=' "$GITHUB_WORKSPACE"/images/product/etc/build.prop)"'a ro.millet.netlink=30' "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi

# 移除自适应刷新率 Pro
Find_character "$GITHUB_WORKSPACE"/images/product/etc/build.prop "ro.display.enable_pwm_switch"
if [[ $Character_present == true ]]; then
  sudo sed -i "/ro.display.enable_pwm_switch=true/d" "$GITHUB_WORKSPACE"/images/product/etc/build.prop
fi

# 迁移 Rust 应用权限文件
src="$GITHUB_WORKSPACE"/images/mi_ext/product/etc/permissions/hyperos.rustruntime_v3.xml
dst="$GITHUB_WORKSPACE"/images/product/etc/permissions/hyperos.rustruntime_v3.xml
if [ -f "$src" ]; then
  echo -e "${Yellow}- 已找到并迁移 Rust 运行时权限文件: $src -> $dst"
  sudo mkdir -p "$(dirname "$dst")"
  sudo mv -f "$src" "$dst"
fi

# 修复 Aod 异常
echo -e "${Red}- 修复 Aod 异常"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MIUIAod
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/aod.zip -d "$GITHUB_WORKSPACE"/images/product/priv-app/

# 禁用 Dolby AC4 解码
echo -e "${Red}- 禁用 Dolby AC4 解码"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/media_codecs_dolby_audio.xml
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/media_codecs_dolby_audio.xml "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/

# 桌面权限异常修复
desktop=$(sudo find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -name "system_launcher_private_permission.xml")
if [ -n "$desktop" ]; then
  echo -e "${Red}- 桌面权限异常修复"
  echo -e "${Yellow}- 找到文件: $desktop"
  sudo mv -f "$desktop" "$GITHUB_WORKSPACE"/images/product/etc/permissions/
fi

# 补全 IMS 配置
xml=$(sudo find "$GITHUB_WORKSPACE"/images/mi_ext/product/ -type f -name "vendor_miui.xml")
echo -e "${Red}- 补全 IMS 配置"
sudo mv -f "$xml" "$GITHUB_WORKSPACE"/images/product/etc/

# 分辨率修复
echo -e "${Red}- 修复分辨率异常"
sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' | while read -r file; do
  echo -e "${Yellow}- 处理文件: $file"
  sed -i '/ro\.sf\.lcd_sec_density/d' "$file"
  if grep -q '^ro\.sf\.lcd_density=' "$file"; then
    sed -i 's/^ro\.sf\.lcd_density=.*/ro.sf.lcd_density=440/' "$file"
  fi
done

# 精简无用配置
echo -e "${Red}- 精简无用配置"
keywords=("thermal.iec")
sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' -print | while read -r port_build_prop; do
  for keyword in "${keywords[@]}"; do
    while IFS= read -r line; do
      if [[ "$line" == *"$keyword"* ]]; then
        echo -e "${Yellow}- 找到指定字符: $line"
        sudo sed -i "/$line/d" "$port_build_prop"
      fi
    done < "$port_build_prop"
  done
done

# 替换相机标定
echo -e "${Red}- 替换相机标定"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/CameraTools_beta.zip -d "$GITHUB_WORKSPACE"/images/product/app/

# 替换 Rust 相册
echo -e "${Red}- 替换 Rust 相册"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/Gallery.zip -d "$GITHUB_WORKSPACE"/images/product/data-app/

# 替换 Rust 天气
echo -e "${Red}- 替换 Rust 天气"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/Weather.zip -d "$GITHUB_WORKSPACE"/images/product/data-app/

# 部分机型指纹支付相关服务存在于 Product，需要清除
echo -e "${Red}- 清除多余指纹支付服务"
for files in IFAAService MipayService SoterService TimeService; do
  appsui=$(sudo find "$GITHUB_WORKSPACE"/images/product/ -type d -iname "*${files}*")
  if [[ -n "$appsui" ]]; then
    echo -e "${Yellow}- 找到服务目录: $appsui"
    sudo rm -rf "$appsui"
  fi
done

# 占位广告应用
echo -e "${Red}- 占位广告应用"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/app/MSA/*
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MSA.apk "$GITHUB_WORKSPACE"/images/product/app/MSA

# 禁用设备硬件编解码器
echo -e "${Red}- 禁用设备硬件编解码器"
system_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/system/system/ -type f -name "build.prop")
system_keyvalues=(
  "media.stagefright.thumbnail.prefer_hw_codecs=false"
)
for kv in "${system_keyvalues[@]}"; do
  key="${kv%%=*}"
  value="${kv#*=}"
  if grep -q "^$key=" "$system_build_prop"; then
    prop=$(grep "^$key=" "$system_build_prop" | cut -d'=' -f2-)
    if [ "$prop" != "$value" ]; then
      sed -i "s|^$key=.*|$key=$value|" "$system_build_prop"
    fi
  else
    sed -i "/# end of file/i $kv" "$system_build_prop"
  fi
done

# 添加 Props
echo -e "${Red}- 添加 Props"
product_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/product/ -type f -name "build.prop")
keyvalues=(
  "ro.vendor.audio.dolby.spatial.profile=dynamic"
  "ro.vendor.display.touch.idle.enable=true"
  "ro.vendor.display.idle_default_fps=120"
  "ro.vendor.display.idle_default_fps.support=true"
  "ro.vendor.display.fod_monitor_default_fps=120"
  "persist.vendor.disable_idle_fps=true"
  "ro.vendor.display.ltpo.sync.tp=false"
  "ro.vendor.mi_sf.ltpo.support=true"
  "ro.vendor.mi_sf.enable_tp_idle_automode=true"
  "ro.vendor.mi_sf.enable_automode_for_maxfps_setting=true"
  "ro.vendor.mi_sf.support_automode_for_normalfps=true"
  "ro.vendor.mi_sf.set_gradient_idle_timer_ms=50000"
  "ro.vendor.mi_sf.support_gradient_idleframerate=true"
  "ro.vendor.display.video_or_camera_fps.support=true"
  "ro.vendor.display.set_fps_stat_timer_ms=250"
  "ro.miui.surfaceflinger_affinity=4-7"
  "ro.miui.affinity.sfui=4-7"
  "ro.miui.affinity.sfre=4-7"
  "ro.miui.affinity.sfuireset=4-7"
  "dalvik.vm.dex2oat-swap=true"
  "dalvik.vm.boot-dex2oat-cpu-set=0,1,2,3,4,5,6,7"
  "dalvik.vm.background-dex2oat-cpu-set=0,1,2,3,4,5,6,7"
  "debug.sf.set_idle_timer_ms=110"
  "persist.sys.miui_animator_sched.bigcores=4-6"
  "persist.sys.miui_animator_sched.sched_threads=2"
  "persist.sys.miui.sf_cores=4-7"
  "persist.vendor.display.miui.composer_boost=4-7"
  "persist.sys.miui_animator_sched.big_prime_cores=4-7"
  "persist.sys.minfree_def=73728,92160,110592,154832,482560,579072"
  "persist.sys.minfree_6g=73728,92160,110592,258048,663552,903168"
  "persist.sys.minfree_8g=73728,92160,110592,387072,1105920,1451520"
  "ro.surface_flinger.use_content_detection_for_refresh_rate=true"
  "ro.surface_flinger.set_idle_timer_ms=2147483647"
  "ro.surface_flinger.set_touch_timer_ms=2147483647"
  "ro.surface_flinger.set_display_power_timer_ms=2147483647"
  "persist.miui.extm.dm_opt.enable=true"
  "debug.game.video.support=true"
  "debug.game.video.speed=true"
  "sys.haptic.down=0,2"
  "sys.haptic.tap.normal=0,2"
  "sys.haptic.tap.light=0,2"
  "sys.haptic.flick=0,2"
  "sys.haptic.flick.light=0,2"
  "sys.haptic.switch=0,2"
  "sys.haptic.mesh.heavy=0,2"
  "sys.haptic.mesh.normal=0,2"
  "sys.haptic.mesh.light=0,2"
  "sys.haptic.long.press=0,2"
  "sys.haptic.popup.normal=0,2"
  "sys.haptic.popup.light=0,2"
  "sys.haptic.pickup=0,2"
  "sys.haptic.scroll.edge=0,2"
  "sys.haptic.trigger.drawer=0,2"
  "sys.haptic.hold=0,2"
)
for kv in "${keyvalues[@]}"; do
  key="${kv%%=*}"
  value="${kv#*=}"
  if grep -q "^$key=" "$product_build_prop"; then
    prop=$(grep "^$key=" "$product_build_prop" | cut -d'=' -f2-)
    if [ "$prop" != "$value" ]; then
      sed -i "s|^$key=.*|$key=$value|" "$product_build_prop"
    fi
  else
    sed -i "/# end of file/i $kv" "$product_build_prop"
  fi
done

# 启用 AutoSingleLayer
echo -e "${Red}- 启用 AutoSingleLayer"
for vendor_build_prop in $(sudo find "$GITHUB_WORKSPACE"/"${device}"/ -type f -name "*build.prop"); do
  sudo sed -i 's/debug.sf.latch_unsignaled=[^*]*/debug.sf.latch_unsignaled='0'/' "${vendor_build_prop}"
  sudo sed -i 's/debug.sf.auto_latch_unsignaled=[^*]*/debug.sf.auto_latch_unsignaled='1'/' "${vendor_build_prop}"
done

# 常规修改
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/recovery-from-boot.p
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/vendor/bin/install-recovery.sh
sudo unzip -o -q "$GITHUB_WORKSPACE"/tools/flashtools.zip -d "$GITHUB_WORKSPACE"/images

# 相机修复
echo -e "${Red}- 相机修复"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/*
sudo cat "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.1 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.2 "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk.3 >"$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk
sudo cp -f "$GITHUB_WORKSPACE"/"${device}"_files/MiuiCamera.apk "$GITHUB_WORKSPACE"/images/product/priv-app/MiuiCamera/

# 修复卡第一屏
echo -e "${Red}- 修复卡第一屏"
sudo find "$GITHUB_WORKSPACE"/images/product/ -name 'build.prop' | while read -r build_prop; do
  sed -i 's/persist\.sys\.enhance_vkpipelinecache\.enable=true/persist.sys.enhance_vkpipelinecache.enable=false/g' "$build_prop"
done

# 第一屏重启修复 - 补全 apex
echo -e "${Red}- 补全 apex"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/apex.zip -d "$GITHUB_WORKSPACE"/images/system_ext/apex/
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/apex_ext.zip -d "$GITHUB_WORKSPACE"/images/system_ext/apex/

# 修复开机设备错误弹窗
echo -e "${Red}- 修复开机设备错误弹窗"
cp -f "$GITHUB_WORKSPACE"/"${device}"_files/manifest.xml "$GITHUB_WORKSPACE"/images/system_ext/etc/vintf/

# 修复基带丢失
echo -e "${Red}- 修复基带丢失"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/lyra.zip -d "$GITHUB_WORKSPACE"/images/product/app/

# 替换开机动画
echo -e "${Red}- 替换开机动画"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/media/bootanimation.zip
sudo mv -f "$GITHUB_WORKSPACE"/"${device}"_files/bootanimation.zip "$GITHUB_WORKSPACE"/images/product/media

# 人脸修复
echo -e "${Red}- 人脸修复"
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/face.zip -d "$GITHUB_WORKSPACE"/images/product/app/

# 修复自动亮度/移除高温降亮度
echo -e "${Red}- 自动亮度修复"
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/*
sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/displayconfig.zip -d "$GITHUB_WORKSPACE"/images/product/etc/displayconfig/

# 修复机型为 POCO 时最近任务崩溃
echo -e "${Red}- 修复机型为 POCO 时最近任务崩溃"
sudo sed -i 's/com.mi.android.globallauncher/com.miui.home/' "$GITHUB_WORKSPACE"/images/system_ext/etc/init/init.miui.ext.rc

# NFC 修复
echo -e "${Red}- NFC 修复"
nfcnq=$(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name "NQNfcNci.apk")
if [ ! -f "$nfcnq" ]; then
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/nfc_app.zip -d "$GITHUB_WORKSPACE"/images/product/pangu/system/app/
  sudo unzip -o -q "$GITHUB_WORKSPACE"/"${device}"_files/nfc_framework.zip -d "$GITHUB_WORKSPACE"/images/product/pangu/system/
fi

# 删除多余的 NFC 服务
echo -e "${Red}- 删除多余的 NFC 服务"
keywords=("Nfc_st" "com.st.android.nfc_extensions" "StNfcExtensionService")
for kw in "${keywords[@]}"; do
    find "$GITHUB_WORKSPACE"/images/ -depth -type d -iname "*${kw}*" -exec rm -rf {} +
done

# 移除 mi_ext 和 pangu (product)
pangu="$GITHUB_WORKSPACE"/images/product/pangu/system
sudo find "$pangu" -type d | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
sudo find "$pangu" -type f | sed 's/\./\\./g' | sed "s|$pangu|/system/system|g" | sed 's/$/ u:object_r:system_file:s0/' >>"$GITHUB_WORKSPACE"/images/config/system_file_contexts
sudo cp -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/* "$GITHUB_WORKSPACE"/images/system/system/
sudo rm -rf "$GITHUB_WORKSPACE"/images/product/pangu/system/*

# 补全移除 mi_ext 和 pangu 后所缺失的叠加层
echo -e "${Red}- 补全叠加层"
find "$GITHUB_WORKSPACE"/images/mi_ext/product/overlay -type f -name "*.apk" | while read -r overlays; do
  echo -e "${Yellow}- 找到文件: $overlays"
  if [[ "$overlays" == *MiuiStkResOverlay.apk ]]; then
    file_size=$(stat -c %s "$overlays")
  fi
  mv -f "$overlays" "$GITHUB_WORKSPACE"/images/product/overlay/
  if [[ "$overlays" == *MiuiStkResOverlay.apk ]]; then
    original_dir=$(dirname "$overlays")
    truncate -s "$file_size" "$original_dir/MiuiStkResOverlay.apk"
  fi
done

# 系统更新获取更新路径对齐
echo -e "${Red}- 系统更新获取更新路径对齐"
for mod_device_build in $(sudo find "$GITHUB_WORKSPACE"/images/ -type f -name 'build.prop' 2>/dev/null | xargs grep -rl 'ro.product.mod_device=' | sort); do
  if echo "${date}" | grep -q "XM" || echo "${date}" | grep -q "DEV"; then
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=munch/' "$mod_device_build"
  else
    sudo sed -i 's/ro.product.mod_device=[^*]*/ro.product.mod_device=munch_pre/' "$mod_device_build"
  fi
done

# 补全版本信息
echo -e "${Red}- 补全版本信息"
product_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/product/ -type f -name "build.prop")
mi_ext_build_prop=$(sudo find "$GITHUB_WORKSPACE"/images/mi_ext/ -type f -name "build.prop")
while IFS= read -r line; do
  echo -e "${Yellow}- 找到字符: $line"
  sudo sed -i "/ro.product.build.version.sdk_full/a\\$line" "$product_build_prop"
done < "$mi_ext_build_prop"

# 修复贴贴分享 (OS3.1及以上)
sudo mkdir -p "$GITHUB_WORKSPACE"/images/system/mi_ext/product/etc/cust_features
sudo mv "$GITHUB_WORKSPACE"/images/mi_ext/product/etc/cust_features/* "$GITHUB_WORKSPACE"/images/system/mi_ext/product/etc/cust_features
sudo cp -rf "$GITHUB_WORKSPACE"/"${device}"_files/device_features.xml -d "$GITHUB_WORKSPACE"/images/system/mi_ext/product/etc/cust_features/
sudo sed -i "/ro.vendor.nfc.mibeam/d" "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
sudo sed -i ''"$(sudo sed -n '/ro.vendor.nfc.repair/=' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop)"'a ro.vendor.nfc.mitouch=1' "$GITHUB_WORKSPACE"/"${device}"/vendor/build.prop
sudo find "$GITHUB_WORKSPACE"/"${device}"/vendor/etc/permissions -type f -iname "*beam*.xml" -delete

# 修复 Google 功能
sudo mkdir -p "$GITHUB_WORKSPACE"/images/product/etc/permissions
sudo cp -rf "$GITHUB_WORKSPACE"/"${device}"_files/cn.google.services.xml "$GITHUB_WORKSPACE"/images/product/etc/permissions/

# 替换更改文件/删除多余文件
echo -e "${Red}- 替换更改文件/删除多余文件"
sudo rm -rf "$GITHUB_WORKSPACE"/images/odm
sudo rm -rf "$GITHUB_WORKSPACE"/images/config/*odm*
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/system_ext
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"/config/*system_ext*
sudo cp -r "$GITHUB_WORKSPACE"/"${device}"/* "$GITHUB_WORKSPACE"/images
sudo mv "$GITHUB_WORKSPACE"/images/firmware-update/boot.img "$GITHUB_WORKSPACE"/images/
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"
sudo rm -rf "$GITHUB_WORKSPACE"/"${device}"_files
End_Time 功能修复
### 功能修复结束

### 生成 super.img (EROFS)
echo -e "${Red}- 开始打包 super.img"
Start_Time

partitions=("mi_ext" "odm" "product" "system" "system_ext" "vendor")

for partition in "${partitions[@]}"; do
  echo -e "${Red}- 正在生成: $partition"
  sudo python3 "$GITHUB_WORKSPACE"/tools/fspatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config
  sudo python3 "$GITHUB_WORKSPACE"/tools/contextpatch.py "$GITHUB_WORKSPACE"/images/$partition "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts None
  Start_Time
  sudo $erofs_mkfs --quiet -zlz4hc,9 -T 1230768000 --mount-point /$partition --fs-config-file "$GITHUB_WORKSPACE"/images/config/"$partition"_fs_config --file-contexts "$GITHUB_WORKSPACE"/images/config/"$partition"_file_contexts "$GITHUB_WORKSPACE"/images/$partition.img "$GITHUB_WORKSPACE"/images/$partition
  End_Time "打包 $partition (erofs)"
  eval "$partition"_size=$(du -sb "$GITHUB_WORKSPACE"/images/$partition.img | awk {'print $1'})
  sudo rm -rf "$GITHUB_WORKSPACE"/images/$partition
done

sudo rm -rf "$GITHUB_WORKSPACE"/images/config

Start_Time
$lpmake --metadata-size 65536 --super-name super --block-size 4096 \
  --partition mi_ext_a:readonly:"$mi_ext_size":qti_dynamic_partitions_a \
  --image mi_ext_a="$GITHUB_WORKSPACE"/images/mi_ext.img \
  --partition mi_ext_b:readonly:0:qti_dynamic_partitions_b \
  --partition odm_a:readonly:"$odm_size":qti_dynamic_partitions_a \
  --image odm_a="$GITHUB_WORKSPACE"/images/odm.img \
  --partition odm_b:readonly:0:qti_dynamic_partitions_b \
  --partition product_a:readonly:"$product_size":qti_dynamic_partitions_a \
  --image product_a="$GITHUB_WORKSPACE"/images/product.img \
  --partition product_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_a:readonly:"$system_size":qti_dynamic_partitions_a \
  --image system_a="$GITHUB_WORKSPACE"/images/system.img \
  --partition system_b:readonly:0:qti_dynamic_partitions_b \
  --partition system_ext_a:readonly:"$system_ext_size":qti_dynamic_partitions_a \
  --image system_ext_a="$GITHUB_WORKSPACE"/images/system_ext.img \
  --partition system_ext_b:readonly:0:qti_dynamic_partitions_b \
  --partition vendor_a:readonly:"$vendor_size":qti_dynamic_partitions_a \
  --image vendor_a="$GITHUB_WORKSPACE"/images/vendor.img \
  --partition vendor_b:readonly:0:qti_dynamic_partitions_b \
  --device super:8589934592 \
  --metadata-slots 3 \
  --group qti_dynamic_partitions_a:8589934592 \
  --group qti_dynamic_partitions_b:8589934592 \
  --virtual-ab -F \
  --output "$GITHUB_WORKSPACE"/images/super.img
End_Time "打包 super.img"

for partition in "${partitions[@]}"; do
  rm -rf "$GITHUB_WORKSPACE"/images/$partition.img
done
### 生成 super.img 结束

### 输出刷机包
echo -e "${Red}- 开始生成刷机包"
echo -e "${Red}- 开始压缩 super.zst"
Start_Time
sudo find "$GITHUB_WORKSPACE"/images/ -exec touch -t 200901010000.00 {} \;
zstd -3 -f "$GITHUB_WORKSPACE"/images/super.img -o "$GITHUB_WORKSPACE"/images/super.zst --rm
End_Time "压缩 super.zst"

echo -e "${Red}- 生成刷机包"
Start_Time
sudo $a7z a "$GITHUB_WORKSPACE"/zip/${device}-2in1_full-${port_os_version}.zip "$GITHUB_WORKSPACE"/images/* >/dev/null
sudo rm -rf "$GITHUB_WORKSPACE"/images
End_Time "压缩卡刷包"

echo -e "${Red}- 定制 ROM 包名"
md5=$(md5sum "$GITHUB_WORKSPACE"/zip/${device}-2in1_full-${port_os_version}.zip)
echo "MD5=${md5:0:32}" >>$GITHUB_ENV
zip_md5=${md5:0:10}
rom_name="${device}-2in1_full-${port_os_version}-user-${android_version}.0-${zip_md5}-EROFS.zip"
sudo mv "$GITHUB_WORKSPACE"/zip/${device}-2in1_full-${port_os_version}.zip "$GITHUB_WORKSPACE"/zip/"${rom_name}"
echo "rom_name=$rom_name" >>$GITHUB_ENV
### 输出刷机包结束
