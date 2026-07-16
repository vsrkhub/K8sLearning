# 🧑‍💻 The Complete Kubernetes & Containerd Engineering Handbook

A comprehensive, production-hardened engineering guide for provisioning a multi-node Kubernetes cluster utilizing **containerd**, **runc**, and **Flannel/Calico** overlays on Amazon Linux / RHEL instances.

---

## 🗺️ 1. Visual Architectures & Layouts

### 1.1 Cluster Node Topology (How Components Communicate)
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

### 1.2 Deep Dive Inside the Container Runtime Engine
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

## 🛠️ 2. Base Operating System Tuning (Run on BOTH Master & Workers)

### 2.1 Enable Network Bridging and Kernel Packets
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

### 2.2 Disable Resource Management Blocks
```bash
# Shift SELinux to Permissive to allow the Kubelet write permissions
sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

# Turn off Swap memory to prevent scheduling conflicts
sudo swapoff -a
```

---

## 📦 3. Container Runtime Installation (Run on BOTH Master & Workers)

### 3.1 Unpack containerd Binaries
```bash
# Extract the binary packages down into systemic executable spaces
sudo tar Cxzvf /usr/local containerd-1.6.2-linux-amd64.tar.gz
```

### 3.2 Setup runc High-Performance Execution Engine
```bash
# Move runc into the system sbin and apply executable bits
sudo install -m 755 runc.amd64 /usr/local/sbin/runc
```

### 3.3 Generate and Customize the Core `config.toml` File
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

### 3.4 Install CNI Basic Plugins on Every System Node
```bash
# Build the target standard destination path
sudo mkdir -p /opt/cni/bin

# Unpack the underlying official network plugins directly to the destination path
sudo tar -Cxzvf /opt/cni/bin cni-plugins-linux-amd64-v1.3.0.tgz
```

### 3.5 Install Kubernetes Package Repositories
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

## 🌐 4. Cluster Initialization & CNI Decision Engine

### 4.1 Spin up the Control Plane (Run on MASTER Node ONLY)
```bash
sudo kubeadm init --cri-socket unix:///var/run/containerd/containerd.sock --pod-network-cidr=10.244.0.0/16

# Extract Administrative Access Configuration for your standard session
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
### 4.2 Hook up Client Instances (Run on WORKER Nodes ONLY)
```bash
sudo kubeadm join 172.31.39.176:6443 --token [your-token] \
    --discovery-token-ca-cert-hash sha256:[your-hash] \
    --cri-socket unix:///var/run/containerd/containerd.sock
```

### 4.3 CNI Deep-Dive Matrix (Apply ONLY One Option from Master)

#### Option A: Pure Flannel (Simple Layer 3 Overlay)
* **Use Case:** Local labs, test setups, low overhead. Does not support network firewalls.
```bash
kubectl apply -f https://github.com
```

#### Option B: Pure Calico (Enterprise Performance & BGP Routing)
* **Use Case:** Multi-tenant isolation, strict network policies, raw performance.
```bash
kubectl create -f https://githubusercontent.com
curl -O https://githubusercontent.com
sed -i 's/192.168.0.0\/16/10.244.0.0\/16/g' custom-resources.yaml
kubectl create -f custom-resources.yaml
```

#### Option C: The Canal Hybrid (Flannel Routing + Calico Firewalls)
* **Use Case:** Simple VXLAN tunneling setup backed by rigorous micro-segmentation firewalls.
```bash
curl -O https://githubusercontent.com
sed -i 's/192.168.0.0\/16/10.244.0.0\/16/g' canal.yaml
kubectl apply -f canal.yaml
```

---

## 🚀 5. Advanced Workload & Storage Deployments

### 5.1 Declarative Application Setup (`app-deployment.yaml`)
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-web-layer
spec:
  replicas: 2
  selector:
    matchLabels:
      run: web-engine-core
  template:
    metadata:
      labels:
        run: web-engine-core
    spec:
      containers:
      - name: nginx-core
        image: nginx:1.25.4-alpine
        ports:
        - containerPort: 80
```
```bash
kubectl apply -f app-deployment.yaml
kubectl expose deployment production-web-layer --type=NodePort --port=80 --name=web-ingress-svc
```

### 5.2 Zero-Trust Ingress Firewall (`secure-policy.yaml`)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: zero-trust-frontend-ingress
spec:
  podSelector:
    matchLabels:
      run: web-engine-core
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          access: verified
```
```bash
kubectl apply -f secure-policy.yaml
```

### 5.3 Cloud Integration: AWS EBS CSI Driver
```bash
# 1. Install Base Infrastructure
kubectl apply -k "://github.com"
```

Create `storage-class.yaml`:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: enterprise-fast-gp3
provisioner: ://aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
```
```bash
kubectl apply -f storage-class.yaml
```

### 5.4 Data Center Integration: NetApp Trident CSI
```bash
# 1. Install Operator via Helm
helm repo add netapp-trident https://github.io
helm install trident netapp-trident/trident-operator --namespace trident --create-namespace
```

Create your physical array backend map configuration (`backend.json`):
```json
{
    "version": 1,
    "storageDriverName": "ontap-nas",
    "managementLIF": "10.0.10.50",
    "dataLIF": "10.0.20.60",
    "svm": "k8s_storage_virtual_machine",
    "username": "trident_cluster_user",
    "password": "SecurePassword2026"
}
```
```bash
tridentctl create backend -f backend.json -n trident
```

---

## 🔍 6. Diagnostic Verification Runbook

Execute these validation workflows on the master control plane node to maintain visibility:

### 6.1 Verify Compute Nodes Status
```bash
kubectl get nodes -o wide
```
* **Troubleshooting Action:** If a node reports `NotReady`, run `sudo systemctl status containerd` or inspect log patterns with `journalctl -u kubelet -n 100 --no-pager` directly on that specific host instance.

### 6.2 Check CNI IP Allocation Status
```bash
kubectl get pods -n kube-system -o wide
```
* **Troubleshooting Action:** If CoreDNS is stuck in `Pending`, verify that your overlay network pods are running and haven't crashed due to firewall blockages on ports `4789` (VXLAN) or `179` (BGP).

### 6.3 Track Dynamic Volume Claims Allocation
```bash
kubectl get pvc,pv
```

**Expected Successful State Output:**
```text
NAME                                STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS         AGE
pvc/database-storage-allocation     Bound    pvc-78f9b1c2-3d4e-5f6a-7b8c-9d0e1f2a3b4c   15Gi       RWO            enterprise-fast-gp3  4m
```
* **Troubleshooting Action:** If a claim stays `Pending`, run `kubectl describe pvc database-storage-allocation` or look for API blockages in controller containers with `kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner --tail=50`.
