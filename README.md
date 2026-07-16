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
### Part 3.5: Enterprise CNI Deep-Dive & Decision Engine

Choosing the correct CNI determines how pods communicate, how network security policies are enforced, and how much CPU overhead your system consumes.

#### 1. Flannel (Simplicity / Low Overhead)
*   **When to use:** Local development labs, test clusters, IoT edge nodes, or environments where advanced security filtering is unnecessary.
*   **How it works:** It uses standard Linux VXLAN encapsulation to build a simple Layer 3 overlay network. It distributes a flat IP pool (`10.244.0.0/16`) globally across nodes.
*   **Verdict:** Extremely fast to install and very lightweight, but it **completely lacks Network Policy support**. It cannot restrict pod-to-pod communication.

#### 2. Calico (Enterprise Performance & Zero-Trust)
*   **When to use:** Production deployments, multitenant setups, compliance-heavy infrastructures, and high-throughput environments.
*   **How it works:** By default, it operates without packet encapsulation by leveraging Border Gateway Protocol (BGP). This turns every Kubernetes node into an active router, avoiding encapsulation performance loss.
*   **Verdict:** Features a world-class, built-in **Network Policy engine** allowing you to create micro-segmented firewalls, but requires more advanced networking knowledge to troubleshoot.

#### 3. The Canal Hybrid (Flannel Speed + Calico Firewalls)
*   **When to use:** Teams that want Flannel's dead-simple, conflict-free VXLAN network pathways but still require Calico’s rigorous security policy enforcement engine.
*   **Verdict:** Best of both worlds, though it runs two discrete networking daemons per node, slightly increasing baseline memory footprint.

---

### Part 4.5: NetApp Trident CSI Integration

While the cloud-native AWS EBS CSI maps volumes to virtual public clouds, enterprise datacenters rely on **NetApp Trident** to map persistent storage folders directly from physical NetApp ONTAP SAN/NAS storage arrays into `containerd` container sandboxes.

#### Step 1: Install the Trident Orchestrator via Helm
Run this command from your master control plane to install the Trident controller onto your node nodes using the official repo:

```bash
# Add the NetApp Trident Helm repository
helm repo add netapp-trident https://github.io

# Install the storage orchestrator system
helm install trident netapp-trident/trident-operator --namespace trident --create-namespace
```

#### Step 2: Define the Physical Backend Storage Array (`backend.json`)
Trident requires a secure mapping specification telling it how to authenticate against your physical SAN/NAS environment. Create a file named `trident-backend.json`:

```json
{
    "version": 1,
    "storageDriverName": "ontap-nas",
    "managementLIF": "10.0.10.50",
    "dataLIF": "10.0.20.60",
    "svm": "k8s_storage_virtual_machine",
    "username": "trident_cluster_user",
    "password": "SecurePasswordSecure2026",
    "labels": {"performance": "gold", "cost": "enterprise"}
}
```
```bash
# Push the backend connection mapping configuration to the Trident orchestrator
tridentctl create backend -f trident-backend.json -n trident
```

#### Step 3: Register the NetApp StorageClass (`netapp-sc.yaml`)
Create your declarative storage tier layout mapped directly to the NetApp ONTAP backend:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: netapp-gold-nas
provisioner: csi.trident.netapp.io
parameters:
  backendType: "ontap-nas"
  media: "ssd"
  provisioningType: "thin"
```
```bash
kubectl apply -f netapp-sc.yaml
```

#### Step 4: Issue a PersistentVolumeClaim to the NetApp Array (`netapp-pvc.yaml`)
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: production-file-share
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: netapp-gold-nas
  resources:
    requests:
      storage: 100Gi
```
```bash
kubectl apply -f netapp-pvc.yaml
```

## 🚀 Part 4: Advanced Workload & Storage Deployments

This section details how to execute advanced workload strategies, configure cluster network firewalls, and provision dynamic cluster storage volumes within an immutable container runtime design.

---

