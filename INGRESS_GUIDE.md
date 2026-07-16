# 🎛️ Advanced Routing: Deploying and Testing the NGINX Ingress Controller

This handbook provides an architectural breakdown, syntax anatomy, and practical terminal execution workflows for transitioning your cluster from restrictive `NodePort` mapping boundaries to an enterprise-grade Ingress architecture.

---

## 🗺️ 1. Ingress Architecture Layout

Instead of exposing every individual internal application service on a high-range random host port (30000-32767), an **Ingress Controller** acts as a unified reverse proxy and single entry point (`Layer 7`) for all inbound cluster HTTP/HTTPS traffic.

```text
 [ Inbound Client HTTP Request ] -> (Host Header: k8s-learning.local)
               │
               ▼
 ┌────────────────────────────────────────────────────────┐
 │ NGINX INGRESS CONTROLLER POD (ingress-nginx namespace)  │
 │  - Acts as a unified Layer 7 Reverse Proxy / Load Balancer│
 │  - Constantly monitors the API Server for routing updates│
 └───────────────────────────┬────────────────────────────┘
                             │
                             ▼ (Evaluates ingress-routing.yaml rules)
 ┌────────────────────────────────────────────────────────┐
 │ INTERNAL K8S SERVICE LAYER (web-ingress-svc)           │
 │  - Matches destination pods via selectors               │
 └───────────────────────────┬────────────────────────────┘
                             │
                             ▼ (Load-balances connection pools evenly)
 ┌────────────────────────────────────────────────────────┐
 │ CONTAINERS / POD WORKLOADS (Default Namespace)          │
 │  - pod/production-web-layer-1  (10.244.x.x)            │
 │  - pod/production-web-layer-2  (10.244.x.x)            │
 └────────────────────────────────────────────────────────┘
```

---

## 🛠️ 2. Dynamic Installation Pipeline

Execute these deployment steps from your **Master Control Plane instance terminal** to activate the core Ingress sub-systems.

### 2.1 Deploy the Ingress Core Manifest Infrastructure
Execute this official entry point schema mapping string to deploy the dedicated namespaces, configuration maps, cluster roles, and admission webhooks required to power the controller:

```bash
kubectl apply -f https://githubusercontent.com
```

### 2.2 Verify System Controller Health
Monitor the initialization loop to ensure that all core management controller pods successfully transition to a healthy `Running` state:

```bash
kubectl get pods -n ingress-nginx -w
```

---

## 📄 3. Declarative Ingress Routing Manifest

Create a file named **`ingress-routing.yaml`**. This manifest registers a routing blueprint instructing the NGINX controller to intercept incoming web requests carrying a specific domain name and route them down to your backend service layer.

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: core-frontend-ingress
  namespace: default
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: k8s-learning.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-ingress-svc
            port:
              number: 80
```

### 3.1 Apply the Routing Specification
```bash
# Register the ingress routing rules to the API server
kubectl apply -f ingress-routing.yaml

# Verify the ingress object has been successfully provisioned
kubectl get ingress
```

---

## 🔍 4. Verification & Diagnostic Traffic Probes

Because we are testing inside an internal AWS EC2 VPC environment without an external hardware cloud load balancer, we will route traffic locally via the controller's exposed NodePort.

### 4.1 Extract the Ingress Entrypoint NodePort
Run a service scan inside the `ingress-nginx` namespace to pinpoint the high-range port mapped to standard HTTP port 80:

```bash
kubectl get svc -n ingress-nginx
```

#### Understanding the Target Port Output Map:
Look at the line tracking `ingress-nginx-controller`. Under the `PORT(S)` column, you will see a layout template resembling this mapping sequence:
`80:31245/TCP,443:30985/TCP`

*   **`80`**: The internal proxy routing port inside the ingress container sandbox.
*   **`31245`**: The actual physical **NodePort** mapped out across your host instances. This is the port we will query to run our validation test.

### 4.2 Execute a Localized HTTP Header Injection Probe
We utilize a targeted `curl` command combined with a customized host header injection flag (`-H`). This mimics a real web browser requesting the domain name without needing to configure a real DNS server record:

```bash
# Replace '31245' with the exact NodePort extracted from your terminal output
curl -H "Host: k8s-learning.local" http://localhost:31245
```

#### Expected Successful Response Verification:
If your `containerd` node routing channels are healthy, the NGINX ingress controller will process your domain header, pass the request across your CNI virtual network interface, and output the raw HTML welcome script of your underlying backend workload:

```html
<!DOCTYPE html>
<html>
<head>
<title>Welcome to nginx!</title>
...
<p><em>Thank you for using nginx.</em></p>
</body>
</html>
```

---

## ❌ 5. Troubleshooting Common Ingress Failures

### 5.1 Request Returns `404 Not Found`
*   **Root Cause**: The Ingress Controller is alive, but it does not recognize the Host domain header or the URL path string you provided.
*   **Remediation**: Double-check that the `host:` line inside your `ingress-routing.yaml` matches your `curl` command header string exactly, and confirm that the target service name (`web-ingress-svc`) exists in the same namespace.

### 5.2 Request Returns `503 Service Temporarily Unavailable`
*   **Root Cause**: The Ingress Controller successfully intercepted your domain request, but it cannot locate any active backend pods to fulfill the connection pool.
*   **Remediation**: Execute `kubectl get endpoints web-ingress-svc`. If the endpoints list returns `<none>` or is completely empty, your backend app deployment is either missing or its pods have crashed inside the container runtime environment.
