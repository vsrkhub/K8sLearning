# 🌐 Phase 2: Advanced CNI Networking & Enterprise CSI Storage Handbook

This sub-page serves as the architectural engineering reference manual for cluster overlay data fabrics, zero-trust network firewalls, and persistent cloud/hardware data volume systems.

---

## 🗺️ 1. Container Network Interface (CNI) Decision Engine

Choosing the correct CNI dictates how pods acquire routing IPs, how network micro-segmentation firewalls are processed, and how much host packet encapsulation overhead is incurred.

### 1.1 Architectural Comparison Matrix

| Architectural Feature | Option A: Pure Flannel | Option B: Pure Calico | Option C: Canal Hybrid |
| :--- | :--- | :--- | :--- |
| **Primary Network Mode** | Overlay Tunnelling (VXLAN) | Native Layer 3 Routing (BGP) | Hybrid Overlay (VXLAN Data) |
| **Network Security Policies** | ❌ Completely Unsupported |  Fully Enforced Natively |  Fully Enforced Natively |
| **Packet Overhead** | Medium (Encapsulation Headers) | Lowest (Direct Host Routing) | Medium (Encapsulation Headers) |
| **Resource Footprint** | Extremely Minimal | Medium (BGP Daemon tracking) | High (Runs dual network daemons)|
| **Best Target Environment** | Local testing labs / Edge IoT | Security-hardened Production | Rapid multi-node cluster labs |

---

## 🛠️ 2. Dynamic Container Storage Interface (CSI) Platforms

Because local container runtime disk workspaces inside `containerd` are ephemeral, any container restart or node migration will instantly wipe application state. We deploy CSI plugins to dynamically provision persistent blocks.

### 2.1 Hyperscaler Option: Amazon EBS CSI Driver Integration
This platform maps dynamic block Solid State Disks directly out of the AWS virtual public cloud into cluster worker node attachment channels.

#### Step 1: Install Core Driver Infrastructure from Master Node
```bash
kubectl apply -k "://github.com"
```
*(Prerequisite Note: The physical EC2 worker nodes must have an IAM Instance Profile role mapping attached that permits `ec2:CreateVolume` and `ec2:AttachVolume` API calls).*

#### Step 2: Register the Dynamic StorageClass (`storage-class.yaml`)
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: enterprise-fast-gp3
provisioner: ://aws.com
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true
parameters:
  type: gp3
```
```bash
kubectl apply -f storage-class.yaml
```

#### Step 3: Claim storage resources (`pvc.yaml`)
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: database-storage-allocation
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: enterprise-fast-gp3
  resources:
    requests:
      storage: 15Gi
```
```bash
kubectl apply -f pvc.yaml
```

---

### 2.2 On-Premises Option: NetApp Trident CSI Integration
For dedicated hardware server rooms, **NetApp Trident** acts as the dynamic translator connecting `containerd` file requirements straight to physical hardware SAN/NAS storage appliances.

#### Step 1: Install the Storage Operator via Helm
```bash
# Register the official NetApp storage chart repo
helm repo add netapp-trident https://github.io

# Install the tracking supervisor framework
helm install trident netapp-trident/trident-operator --namespace trident --create-namespace
```

#### Step 2: Configure the Physical Storage Array Credentials (`backend.json`)
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

#### Step 3: Deploy the Hardware Storage Class Mapping (`netapp-sc.yaml`)
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

#### Step 4: Execute a High-Capacity Shared Volume Claim (`netapp-pvc.yaml`)
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
