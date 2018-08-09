#
# Set up LXD
#

set -u
set -e

echo "Updating package list..."
sudo apt-get -y update

echo "Removing old LXD..."
sudo apt-get -y remove lxd lxd-client
sudo apt-get -y autoremove

echo "Installing Snap..."
sudo apt-get -y install snapd
echo "PATH=/snap/bin:$PATH" | sudo tee -a /etc/environment
export PATH=/snap/bin:$PATH

echo "Installing LXD from Snap (APT's version is too old)..."
sudo snap install lxd

if [ ! -e "$LXC_BIN" ]; then
    echo "LXC binary does not exist or is not executable at path $LXC_BIN."
    exit 1
fi

echo "Waiting for LXD to start..."
sudo snap start lxd
sudo lxd waitready

echo "Initializing LXD..."
sudo lxd init --auto --storage-backend=dir || echo "Already initialized?"

echo "Removing linuxcontainers.org repo..."
sudo $LXC_BIN remote remove images || echo "Not here?"

LXD_PROFILE=travis
if [[ $(sudo $LXC_BIN profile list | grep $LXD_PROFILE | wc -l) -eq 0 ]]; then
    echo "Creating LXD profile..."
    sudo $LXC_BIN profile create $LXD_PROFILE
    sudo $LXC_BIN profile set $LXD_PROFILE security.privileged true
fi

LXD_STORAGE_POOL=travis
if [[ $(sudo $LXC_BIN storage list | grep $LXD_STORAGE_POOL | wc -l) -eq 0 ]]; then
    echo "Setting up LXD storage pool..."
    sudo $LXC_BIN storage create $LXD_STORAGE_POOL dir
    sudo $LXC_BIN profile device add $LXD_PROFILE root disk path=/ pool=$LXD_STORAGE_POOL
fi

LXD_BRIDGE_INTERFACE=travisbr0
if [[ $(sudo $LXC_BIN network list | grep $LXD_BRIDGE_INTERFACE | wc -l) -eq 0 ]]; then
    echo "Setting up LXD networking..."
    sudo $LXC_BIN network create $LXD_BRIDGE_INTERFACE
    sudo $LXC_BIN network attach-profile $LXD_BRIDGE_INTERFACE $LXD_PROFILE eth0
fi
