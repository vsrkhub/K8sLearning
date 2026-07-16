#!/bin/bash
# ==============================================================================
# 🚀 AUTOMATED KUBERNETES MASTER INITIALIZATION SCRIPT
# ==============================================================================
set -e

echo "=== 1. Tuning Base Operating System Networks ==="
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system

echo "=== 2. Disabling Kernel Constraints ==="
sudo setenforce 0 || true
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
sudo swapoff -a

echo "=== 3. Pulling and Extracting Container Engines ==="
# Verify files exist in your working path before execution
if [ ! -f containerd-1.6.2-linux-amd64.tar.gz ] || [ ! -f runc.amd64 ]; then
    echo "❌ Error: Missing containerd tarball or runc binary in current folder!"
    exit 1
fi

sudo tar Cxzvf /usr/local containerd-1.6.2-linux-amd64.tar.gz
sudo install -m 755 runc.amd64 /usr/local/sbin/runc

echo "=== 4. Customizing config.toml ==="
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable containerd

echo "=== 5. Mounting Baseline CNI Layout Directories ==="
if [ -f cni-plugins-linux-amd64-v1.3.0.tgz ]; then
    sudo mkdir -p /opt/cni/bin
    sudo tar -Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
else
    echo "⚠️ Warning: cni-plugins archive not found. Creating empty path layout."
    sudo mkdir -p /opt/cni/bin
fi

echo "=== 6. Registering Kubernetes System Packages ==="
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://k8s.io
enabled=1
gpgcheck=1
gpgkey=https://k8s.iorepodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
sudo systemctl enable --now kubelet

echo "=== 7. Initializing Core Control Plane Infrastructure ==="
sudo kubeadm init --cri-socket unix:///var/run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16

echo "=== 8. Pipelining User Administrative Workspace Context ==="
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "=== 9. Deploying Network Overlay (Flannel) ==="
kubectl apply -f https://github.com

echo "=============================================================================="
echo "🎯 SUCCESS! Control Plane initialization complete."
echo "Copy the 'kubeadm join' token printed above and run it on your worker nodes!"
echo "=============================================================================="
