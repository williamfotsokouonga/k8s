#!/bin/sh
# Source: http://kubernetes.io/docs/getting-started-guides/kubeadm

set -e
source /etc/lsb-release
echo "################################# "
echo "You're using: ${DISTRIB_DESCRIPTION}"

KUBERNETES_VERSION=1.33
CONTAINERD_VERSION=2.0.4
CRICTL_VERSION=1.33.0
RUNC_VERSION=1.3.0
CNI_VERSION=1.7.1
ETCDCTL_VERSION=v3.5.21
IPADDR=$(hostname -I | awk '{print $1}')
NODENAME=$(hostname -s)
POD_CIDR="192.168.0.0/16"

# get platform
PLATFORM=`uname -p`

if [ "${PLATFORM}" == "aarch64" ]; then
  PLATFORM="arm64"
elif [ "${PLATFORM}" == "x86_64" ]; then
  PLATFORM="amd64"
else
  echo "${PLATFORM} has to be either amd64 or arm64/aarch64. Check containerd supported binaries page"
  echo "https://github.com/containerd/containerd/blob/main/docs/getting-started.md#option-1-from-the-official-binaries"
  exit 1
fi

### setup terminal ###
cd /etc/apt/sources.list.d/
ls -lrt
sudo chmod 755 *
sudo rm -rf devel*
sudo apt-get --allow-unauthenticated update
sudo apt-get --allow-unauthenticated upgrade
sudo apt-get --allow-unauthenticated install -y bash-completion binutils curl wget
echo 'colorscheme ron' >> ~/.vimrc
echo 'set tabstop=2' >> ~/.vimrc
echo 'set shiftwidth=2' >> ~/.vimrc
echo 'set expandtab' >> ~/.vimrc
echo 'source <(kubectl completion bash)' >> ~/.bashrc
echo 'alias k=kubectl' >> ~/.bashrc
echo 'alias c=clear' >> ~/.bashrc
echo 'complete -F __start_kubectl k' >> ~/.bashrc
sudo sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc

### 1 - Disable linux Swap Remove any existing swap partitions
echo "### 1 - DISABLE SWAP ###"
sudo swapoff -a
sudo sed -i '/\sswap\s/ s/^\(.*\)$/#\1/g' /etc/fstab

### 2 - Enable Iptables bridge traffic
echo "### 2 - ENABLE IPTABLE BRIDGE TRAFFIC ###"
sudo cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

### 3 - install containerd
echo "### 3 - INSTALL CONTAINERD ###"
sudo mkdir -p /etc/containerd
sudo wget https://github.com/containerd/containerd/releases/download/v${CONTAINERD_VERSION}/containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
sudo tar Cxzvf /usr/local containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
sudo curl -LO https://raw.githubusercontent.com/containerd/containerd/main/containerd.service
sudo mkdir -p /usr/local/lib/systemd/system/
sudo mv containerd.service /usr/local/lib/systemd/system/
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup \= false/SystemdCgroup \= true/g' /etc/containerd/config.toml
sudo chmod 755 /etc/containerd/config.toml
sudo systemctl daemon-reload
sudo systemctl enable --now containerd
sudo rm -rf containerd-${CONTAINERD_VERSION}-linux-${PLATFORM}.tar.gz
sudo systemctl unmask containerd
sudo systemctl start containerd
containerd --version

### 4 - Install runC
echo "### 4 - INSTALL RUNC ###"
sudo curl -LO https://github.com/opencontainers/runc/releases/download/v$RUNC_VERSION/runc.amd64
sudo install -m 755 runc.amd64 /usr/local/sbin/runc
runc --version

### 5 - Install CRICTL
echo "### 5 - INSTALL CRICTL ###"
sudo wget https://github.com/kubernetes-sigs/cri-tools/releases/download/v$CRICTL_VERSION/crictl-v$CRICTL_VERSION-linux-amd64.tar.gz
sudo tar zxvf crictl-v$CRICTL_VERSION-linux-amd64.tar.gz -C /usr/local/bin
sudo rm -f crictl-v$CRICTL_VERSION-linux-amd64.tar.gz
crictl --version

### 6 - Install  CNI
echo "### 6 - INSTALL CNI ###"
sudo curl -LO https://github.com/containernetworking/plugins/releases/download/v$CNI_VERSION/cni-plugins-linux-amd64-v$CNI_VERSION.tgz
sudo mkdir -p /opt/cni/bin
sudo tar Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v$CNI_VERSION.tgz
ls -lrt /opt/cni/bin

### 7 - Install KUBEADM KUBELET KUBECTL
echo "### 7 - INSTALL KUBEADM KUBELET KUBECTL ###"
sudo apt-get update -y
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update -y
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo apt-get install -y jq
local_ip="$(ip --json addr show eth0 | jq -r '.[0].addr_info[] | select(.family == "inet") | .local')"
sudo cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
EOF
sudo apt-mark hold kubelet kubeadm kubectl kubernetes-cni
kubeadm version
kubelet --version
kubectl version --client

### 8 - Configure CRICTL
echo "### 8 - CONFIGURE CRICTL ###"
sudo cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 30
debug: true
EOF
crictl --version
crictl ps -a

### 9 - containerd config
echo "### 9 - CONFIGURE CONTAINERD ###"
sudo cat > /etc/containerd/config.toml <<EOF
disabled_plugins = []
imports = []
oom_score = 0
plugin_dir = ""
required_plugins = []
root = "/var/lib/containerd"
state = "/run/containerd"
version = 2

[plugins]

  [plugins."io.containerd.grpc.v1.cri".containerd.runtimes]
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
      base_runtime_spec = ""
      container_annotations = []
      pod_annotations = []
      privileged_without_host_devices = false
      runtime_engine = ""
      runtime_root = ""
      runtime_type = "io.containerd.runc.v2"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
        BinaryName = ""
        CriuImagePath = ""
        CriuPath = ""
        CriuWorkPath = ""
        IoGid = 0
        IoUid = 0
        NoNewKeyring = false
        NoPivotRoot = false
        Root = ""
        ShimCgroup = ""
        SystemdCgroup = true
EOF

### 10 : Setup WORKER
echo "### 10 - CONFIGURE WORKER ###"
sudo kubeadm join 172.31.13.96:6443 --token 0d47wr.hp1t7mupyqpympyo \
	--discovery-token-ca-cert-hash sha256:aeaf05ebb2012faee43bb54aa8df27710c1e2458dc0b747ec94620a8ea169f16