### 1. Declarative Pod Application Setup
Deploying workloads natively requires a declarative approach. We establish a scalable backend architecture utilizing a multi-replica NGINX deployment.

#### Step 1.1: Create the Workload Manifest (`app-deployment.yaml`)
This deployment deploys two isolated pods across our worker nodes, managing lifecycle states via `containerd`.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: production-web-layer
  namespace: default
  labels:
    app.kubernetes.io/name: web-frontend
    tier: production
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
        resources:
          requests:
            memory: "64Mi"
            cpu: "100m"
          limits:
            memory: "128Mi"
            cpu: "200m"
```

#### Step 1.2: Apply and Expose the Workload via NodePort
```bash
# Deploy the manifest to your containerd nodes
kubectl apply -f app-deployment.yaml

# Create a permanent Layer 4 routing boundary across your physical node ports
kubectl expose deployment production-web-layer --type=NodePort --port=80 --target-port=80 --name=web-ingress-svc
```

---

### 2. Network Isolation Rule Enforcement (Calico / Canal Plugins Only)
By default, the Kubernetes network fabric is completely non-isolated—any pod can transmit packets to any other pod. If you implement **Calico** or the **Canal Hybrid**, you can apply standard zero-trust firewall configurations.

#### Scenario Example
We want to completely lock down our `production-web-layer` application. It must reject all inbound cluster traffic *unless* the requesting source explicitly contains the security badge validation label `access: verified`.

#### Step 2.1: Write the Isolation Manifest (`secure-policy.yaml`)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: zero-trust-frontend-ingress
  namespace: default
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
    ports:
    - protocol: TCP
      port: 80
```

#### Step 2.2: Enforce and Test the Firewall Policy
```bash
# Activate the zero-trust ingress firewall rule
kubectl apply -f secure-policy.yaml

# TEST A: Spin up an unapproved container (This request will hang and time out)
kubectl run standard-test-pod --image=alpine --rm -it -- restart=Never -- wget -qO- http://web-ingress-svc

# TEST B: Spin up a secure, authorized container (This request will succeed instantly)
kubectl run secure-test-pod --image=alpine --labels="access=verified" --rm -it -- restart=Never -- wget -qO- http://web-ingress-svc
```

---

### 3. Container Storage Interface (CSI) Integration
Because our local `containerd` file layers are ephemeral, any cluster restart or pod crash will instantly erase application data. To preserve state, we configure a cloud-native dynamic block storage tier utilizing the **Amazon EBS CSI Driver**.

#### Step 3.1: Initialize the AWS EBS CSI Core Infrastructure
Execute this command on your control plane master node to deploy the necessary storage controllers, daemonsets, and API schemas straight out of the Kubernetes SIG registry:

```bash
kubectl apply -k "://github.com"
```
*(Prerequisite Note: Ensure the underlying IAM Role attached to your EC2 worker nodes contains standard policy permissions allowing them to execute `ec2:CreateVolume`, `ec2:AttachVolume`, and `ec2:DeleteVolume` API calls).*

#### Step 3.2: Create a Dynamic StorageClass (`storage-class.yaml`)
This registers a template instructing the AWS CSI driver to automatically provision high-performance `gp3` Solid State Disks whenever a user creates a volume claim.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: enterprise-fast-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
```
```bash
# Register the storage template to the API server
kubectl apply -f storage-class.yaml
```

#### Step 3.3: Request a Persistent Volume Slice (`pvc.yaml`)
Instead of manually cutting AWS disk volumes, developers submit a PersistentVolumeClaim (PVC). The CSI driver intercepts this request and provisions a matching disk asset.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-storage-allocation
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: enterprise-fast-gp3
  resources:
    requests:
      storage: 15Gi
```
```bash
# Submit the storage allocation slice request
kubectl apply -f pvc.yaml
```

