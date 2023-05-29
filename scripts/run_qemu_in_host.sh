#!/bin/bash
set -o errexit
set -o nounset
set -o xtrace

IMG_RELEASE_URL="https://cloud-images.ubuntu.com/releases/focal/release-20210125"
IMG_RELEASE_UNPACKED_URL="${IMG_RELEASE_URL}/unpacked"
IMG_NAME="ubuntu-20.04-server-cloudimg-amd64.img"
KERNEL_NAME="ubuntu-20.04-server-cloudimg-amd64-vmlinuz-generic"
INITRD_NAME="ubuntu-20.04-server-cloudimg-amd64-initrd-generic"
KERNEL_VERSION="linux-headers-5.4.0-64-generic"
DEMO_PATH="/home/${USER}/cosim_demo"
QEMU_TARGET="qemu-system-x86_64"
UBUNTU_IMG_PATH="${DEMO_PATH}/${IMG_NAME}"
UBUNTU_KERNEL_PATH="${DEMO_PATH}/${KERNEL_NAME}"
UBUNTU_INITRD_PATH="${DEMO_PATH}/${INITRD_NAME}"
BIOS_PATH="${DEMO_PATH}/xilinx-qemu/pc-bios/bios-256k.bin"
CLOUD_CONFIG_IMG_PATH="${DEMO_PATH}/cloud_init.img"
TEMP_FILE_PATH="/tmp/machine-x86-qdma-demo"
DOCKER_DRIVER_PATH="/tmp/driver"
TEST_LOG_FILE_PATH="${TEMP_FILE_PATH}/test.log"
IMG_SIZE="10G"
VM_MEM_SIZE="4G"
VM_SMP_NUM="4"
VM_SSH_PORT="22"
VM_SSH_PORT_IN_HOST="2222"
RP_PCIE_SLOT_NUM="0"
RP_CHAN_NUM="0"
PCIE_ROOT_SLOT_NUM="1"

# Copy scripts
cp scripts/run_test_in_qemu.sh $TEMP_FILE_PATH
cloud-localds $CLOUD_CONFIG_IMG_PATH scripts/cloud_init.cfg

# Create demo path
mkdir -p $DEMO_PATH
cp scripts/Dockerfile $DEMO_PATH
cd $DEMO_PATH

# Download OS images
wget -q $IMG_RELEASE_URL/$IMG_NAME
wget -q $IMG_RELEASE_UNPACKED_URL/$KERNEL_NAME
wget -q $IMG_RELEASE_UNPACKED_URL/$INITRD_NAME
qemu-img resize $DEMO_PATH/$IMG_NAME $IMG_SIZE

# Download and make QDMA driver for VM
docker build -t dma-driver-builder .
docker run --rm -v $TEMP_FILE_PATH:$DOCKER_DRIVER_PATH dma-driver-builder

# Build Xilinx QEMU
sudo apt update
sudo apt install -y build-essential pkg-config zlib1g-dev libglib2.0-dev libpixman-1-dev libfdt-dev ninja-build \
libcap-ng-dev libattr1-dev

git clone https://github.com/GTwhy/xilinx-qemu.git
cd xilinx-qemu
mkdir qemu_build
cd qemu_build
../configure  --target-list=x86_64-softmmu --enable-virtfs
make -j
sudo make install

# non-kvm version
$QEMU_TARGET \
    -M q35,kernel-irqchip=split -cpu qemu64,rdtscp \
    -m $VM_MEM_SIZE -smp $VM_SMP_NUM -display none -no-reboot \
    -serial mon:stdio \
    -drive file=$UBUNTU_IMG_PATH \
    -drive file=$CLOUD_CONFIG_IMG_PATH,format=raw \
    -kernel $UBUNTU_KERNEL_PATH \
    -initrd $UBUNTU_INITRD_PATH \
    -bios $BIOS_PATH \
    -machine-path $TEMP_FILE_PATH \
    -netdev type=user,id=net0,hostfwd=tcp::$VM_SSH_PORT_IN_HOST-:$VM_SSH_PORT \
    -device intel-iommu,intremap=on,device-iotlb=on \
    -device ioh3420,id=rootport1,slot=$PCIE_ROOT_SLOT_NUM \
    -device remote-port-pci-adaptor,bus=rootport1,id=rp0 \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=shared \
    -device remote-port-pcie-root-port,id=rprootport,slot=$RP_PCIE_SLOT_NUM,rp-adaptor0=rp,rp-chan0=$RP_CHAN_NUM \
    -fsdev local,security_model=mapped,id=fsdev0,path=$TEMP_FILE_PATH \
    -append "root=/dev/sda1 rootwait console=tty1 console=ttyS0 intel_iommu=on"

sudo cat $TEMP_FILE_PATH/test.log

# Check log file
if [ ! -f "$TEST_LOG_FILE_PATH" ]
then
    echo "${TEST_LOG_FILE_PATH} not found."
    exit 1
fi

if grep -q -e "FAILED" $TEST_LOG_FILE_PATH
then
    echo "Error: FAILED found in $TEST_LOG_FILE_PATH"
    exit 1
else
    echo "Success: No FAILED or error found in $TEST_LOG_FILE_PATH"
fi

# # kvm version
# $QEMU_TARGET \
#     -M q35,accel=kvm,kernel-irqchip=split -cpu qemu64,rdtscp \
#     -m 4G -smp 4 -enable-kvm -display none \
#     -serial mon:stdio \
#     -device intel-iommu,intremap=on,device-iotlb=on \
#     -drive file=$UBUNTU_IMG_PATH \
#     -drive file=$CLOUD_CONFIG_IMG_PATH,format=raw \
#     -device ioh3420,id=rootport1,slot=1 \
#     -device remote-port-pci-adaptor,bus=rootport1,id=rp0 \
#     -machine-path ${TEMP_FILE_PATH} \
#     -device virtio-net-pci,netdev=net0 -netdev type=user,id=net0,hostfwd=tcp::2222-:22\
#     -device remote-port-pcie-root-port,id=rprootport,slot=0,rp-adaptor0=rp,rp-chan0=0 \
#     -fsdev local,security_model=mapped,id=fsdev0,path=$TEMP_FILE_PATH \
#     -device virtio-9p-pci,id=fs0,fsdev=fsdev0,mount_tag=shared
