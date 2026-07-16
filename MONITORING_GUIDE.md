# 📊 Advanced Observability: Cluster Metrics Tracking with Prometheus & Grafana

This handbook outlines the architectural blueprints, schema manifests, and engineering workflows required to deploy an enterprise-grade metrics collection and visualization data pipeline across your `containerd` nodes.

---

## 🗺️ 1. Cluster Monitoring Architecture Layout

Observability relies on a pull-based scraping architecture. **Prometheus** periodically queries underlying node metrics endpoints, parses the telemetry, and stores it in a high-performance Time Series Database (TSDB). **Grafana** then acts as the presentation layer, pulling from Prometheus to render real-time infrastructure dashboards.

```text
 ┌──────────────────────┐      ┌──────────────────────┐
 │   Worker Node 1      │      │   Worker Node 2      │
 │ [ kubelet / cAdvisor]│      │ [ kubelet / cAdvisor]│
 └──────────┬───────────┘      └──────────┬───────────┘
            │ /metrics                    │ /metrics
            ▼                             ▼
 ┌────────────────────────────────────────────────────────┐
 │ PROMETHEUS SERVER POD (monitoring namespace)           │
 │  - Scrapes metrics endpoints via periodic scrape loops  │
 │  - Evaluates operational data inside its internal TSDB │
 └───────────────────────────┬────────────────────────────┘
                             │
                             ▼ (Pulls metrics via PromQL queries)
 ┌────────────────────────────────────────────────────────┐
 │ GRAFANA VISUALIZATION ENGINE (monitoring namespace)     │
 │  - Connects to Prometheus as an active Data Source     │
 │  - Renders real-time cluster health & resource charts  │
 └────────────────────────────────────────────────────────┘
```

---

## 🛠️ 2. Automated Stack Deployment via Helm

The industry standard for installing Prometheus and Grafana simultaneously is the **kube-prometheus-stack**, a curated community project that configures all necessary cluster roles, scrape targets, and alert managers out of the box.

Execute these commands from your **Master Control Plane instance terminal**:

### 2.1 Register the Prometheus Community Chart Repo
```bash
# Add the official prometheus-community chart marketplace
helm repo add prometheus-community https://github.io

# Sync repository indices to fetch the latest builds
helm repo update
```

### 2.2 Install the Complete Observability Stack
```bash
# Provision a dedicated monitoring namespace and inject the entire infrastructure stack
helm install prometheus-stack prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --create-namespace \
    --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
```

### 2.3 Verify System Telemetry Pod Health
Ensure all metrics scraping daemons, dashboard engines, and cluster-role-binding managers successfully scale to a running state:

```bash
kubectl get pods -n monitoring -w
```

---

## 📄 3. Exposing and Accessing Dashboard Portals

By default, Prometheus and Grafana are securely isolated as internal `ClusterIP` services inside the `monitoring` namespace. To access their graphic user interfaces from outside your EC2 VPC, we expose them via `NodePort` or `Ingress` boundaries.

### 3.1 Expose the Grafana Dashboard View
```bash
# Convert Grafana from an internal ClusterIP to a high-range NodePort routing interface
kubectl patch svc prometheus-stack-grafana -n monitoring -p '{"spec": {"type": "NodePort"}}'

# Extract the high-range port mapped out across your host network interfaces
kubectl get svc prometheus-stack-grafana -n monitoring
```
Look under the `PORT(S)` column for the target mapping string (e.g., `80:31999/TCP`). You can now visit your server's public IP address in your web browser at port `31999` to open the Grafana portal.

#### Fetching Your Grafana Administrator Login Credentials:
The stack automatically generates a secure administrative password. Extract it directly using this base64 decoding text command:
```bash
kubectl get secret prometheus-stack-grafana -n monitoring -o jsonpath="{.data.admin-password}" | base64 --decode; echo
```
*Username default:* `admin`

---

## 📈 4. Writing Core PromQL Metrics Queries

Once logged into Grafana, navigate to **Explore** or create a new **Dashboard Panel**. Ensure your Data Source is set to Prometheus, and utilize these high-utility **PromQL (Prometheus Query Language)** syntax snippets to audit cluster limits:

### 4.1 Track Live Memory Consumption per Container
Calculates exactly how much physical RAM (in bytes) your `containerd` container runtimes are actively drawing from host worker pools:
```promql
sum(container_memory_working_set_bytes{container!=""}) by (pod)
```

### 4.2 Track CPU Core Millisecond Saturation Loops
Measures active processing unit thread draw changes over a rolling 5-minute window, broken down by individual application namespaces:
```promql
sum(rate(container_cpu_usage_seconds_total{container!=""}[5m])) by (namespace)
```

### 4.3 Audit Pod Restart Spike Thresholds
Quickly flags unstable containers trapped in severe crash loop cycles across the entire infrastructure topology:
```promql
sum(changes(kube_pod_container_status_restarts_total[1h])) by (pod)
```

---

## ❌ 5. Troubleshooting Observability Blindspots

### 5.1 Prometheus Shows `0/0 Nodes Up` or Node Metrics are Blank
*   **Root Cause**: The underlying scraper loops cannot reach the host worker node Kubelet tracking sockets due to structural security framework blocks.
*   **Remediation**: Check that your physical AWS Security Group parameters explicitly permit inbound communication across port `10250` (the Kubelet diagnostic channel). This allows the Prometheus collector pods to safely pull raw node resource arrays.

### 5.2 Dashboards Display a `Data Source Connection Error`
*   **Root Cause**: Grafana is attempting to point to an outdated server URL path or a disconnected API registration endpoint.
*   **Remediation**: Inside your Grafana web panel, navigate to **Connections** -> **Data Sources** -> **Prometheus**. Ensure the core HTTP URL endpoint matches the internal cluster DNS name string exactly:  
    `http://cluster.local`
