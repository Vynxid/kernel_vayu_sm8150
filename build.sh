#!/bin/bash

# Directories
kernel_dir="${PWD}"
objdir="${kernel_dir}/out"
ANYKERNEL="/workspace/jale/AnyKernel3"
DISPLAY="arch/arm64/boot/dts/qcom/xiaomi/overlay/common/display"
MKDTBOIMG="/workspace/jale/libufdt/utils/src/mkdtboimg.py"
CLANG_DIR="/workspace/jale/clang"
GCC64_DIR="/workspace/jale/gcc64/aarch64--glibc--stable-2024.05-1"
GCC32_DIR="/workspace/jale/gcc32"
patch_file="ksu-susfs.patch"

# Variables
export ARCH="arm64"
export CONFIG_FILE="vayu_defconfig"
export KBUILD_BUILD_HOST="AnymoreProject"
export KBUILD_BUILD_USER="t.me"
export KBUILD_BUILD_FEATURES="Dev-Jale"
export PATH="$CLANG_DIR/bin:$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH"

# Colors
NC='\033[0m'
RED='\033[0;31m'
LGR='\033[1;32m'

echo -e "${LGR}==> Checking toolchain...${NC}"
if ! [ -d "$CLANG_DIR" ]; then
    echo "Toolchain not found! Cloning to $CLANG_DIR..."
    git clone --depth=1 https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git -b 15.0 $CLANG_DIR || {
        echo -e "${RED}Failed to clone clang!${NC}"
        exit 1
    }
fi

echo -e "${LGR}==> Applying SUSFS Patch...${NC}"
if [ -f "$patch_file" ]; then
    git apply --whitespace=fix "$patch_file" || {
        echo -e "${RED}Failed to apply patch!${NC}"
        exit 1
    }
else
    echo -e "${RED}Patch file not found: $patch_file${NC}"
    exit 1
fi

echo -e "${LGR}==> Injecting KernelSU + SUSFS config...${NC}"
cat <<EOF >> arch/arm64/configs/$CONFIG_FILE

# KernelSU + SUSFS
CONFIG_KSU=y
CONFIG_KSU_DEBUG=y
CONFIG_KSU_LSM_SECURITY_HOOKS=y
CONFIG_KSU_SUSFS=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=n
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_SUS_SU=y
EOF

echo -e "${LGR}==> Generating defconfig...${NC}"
make -s ARCH=${ARCH} O=${objdir} ${CONFIG_FILE} -j$(nproc)

echo -e "${LGR}==> Starting kernel compilation...${NC}"
make -j$(nproc) \
  O=${objdir} \
  ARCH=arm64 \
  SUBARCH=arm64 \
  CLANG_TRIPLE=aarch64-linux-gnu- \
  CROSS_COMPILE=aarch64-linux-gnu- \
  CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
  CROSS_COMPILE_COMPAT=arm-linux-gnueabi- \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  STRIP=llvm-strip \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  READELF=llvm-readelf \
  HOSTCC=clang \
  HOSTCXX=clang++ \
  HOSTAR=llvm-ar \
  HOSTLD=ld.lld \
  LLVM=1 \
  LLVM_IAS=1 \
  CC="ccache clang"

echo -e "${LGR}==> Patching MIUI panel values...${NC}"
sed -i 's/<70>/<695>/g'   $DISPLAY/dsi-panel-j20s-36-02-0a-lcd-dsc-vid.dtsi
sed -i 's/<154>/<1546>/g' $DISPLAY/dsi-panel-j20s-36-02-0a-lcd-dsc-vid.dtsi
sed -i 's/<70>/<695>/g'   $DISPLAY/dsi-panel-j20s-42-02-0b-lcd-dsc-vid.dtsi
sed -i 's/<154>/<1546>/g' $DISPLAY/dsi-panel-j20s-42-02-0b-lcd-dsc-vid.dtsi

echo -e "${LGR}==> Generating dtbo.img & dtb...${NC}"
python3 $MKDTBOIMG create $ANYKERNEL/dtbo.img --page_size=4096 out/arch/arm64/boot/dts/qcom/vayu-sm8150-overlay.dtbo
find out/arch/arm64/boot/dts/qcom -name 'sm8150-v2*.dtb' -exec cat {} + > $ANYKERNEL/dtb
python3 $MKDTBOIMG create $ANYKERNEL/dtbo-miui.img --page_size=4096 out/arch/arm64/boot/dts/qcom/vayu-sm8150-overlay.dtbo

echo -e "${LGR}==> Restoring MIUI panel files...${NC}"
git restore $DISPLAY/dsi-panel-j20s-36-02-0a-lcd-dsc-vid.dtsi
git restore $DISPLAY/dsi-panel-j20s-42-02-0b-lcd-dsc-vid.dtsi

echo -e "${LGR}==> Build complete. Verifying output...${NC}"
if [[ -f "$objdir/arch/arm64/boot/Image" && -f "$ANYKERNEL/dtbo.img" ]]; then
  echo -e "${LGR}############################################"
  echo -e "${LGR}############# OkThisIsEpic!  ##############"
  echo -e "${LGR}############################################${NC}"
  exit 0
else
  echo -e "${RED}############################################"
  echo -e "${RED}##         This Is Not Epic :'(          ##"
  echo -e "${RED}############################################${NC}"
  exit 1
fi
