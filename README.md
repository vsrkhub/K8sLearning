# 🧑‍💻 The Complete Kubernetes & Containerd Engineering Handbook

A comprehensive learning repository and production-hardened guide for provisioning a multi-node Kubernetes cluster.

## 📖 Project Documentation Index
* 🚀 Read the [Complete Installation Guide](Installation/README.md)
* 🌐 Review [Advanced CNI & CSI Storage Architecture](storage-networking/README.md)
* ⚙️ Review [Systemd Services & YAML Schema Architectures](CONFIG_STRUCTURE.md)
* 🔍 Open the [Diagnostic Verification Runbook](TROUBLESHOOTING.md)

## 🗺️ 1. Project Overview & Topology & Visual Architectures & Layouts

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
