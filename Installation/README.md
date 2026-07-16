# 🚀 Phase 1: Bare-Metal & OS Level Cluster Installation Guide

This handbook contains the exhaustive installation procedures, environment tuning primitives, and core engine configurations required to bootstrap your node topology from bare instances up to a responsive cluster state.

---

## 🏗️ 1. Infrastructure Baseline Validation Checklist

Before firing terminal commands, ensure your server instances satisfy these resource specifications:
*   **Control Plane Node**: Minimum 2 vCPUs, 2 GiB RAM, static internal IP networking.
*   **Worker Nodes**: Minimum 1 vCPU, 1.5 GiB RAM, distinct internal IP interfaces.
*   **Cluster Networking Firewalls**: Ensure your cloud provider network groups permit seamless host routing across these key ports:
    *   `6443` (Kubernetes API Server API Hub)
    *   `2379-2380` (etcd key-value distributed storage engine)
    *   `10250` (Kubelet connectivity loop daemon)
    *   `4789` (Flannel VXLAN overlay packet encapsulation tunnel)

---

## ⚙️ 2. Base Operating System Kernel Tuning

Run these commands as a root/sudo administrative user across **BOTH** your master node and all worker nodes to prepare the Linux environment for containerised traffic abstractions.

### 2.1 Load Kernel Module Pre-Requisites
```bash
# Register overlay and network bridge drivers to activate automatically on host boot
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Inject modules instantly into active system memory spaces
sudo modprobe overlay
sudo modprobe br_netfilter
```

### 2.2 Configure Sysctl Networking Layer
```bash
# Enable IPv4 packet forwarding and prevent iptables firewall bypass chains
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Refresh the active Linux kernel parameters parameter metrics
sudo sysctl --system
```

### 2.3 Clear Memory & Access Barriers
```bash
# Deactivate Swap space to preserve predictable scheduler memory profiles
sudo swapoff -a

# Put SELinux into permissive mode to unlock internal file tracking for the Kubelet
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing\$/SELINUX=permissive/' /etc/selinux/config
```

---

## 📦 3. Container Engine Core Compilation Pipeline

Run these actions across **ALL** nodes to establish the Container Runtime Interface (CRI) runtime foundations.

### 3.1 Extract containerd Workspace Files
```bash
# Unpack official CNCF containerd binaries straight into system binary execution spaces
sudo tar Cxzvf /usr/local containerd-1.6.2-linux-amd64.tar.gz
```

### 3.2 Secure Low-Level OCI execution Frameworks
```bash
# Compile runc engine execution files directly inside the host system sbin folder
sudo install -m 755 runc.amd64 /usr/local/sbin/runc
```

### 3.3 Configure the System Runtime Engine Driver
```bash
# Build system target configurations directory tracking nodes
sudo mkdir -p /etc/containerd

# Map out raw runtime layout values to the active config path
containerd config default | sudo tee /etc/containerd/config.toml

# Force containerd to delegate resource group boundaries to systemd
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Trigger system configuration reloads and execute the service
sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable containerd
```

### 3.4 Populate local CNI Workspace Layout Directories
```bash
# Build host execution pathways
sudo mkdir -p /opt/cni/bin

# Unpack baseline binary interface loop plugins
sudo tar -Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
```

---

## 🛠️ 4. Deploying Cluster Binaries

Run these package installation sequences across **ALL** nodes.

```bash
# Inject the official Kubernetes RHEL/CentOS system tracking repository
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://k8s.io
enabled=1
gpgcheck=1
gpgkey=https://k8s.iorepodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Install management packages simultaneously
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Lock down the Kubelet node agent background routine loop
sudo systemctl enable --now kubelet
```

---

## 🏁 5. Bootstrapping the Cluster Network Nodes

### 5.1 Initialize Control Plane Engine (Master Node ONLY)
Execute this setup string from the terminal of your Master engine server node instance:
```bash
sudo kubeadm init --cri-socket unix:///var/run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16
```

#### Map Non-Root Administrative Security Tokens
To access cluster operations natively via `kubectl` without requiring `sudo`, map the profile context variables:
```bash
mkdir -p \$HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
sudo chown \$(id -u):(id -g) HOME/.kube/config
```

### 5.2 Join Scaling Instances (Worker Nodes ONLY)
Take your uniquely printed token block string generated by the master node step output and apply it on your worker terminals to finish node synchronization:
```bash
sudo kubeadm join <master-internal-ip>:6443 --token <your-token-string> \
    --discovery-token-ca-cert-hash sha256:<your-sha-hash> \
    --cri-socket unix:///var/run/containerd/containerd.sock
```
