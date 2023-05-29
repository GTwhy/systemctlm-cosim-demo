# Choose ubuntu 20.04 as base image
FROM ubuntu:20.04

# Set environment variables
ENV DEBIAN_FRONTEND=noninteractive KERNEL_VERSION=linux-headers-5.4.0-64-generic TEMP_FILE_PATH=/tmp/driver

# Update the source list and install required packages
RUN apt update && \
    apt install -y build-essential pkg-config zlib1g-dev libglib2.0-dev libpixman-1-dev libfdt-dev ninja-build \
    libcap-ng-dev libattr1-dev libelf-dev libaio-dev git $KERNEL_VERSION

# Clone the QDMA driver
RUN git clone https://github.com/Xilinx/dma_ip_drivers.git

# Build the driver
WORKDIR dma_ip_drivers/QDMA/linux-kernel
RUN make TANDEM_BOOT_SUPPORTED=1 KDIR=/usr/src/$KERNEL_VERSION && \
    mkdir -p $TEMP_FILE_PATH

# Move the built driver to the temp path
CMD mv /dma_ip_drivers $TEMP_FILE_PATH