#### Step 3.4: Deploy a Stateful Workload Mounting the Cloud Disk
Create a manifest named `stateful-app.yaml`. This launches a stateful database layer that automatically mounts the requested 15Gi AWS SSD straight inside its `/var/lib/mysql` storage directory.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: database-core-layer
spec:
  replicas: 1
  selector:
    matchLabels:
      app: backend-database
  template:
    metadata:
      labels:
        app: backend-database
    spec:
      containers:
      - name: mysql-engine
        image: mysql:8.3.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          value: "ClusterEngineeringSecret2026"
        ports:
        - containerPort: 3306
        volumeMounts:
        - name: physical-aws-ebs-disk
          mountPath: /var/lib/mysql
      volumes:
      - name: physical-aws-ebs-disk
        persistentVolumeClaim:
          claimName: database-storage-allocation
```
```bash
# Finalize deployment by spinning up your stateful database layer
kubectl apply -f stateful-app.yaml
```

---

## 🔍 Part 5: Diagnostic Verification Runbook

Use this verification runbook to check your multi-node cluster topology, network allocations, and storage health.

### 1. Compute Node Fabric Assessment
Verify that every master and worker instance successfully communicates via the `containerd` runtime socket:

```bash
kubectl get nodes -o wide
```
#### Expected Healthy Output Template
```text
NAME               STATUS   ROLES           AGE   VERSION   INTERNAL-IP     OS-IMAGE                  KERNEL-VERSION                 CONTAINER-RUNTIME
ip-172-31-39-176   Ready    control-plane   2h    v1.30.0   172.31.39.176   Amazon Linux 2023.4.12    6.1.72-96.166.amzn2023.x86_64  containerd://1.6.2
ip-172-31-18-184   Ready    <none>          2h    v1.30.0   172.31.18-184   Amazon Linux 2023.4.12    6.1.72-96.166.amzn2023.x86_64  containerd://1.6.2
```
* **Troubleshooting Action:** If a node reports `NotReady`, execute `sudo systemctl status containerd` and `journalctl -u kubelet -n 100 --no-pager` directly on that specific node to locate failing cgroup initialization loops.

### 2. Network Interface Allocation Audit
Verify that your CoreDNS systems and CNI infrastructure pods have successfully acquired valid internal IP allocations from your configured subnet pool:

```bash
kubectl get pods -n kube-system -o wide
```
#### Expected Healthy Output Template
```text
NAME                                       READY   STATUS    RESTARTS   AGE    IP              NODE               NOMINATED NODE   READINESS GATES
coredns-7c65d6cfc9-abc12                   1/1     Running   0          115m   10.244.0.2      ip-172-31-39-176   <none>           <none>
kube-flannel-ds-lkn72                     1/1     Running   0          112m   172.31.18.184   ip-172-31-18-184   <none>           <none>
```
* **Troubleshooting Action:** If CoreDNS remains permanently `Pending`, your CNI network configuration failed. Execute `kubectl describe pod -n kube-system -l k8s-app=kube-dns` to check if a valid network overlay exists.

### 3. Dynamic Storage Lifecycle Validation
Verify that your AWS EBS CSI driver has dynamically provisioned your storage volume:

```bash
kubectl get pvc,pv -n default
```
#### Expected Healthy Output Template
```text
NAME                                                 STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS         AGE
pvc/database-storage-allocation                       Bound    pvc-78f9b1c2-3d4e-5f6a-7b8c-9d0e1f2a3b4c   15Gi       RWO            enterprise-fast-gp3  4m

NAME                                                 CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS   CLAIM                                  STORAGECLASS         REASON   AGE
pv/pvc-78f9b1c2-3d4e-5f6a-7b8c-9d0e1f2a3b4c          15Gi       RWO            Delete           Bound    default/database-storage-allocation    enterprise-fast-gp3           3m58s

* **Troubleshooting Action:** If your claim status remains stuck in a Pending state, your CSI driver cannot talk to the AWS infrastructure API. Run `kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner --tail=50` to inspect underlying permission errors or blocked cloud routing calls.


