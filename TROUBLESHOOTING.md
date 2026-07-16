# 🔍 Phase 3: Diagnostic Verification & Production Troubleshooting Runbook

This engineering runbook contains the telemetry inspection commands, log parsing scripts, and system repair routines required to resolve cluster component failures across the compute, network, and storage planes.

---

## 🛑 1. Compute Plane Failure Modes & Host Remediation

### 1.1 Worker Node Trapped in `NotReady` Status
If a node drops communication or displays a `NotReady` execution flag when calling `kubectl get nodes -o wide`, the failure is typically caused by a crash-looping container runtime daemon or host resource starvation.

#### Step 1: Inspect the Local Runtime Process
Log straight into the affected worker node via SSH and run a system status scan:
```bash
sudo systemctl status containerd
```
* **Remediation**: If the process reports an inactive or failed state, force-restart the container runtime daemon instantly:
  ```bash
  sudo systemctl daemon-reload && sudo systemctl restart containerd
  ```

#### Step 2: Audit Host Cgroup Resource Mappings
If containerd runs fine but the node stays `NotReady`, the `kubelet` is likely failing to synchronize with system resources. Read the tail end of the system logs:
```bash
journalctl -u kubelet -n 100 --no-pager
```
* **Common Root Cause**: Look for lines stating `Failed to check bridging` or `cgroup driver mismatch`. Ensure your `/etc/containerd/config.toml` holds `SystemdCgroup = true` and that swap space is fully suppressed via `sudo swapoff -a`.

---

## 🌐 2. Network Plane & CNI Data Fabric Debugging

### 2.1 CoreDNS Pod Stuck in `Pending` or `ContainerCreating`
A freshly provisioned cluster will keep `coredns` pods trapped in a `Pending` initialization loop until a functional CNI overlay network interface is active.

#### Step 1: Trace the Pod Scheduling Blockage
```bash
kubectl describe pod -n kube-system -l k8s-app=kube-dns
```
* **Look For**: Under the `Events:` block at the bottom, find the failure reason. If it states `network plugin not initialized`, your CNI daemonset has failed to spin up.

#### Step 2: Validate CNI DaemonSet Executions
```bash
kubectl get pods -n kube-system -l app=flannel # For Flannel
# OR
kubectl get pods -n kube-system -l k8s-app=calico-node # For Calico
```
* **Remediation**: If overlay pods report `CrashLoopBackOff`, view their initialization container logs to find kernel packet dropping faults:
  ```bash
  kubectl logs -n kube-system -l app=flannel --tail=50
  ```
  Ensure your physical AWS Security Groups or local hardware network switches permit host traffic routing across UDP ports `4789` (VXLAN tunneling metrics) and TCP port `179` (Calico BGP routing tables).

---

## 💾 3. Dynamic Storage Plane & CSI Allocation Errors

### 3.1 PersistentVolumeClaim (PVC) Stuck in `Pending` State
When an application requests a disk but stays in a `Pending` layout state, the Container Storage Interface driver is failing to talk to the infrastructure API.

#### Step 1: Describe the Request Constraints
```bash
kubectl describe pvc <your-pvc-name>
```
* **Look For**: Look for warning tags at the bottom. If it states `waiting for first consumer to be created before binding`, this is **normal** behavior caused by your StorageClass setting `volumeBindingMode: WaitForFirstConsumer`. It will bind the moment you deploy a pod that references this specific claim name.

#### Step 2: Extract Controller Management Logs
If a pod *is* running but the storage fails to bind, the CSI provider controller is experiencing a permission rejection or API timeout. Parse the controller supervisor log block directly:

```bash
# For AWS EBS CSI Driver implementations:
kubectl logs -n kube-system -l app=ebs-csi-controller -c csi-provisioner --tail=50

# For NetApp Trident CSI implementations:
kubectl logs -n trident -l app=trident-csi --tail=50
```
* **Remediation Check**: 
  * For AWS setups, verify that your EC2 worker nodes hold the necessary AWS IAM permissions needed to dynamically spin up cloud disks (`ec2:CreateVolume`).
  * For NetApp setups, run `kubectl get tridentbackends -n trident` to confirm the cluster can communicate over management networks to your physical storage array LIF endpoints.
