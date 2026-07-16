# 🧑‍💻 The Complete Kubernetes & Containerd Engineering Handbook

## 🗺️ Part 1: Visual Architectures & Layouts

### 1. Cluster Node Topology (How Components Communicate)
This diagram illustrates the separation of control plane and worker node responsibilities. The API Server acts as the core hub for all cluster communication.

```text
                    ┌──────────────────────────────────────┐
                    │          DEVELOPER / ADMIN           │
                    └──────────────────┬───────────────────┘
                                       │ (kubectl commands)
                                       ▼
 ┌─────────────────────────────────────────────────────────────────────────────────────────┐
 │ CONTROL PLANE (MASTER NODE: ip-172-31-39-176)                                           │
 │                                                                                         │
 │   ┌───────────────┐     ┌──────────────────────┐     ┌───────────────┐     ┌────────┐   │
 │   │  kube-sch     │     │   kube-apiserver     │     │  kube-ctrl    │     │  etcd  │   │
 │   │  (Scheduler)  │◄───►│ (Core Communication) │◄───►│ (Controllers) │◄───►│ (Data) │   │
 │   └───────────────┘     └──────────┬───────────┘     └───────────────┘     └────────┘   │
 │                                    │                                                    │
 │   ┌────────────────────────────────▼────────────────────────────────────────────────┐   │
 │   │ containerd Runtime  <──[CRI Socket]──>  kubelet Agent                           │   │
 │   └─────────────────────────────────────────────────────────────────────────────────┘   │
 └────────────────────────────────────┬────────────────────────────────────────────────────┘
                                      │
                 ┌────────────────────┴────────────────────┐
                 │ (Internal Network Encapsulation / BGP)  │
                 ▼                                         ▼
 ┌───────────────────────────────────────┐ ┌───────────────────────────────────────┐
 │ WORKER NODE 1 (ip-172-31-18-184)      │ │ WORKER NODE 2 (ip-172-31-16-198)      │
 │                                       │ │                                       │
 │  ┌───────────────┐   ┌─────────────┐  │ │  ┌───────────────┐   ┌─────────────┐  │
 │  │ kubelet Agent │   │ kube-proxy  │  │ │  │ kubelet Agent │   │ kube-proxy  │  │
 │  └───────┬───────┘   └───────┬─────┘  │ │  └───────┬───────┘   └───────┬─────┘  │
 │          │                   │        │ │          │                   │        │
 │  ┌───────▼───────────────────▼─────┐  │ │  ┌───────▼───────────────────▼─────┐  │
 │  │     containerd Runtime          │  │ │  │     containerd Runtime          │  │
 │  │  ┌───────────┐   ┌───────────┐  │  │ │  │  ┌───────────┐   ┌───────────┐  │  │
 │  │  │ Pod Alpha │   │  Pod Beta │  │  │ │  │  │ Pod Gamma │   │ Pod Delta │  │  │
 │  │  └───────────┘   └───────────┘  │  │ │  │  └───────────┘   └───────────┘  │  │
 │  └─────────────────────────────────┘  │ │  └─────────────────────────────────┘  │
 └───────────────────────────────────────┘ └───────────────────────────────────────┘
```

### 2. Deep Dive inside the Container Runtime Engine
This layout shows how high-level container management hands operations down to the low-level OCI engine, using kernel primitives to establish security boundaries.

