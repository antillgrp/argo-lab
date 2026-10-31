# Ultimate Argo Bootcamp — Student Lab & Training Guide

A complete, beginner-friendly lab companion for the **[Ultimate Argo Bootcamp by School of DevOps®](https://www.udemy.com/course/ultimate-argo-bootcamp-by-school-of-devops/learn/)**.

This repository gives you a pre-configured local Kubernetes environment running on **WSL2 (Ubuntu)** with **kind (Kubernetes in Docker)**, plus all required manifests for GitOps, Progressive Delivery, and CI/CD automation.

---

## 🎯 Quick Start (Get Up and Running in 4 Steps)

### Step 1: Start Docker Desktop
Ensure Docker Desktop is running on Windows (the whale icon in your taskbar should be steady).

### Step 2: Configure WSL2 Hardware Resources (Half RAM & Half CPU Cores)
Before creating the multi-node KIND cluster, make sure WSL2 has enough CPU and RAM allocated.

A helper launcher [`set-wsl-resources.bat`](./_scripts/set-wsl-resources.bat) and PowerShell script [`set-wsl-resources.ps1`](./_scripts/set-wsl-resources.ps1) are included under `_scripts/`.

Run the `.bat` wrapper from Windows (it automatically bypasses PowerShell execution restrictions and unblocks UNC paths):

```cmd
# Option A: From Windows Command Prompt (CMD) or PowerShell:
.\_scripts\set-wsl-resources.bat

# Option B: Directly from PowerShell:
powershell.exe -ExecutionPolicy Bypass -File .\_scripts\set-wsl-resources.ps1
```

> **What it does:** Queries Windows host hardware specs, calculates 50% RAM and 50% logical cores, updates `C:\Users\<YourUser>\.wslconfig`, and prompts to run `wsl --shutdown` so the new resource limits take effect upon your next terminal launch.

### Step 3: Run Preflight Check
Open your terminal in this repository and verify your environment:
```bash
cd /home/toor/DEVOPS_DEV/_Ultimate_Argo_Bootcamp
./00-bootstrap.sh preflight
```
> **What it does:** Performs a safe, read-only audit. Verifies Docker engine reachability, confirms WSL2 environment, inspects `.wslconfig` networking mode, and warns if your active Kubernetes context is set to a real AWS EKS cloud cluster.
> 
> **Interactive Cleanup:** Preflight will also ask if you wish to clean up Docker:
> - Clean **all** (full system prune: containers, networks, volumes, build cache) `[y/N]`
> - Clean **containers** only (stops & removes all containers) `[y/N]`
> - Clean **images** only (removes all images) `[y/N]`

### Step 4: Launch Cluster & Tooling
Run the automated installer to stand up the 3-node cluster and install all course components in one shot:
```bash
./00-bootstrap.sh all
```
> **What it does:** Runs the complete end-to-end setup in ~5–7 minutes:
> 1. **`tools`**: Downloads `kind`, `argocd`, `argo`, `argo-events`, and `kubectl-argo-rollouts` plugin to `~/.local/bin/`.
> 2. **`cluster`**: Provisions 3-node KIND cluster (`kind-control-plane`, `kind-worker`, `kind-worker2`) with ports mapped to host.
> 3. **`argo`**: Deploys Argo CD, Argo Rollouts, Argo Workflows, and Argo Events controllers.
> 4. **`ingress`**: Deploys NGINX Ingress Controller configured for KIND canary traffic routing.
> 5. **`prometheus`**: Deploys `kube-prometheus-stack` (Prometheus on port `30100`, Grafana on `30300`).
> 6. **`imageupdater`**: Deploys Argo Image Updater pinned to `v0.18.0` (annotation-driven).

---

## 🗺️ Course Roadmap & Hands-on Lab Walkthrough

Follow the course modules in order. Each lab corresponds to downloaded videos in [`RESOURCES/_VIDEOS/`](./RESOURCES/_VIDEOS/) and reference PDF guides in [`RESOURCES/`](./RESOURCES/):

| Lab / Project | Topic | Videos | Guide / Manifests | What You Do & Learn |
| :--- | :--- | :---: | :--- | :--- |
| **Module 01 & 02** | **Introduction to Argo Ecosystem** | `01` – `10` | [`ArgoWorkshop.pdf`](./RESOURCES/ArgoWorkshop-2705202401.pdf) | Understand GitOps principles, CRD architecture, and how Argo CD, Rollouts, Workflows, and Events connect. |
| **Lab K101** | **Multi-Node Cluster Setup** | `04` – `10` | [`Lab 1 KIND Cluster.pdf`](./RESOURCES/Lab+1+-+Create+Kubernetes+Cluster+with+KIND.pdf)<br>[`kind-argo.yaml`](./kind-argo.yaml) | Provision 1 control-plane and 2 worker nodes using `kind` with ports mapped for local browser access. |
| **Lab K602** | **Blue/Green Releases with Rollouts** | `11` – `18` | [`Lab 2 Blue Green.pdf`](./RESOURCES/Lab+2+-++Blue+Green+Releases+with+Argo+Rollouts.pdf)<br>[`demo-app/10-app.yaml`](./demo-app/10-app.yaml) | Replace standard Kubernetes Deployments with Argo Rollouts. Use active & preview services for zero-downtime cutovers. |
| **Lab K603** | **Canary Progressive Delivery** | `19` – `28` | [`Lab 3 Canary Release.pdf`](./RESOURCES/Lab+3+-++Implementing+Canary+Release+for+Prod.pdf)<br>[`ingress`](./00-bootstrap.sh) | Route production traffic dynamically (20% → 40% → 60% → 80% → 100%) using Nginx Ingress annotations. |
| **Lab K604** | **GitOps Deployments with Argo CD** | `29` – `41` | [`Lab 4 ArgoCD.pdf`](./RESOURCES/Lab+4+-++Setting+up+Automated+Deployments+with+ArgoCD.pdf)<br>[`gitops/10-application.yaml`](./gitops/10-application.yaml) | Connect Git repositories to Kubernetes. Configure auto-sync, automated self-healing, and multi-environment apps. |
| **Lab K606** | **CI Pipelines with Argo Workflows** | `42` – `51` | [`Lab 5 Workflows.pdf`](./RESOURCES/Lab+5+-+CI+Pipeline+with+Argo+Workflows.pdf) | Build native containerized CI pipelines with parallel Directed Acyclic Graph (DAG) task execution. |
| **Lab K607** | **Event-Driven Automation (Events)** | `52` – `58` | [`Lab 6 Argo Events.pdf`](./RESOURCES/Lab+6+-+Event+Based+Automation+with++Argo+Events.pdf) | Configure EventSources and Webhook Sensors to automatically trigger CI workflows on Git/registry events. |
| **Lab K608** | **Argo Image Updater** | `59` – `62` | [`Lab 7 Image Updater.pdf`](./RESOURCES/Lab+7+-+Argo+Image+Updater.pdf)<br>[`gitops/20-annotations.yaml`](./gitops/20-imageupdater-annotations.yaml) | Automate container image updates back into Git using v0.18.0 annotations. |
| **Lab K609** | **Automated Analysis & Rollbacks** | `63` – `69` | [`Lab 8 Prometheus.pdf`](./RESOURCES/Lab+8+-+Automated+Analysis+and+Experiments+with+Prometheus+and+Grafana.pdf)<br>[`demo-app/40-analysis.yaml`](./demo-app/40-analysis.yaml) | Query Prometheus metrics in real-time during rollouts. Automatically promote or abort based on latency and error rate. |

> Detailed video audit and duration index: [`RESOURCES/_VIDEOS/VIDEO_INDEX.md`](./RESOURCES/_VIDEOS/VIDEO_INDEX.md)

---

## 🖥️ Accessing Web Dashboards from Your Browser

All ports are mapped to `0.0.0.0`, allowing you to open them directly in your Windows browser:

### 1. Argo CD Web UI
* **URL:** [https://localhost:8081](https://localhost:8081)
* **Start Port-Forward:**
  ```bash
  kubectl -n argocd port-forward svc/argocd-server 8081:443 --address 0.0.0.0
  ```
* **Login Username:** `admin`
* **Get Password:**
  ```bash
  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d && echo
  ```

### 2. Argo Workflows UI
* **URL:** [http://localhost:8001](http://localhost:8001) (mapped automatically via worker container port 8080)
* Or forward manually:
  ```bash
  kubectl -n argo port-forward svc/argo-server 2746:2746 --address 0.0.0.0
  # Open http://localhost:2746
  ```

### 3. Demo Application & Canary Ingress
* **Stable App:** [http://localhost](http://localhost) (Host header: `podinfo.example.com`)
* **Simulate Canary Traffic:**
  ```bash
  while true; do
    curl -s -o /dev/null -w "%{http_code}\n" -H "Host: podinfo.example.com" http://localhost/version
    sleep 0.3
  done
  ```

---

## 🛠️ Step-by-Step Bootstrap Commands
If you prefer to run each step individually as you progress through course chapters rather than running `./00-bootstrap.sh all`:

### 1. Install CLI Tools
```bash
./00-bootstrap.sh tools
```
* **When to run:** Before starting Section 3.
* **What it does:** Downloads and installs official binaries for `kind`, `argocd`, `argo`, `argo-events`, `argo-rollouts`, the `kubectl-argo-rollouts` plugin, and **`k9s`** (Kubernetes terminal UI) into `~/.local/bin/`.

### 2. Provision 3-Node KIND Cluster
```bash
./00-bootstrap.sh cluster
```
* **When to run:** Section 3 (Environment Setup, Lab K101).
* **What it does:** Uses `kind-argo.yaml` to spin up 3 containerized nodes (`kind-control-plane`, `kind-worker`, `kind-worker2`), sets up host port mappings (`80`, `443`, NodePorts `30000–30800`, `32000`), binds API server to `0.0.0.0`, and points `kubectl` to `kind-kind`.

### 3. Install Core Argo Stack
```bash
./00-bootstrap.sh argo
```
* **When to run:** Before Section 4 (Rollouts) or Section 6 (Argo CD).
* **What it does:** Deploys CRDs and controller pods for Argo CD (`ns/argocd`), Argo Rollouts (`ns/argo-rollouts`), Argo Workflows (`ns/argo`), and Argo Events (`ns/argo-events`).

### 4. Install NGINX Ingress Controller
```bash
./00-bootstrap.sh ingress
```
* **When to run:** Before Section 5 (Canary Releases, Lab K603).
* **What it does:** Installs `ingress-nginx` preconfigured for KIND and admission webhooks, enabling weighted traffic shifting (`canary-weight: 20` ... `80`).

### 5. Install Prometheus & Grafana Monitoring
```bash
./00-bootstrap.sh prometheus
```
* **When to run:** Before Section 9 (Automated Analysis & Experiments, Lab K609).
* **What it does:** Deploys `kube-prometheus-stack` via Helm under release name `prom`. Exposes Prometheus on port `30100` (`http://localhost:30100`), Grafana on port `30300` (`http://localhost:30300`), and configures internal DNS `http://prom-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090` required by the course `AnalysisTemplate`.

### 6. Install Argo Image Updater
```bash
./00-bootstrap.sh imageupdater
```
* **When to run:** Before Section 8 (Mission #5 & Lab K608).
* **What it does:** Deploys Argo Image Updater pinned to **`v0.18.0`** into `ns/argocd` so the course's annotation-driven auto-update manifests (`argocd-image-updater.argoproj.io/*`) work verbatim.

### 7. Clean Up / Tear Down Cluster
```bash
./00-bootstrap.sh down
```
* **When to run:** When you finish studying or want to wipe the cluster clean.
* **What it does:** Deletes the 3-node KIND cluster and frees memory/disk. Leaves your downloaded tools, video files, and AWS cloud configurations completely untouched.

---

## ⚠️ 3 Golden Rules (Gotchas to Avoid)

### 1. Always Check Your Kubernetes Context
If you have work EKS or cloud clusters in your kubeconfig, ensure your active context is the local lab:
```bash
kubectl config current-context          # Should output: kind-kind
kubectl config use-context kind-kind    # Switch if needed
```

### 2. WSL2 Mirrored Networking Rule
Your WSL2 environment uses `networkingMode=mirrored`.
* Always bind services to `0.0.0.0` (not `127.0.0.1`), e.g. `kubectl port-forward ... --address 0.0.0.0`.
* Never rewrite `kind-argo.yaml`'s API server IP to `127.0.0.1`, or Windows clients and browsers cannot connect.

### 3. Argo Image Updater: Annotations vs CRD
* Course **Lab K608** teaches configuring Image Updater with **annotations** on the Application.
* Modern Image Updater `v1.x` removed annotation support and replaced it with an `ImageUpdater` CRD (annotations are silently ignored).
* This environment installs **`v0.18.0`** so course manifests work verbatim out-of-the-box.

---

## 📁 Repository Directory Structure

```text
├── 00-bootstrap.sh                   # Main idempotent lab installer script
├── _scripts/                         # Utility scripts for Windows & WSL host setup
│   ├── set-wsl-resources.bat         # Batch launcher (bypasses execution policy & unblocks file)
│   └── set-wsl-resources.ps1         # PowerShell host hardware allocation script
├── kind-argo.yaml                    # 3-node kind cluster configuration (mirrored mode compatible)
├── README.md                         # This training handbook
├── demo-app/                         # Sample progressive delivery microservice
│   ├── 10-app.yaml                   # Rollout spec, stable & preview services, ingress
│   ├── 40-analysis.yaml              # Prometheus metric queries for automated rollback
│   └── kustomization.yaml            # Kustomize manifest for GitOps tracking
├── gitops/                           # Argo CD declarative applications
│   ├── 10-application.yaml           # Root Argo CD Application
│   ├── 20-imageupdater-annotations.yaml # Lab K608 annotation patch
│   └── ALT-imageupdater-v1-crd.yaml  # Reference v1.x CRD syntax
└── RESOURCES/                        # Official course lab assets
    ├── *.pdf                         # Step-by-step PDF lab instructions (Lab 1 through 8)
    ├── *.url                         # Direct browser shortcuts to School of DevOps tutorials
    ├── LECTURE_NOTES/                # Saved markdown notes from text-only course lectures
    └── _VIDEOS/                      # Downloaded video lectures (sorted and numbered 01-69)
        └── VIDEO_INDEX.md            # Detailed chronological video mapping table
```