```text
 [ Kubernetes Control Plane (Kubelet Node Agent) ]
                      │
                      │ (Calls via UNIX Socket: /run/containerd/containerd.sock)
                      ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ HIGHER-LEVEL RUNTIME MANAGER (containerd daemon)                       │
 │  - Fetches and pulls remote OCI container images                       │
 │  - Allocates local network namespaces and configures root file paths   │
 │  - Manages snapshot layers (OverlayFS)                                 │
 └────────────────────┬───────────────────────────────────────────────────┘
                      │
                      │ (Spawns an independent tracking process per container)
                      ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ TRACKING LAYER (containerd-shim-runc-v2)                               │
 │  - Keeps stdout/stderr streams open                                    │
 │  - Keeps the container alive if containerd restarts or updates        │
 └────────────────────┬───────────────────────────────────────────────────┘
                      │
                      │ (Invokes the runtime executable with execution specs)
                      ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ LOW-LEVEL EXECUTION ENGINE (runc Engine)                              │
 │  - Executes specific system calls directly to the Linux Kernel         │
 └────────────────────┬───────────────────────────────────────────────────┘
                      │
                      ▼
 ┌────────────────────────────────────────────────────────────────────────┐
 │ LINUX HOST KERNEL (Isolation Layer)                                    │
 │                                                                        │
 │  ┌──────────────────────────────────────────────────────────────────┐  │
 │  │ NAMESPACES (Visibility Controls)                                 │  │
 │  │  - PID (Isolates PIDs so container sees itself as PID 1)         │  │
 │  │  - NET (Creates isolated interface networks for container IPs)   │  │
 │  │  - MNT (Mounts isolated root filesystems via pivot_root)        │  │
 │  │  - USER/UTS/IPC (Isolates system groups, names, and memory)      │  │
 │  └──────────────────────────────────────────────────────────────────┘  │
 │  ┌──────────────────────────────────────────────────────────────────┐  │
 │  │ CONTROL GROUPS - CGROUPS (Resource Throttling)                   │  │
 │  │  - Caps memory, limits CPU shares, and tracks device I/O        │  │
 │  └──────────────────────────────────────────────────────────────────┘  │
 └────────────────────────────────────────────────────────────────────────┘
```

---

## 🛠️ Part 2: Step-by-Step Installation Pipeline

### Phase 1: Base Operating System Tuning (Run on BOTH Master and All Worker Nodes)
Run these commands as a user with administrative access (`sudo`) across your instances.

#### Step 1.1: Enable Network Bridging and Kernel Packets
```bash
# Register kernel dependencies to verify they trigger on system boot
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

# Activate modules instantly into active system memory
sudo modprobe overlay
sudo modprobe br_netfilter

# Set runtime kernel network forwarding variables
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

# Load settings into the kernel without rebooting
sudo sysctl --system
```

#### Step 1.2: Disable Resource Management Blocks
```bash
# Shift SELinux to Permissive to allow the Kubelet write permissions
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Turn off Swap memory to prevent scheduling issues
sudo swapoff -a
```

---

### Phase 2: Compile & Configure Container Execution Engines (Run on BOTH Master and All Worker Nodes)

#### Step 2.1: Unpack containerd Binaries
```bash
# Extract the binary packages down into systemic executable spaces
sudo tar Cxzvf /usr/local containerd-1.6.2-linux-amd64.tar.gz
```

#### Step 2.2: Setup runc High-Performance Execution Engine
```bash
# Move runc into the system sbin and apply executable bits
sudo install -m 755 runc.amd64 /usr/local/sbin/runc
```

#### Step 2.3: Generate and Customize the Core `config.toml` File
```bash
# Generate the base target configuration folders
sudo mkdir -p /etc/containerd

# Generate default configuration layout values
containerd config default | sudo tee /etc/containerd/config.toml

# Update the SystemdCgroup value from false to true to use systemd resource tracking
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/g' /etc/containerd/config.toml

# Trigger systemd tracking registers, and start the daemon
sudo systemctl daemon-reload
sudo systemctl restart containerd
sudo systemctl enable containerd
```

#### Step 2.4: Install CNI Basic Plugins on Every System Node
Before running `kubeadm`, every system node needs the baseline CNI directory structure populated.
```bash
# Build the target standard destination path
sudo mkdir -p /opt/cni/bin

# Unpack the underlying official network plugins directly to the destination path
sudo tar -Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
```

---

### Phase 3: Install Kubernetes Package Repositories (Run on BOTH Master and All Worker Nodes)

```bash
# Write the official RedHat package deployment target repo file
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://k8s.io
enabled=1
gpgcheck=1
gpgkey=https://k8s.iorepodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

# Install the management software
sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

# Force the node-agent service loop to run at system startup
sudo systemctl enable --now kubelet
```

---

### Phase 4: Spin up the Cluster Head (Run on MASTER Node ONLY)

#### Step 4.1: Trigger Initialization
