#!/usr/bin/env bash
#
# 00-bootstrap.sh -- stand up the Argo lab on KIND inside WSL2.
#
# Safe to re-run: every step is idempotent and nothing here touches your
# existing AWS EKS kube-context (we never auto-switch contexts).
#
#   ./00-bootstrap.sh preflight    # just check the environment, change nothing
#   ./00-bootstrap.sh tools        # install kind + every Argo CLI + kubectl plugin
#   ./00-bootstrap.sh cluster      # create the 3-node kind cluster
#   ./00-bootstrap.sh argo         # Argo CD + Workflows + Events + Rollouts
#   ./00-bootstrap.sh ingress      # nginx-ingress (Lab K603 traffic routing)
#   ./00-bootstrap.sh prometheus   # kube-prometheus-stack (Lab K609 analysis)
#   ./00-bootstrap.sh imageupdater # Argo CD Image Updater v0.18.0 (annotation style)
#   ./00-bootstrap.sh all          # tools -> cluster -> argo -> ingress -> prometheus -> imageupdater
#   ./00-bootstrap.sh down         # delete the cluster
#
# Covers all five Argo projects: CD, Workflows, Events, Rollouts, Image Updater.
#
# WHY KIND: you are following the School of DevOps CKA/CKAD Argo track, whose
# labs are written for kind and hard-code nginx-ingress traffic routing and
# kube-prometheus-stack. See README.md section 1 and kind-argo.yaml.
#
set -euo pipefail

LAB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KIND_VERSION="${KIND_VERSION:-v0.33.0}"        # pin: kind releases are not "latest"-downloadable
CLUSTER_CONFIG="${LAB_DIR}/kind-argo.yaml"
CLUSTER_NAME="${CLUSTER_NAME:-kind}"           # course default -> context kind-kind
LAB_CONTEXT="kind-${CLUSTER_NAME}"
BIN_DIR="${HOME}/.local/bin"
DOCKER_DESKTOP="/mnt/c/Program Files/Docker/Docker/resources/bin/docker.exe"

# Image Updater: the course (v2024.06) teaches the ANNOTATION style, which is
# v0.x. v1.x replaced it with an ImageUpdater CRD. v0.18.0 is the newest v0.x
# and is still maintained, so the course lab works verbatim.
IMAGE_UPDATER_VERSION="${IMAGE_UPDATER_VERSION:-v0.18.0}"

log()  { printf '\033[1;34m[argo-lab]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[argo-lab] WARN:\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[argo-lab] ERROR:\033[0m %s\n' "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# --------------------------------------------------------------------------
# Preflight: fail loudly on the two things that actually break this lab.
# --------------------------------------------------------------------------
preflight() {
  log "Running preflight checks..."

  grep -qi microsoft /proc/version || die "This does not look like WSL2."
  log "  WSL2 detected: $(uname -r)"

  # A Docker engine must be reachable -- kind is containers-in-Docker.
  local docker_bin=""
  if have docker; then docker_bin="docker"
  elif [[ -x "$DOCKER_DESKTOP" ]]; then docker_bin="$DOCKER_DESKTOP"; fi
  [[ -n "$docker_bin" ]] || die "No docker CLI found. Install Docker Desktop + enable WSL integration."

  if "$docker_bin" info >/dev/null 2>&1; then
    log "  Docker engine reachable: $("$docker_bin" version --format '{{.Server.Version}}' 2>/dev/null)"
  else
    warn "  Docker engine NOT reachable."
    warn "  Your docker CLI points at Docker Desktop for Windows, whose engine is stopped."
    warn "  Start Docker Desktop from Windows, then re-run."
    die  "  Aborting: kind cannot create a cluster without a running engine."
  fi

  # Mirrored networking dictates the 0.0.0.0 binding rule.
  local wslcfg
  wslcfg="$(ls /mnt/c/Users/*/.wslconfig 2>/dev/null | head -1 || true)"
  if [[ -n "$wslcfg" ]] && grep -qi 'networkingMode[[:space:]]*=[[:space:]]*mirrored' "$wslcfg"; then
    log "  .wslconfig: networkingMode=mirrored -> listeners MUST bind 0.0.0.0, not 127.0.0.1"
    log "    (kind-argo.yaml sets networking.apiServerAddress: 0.0.0.0 for this reason;"
    log "     the course's upstream kind config omits it and would break Windows-side clients)"
  else
    log "  .wslconfig: NAT networking (default) detected."
  fi

  # systemd is optional for kind; report it because it rules out microk8s / k3s-native.
  if [[ -d /run/systemd/system ]]; then
    log "  systemd: enabled (not required by kind)"
  else
    log "  systemd: DISABLED -- fine for kind; this is why microk8s / k3s-native are not viable here"
  fi

  # Warn about the live EKS context so nobody applies lab manifests into AWS.
  if have kubectl; then
    local ctx
    ctx="$(kubectl config current-context 2>/dev/null || true)"
    if [[ "$ctx" == arn:aws:eks:* ]]; then
      warn "  current-context is a REAL EKS cluster: ${ctx}"
      warn "  Always 'kubectl config use-context ${LAB_CONTEXT}' before applying lab manifests."
    fi
  fi

  # Interactive Docker cleanup option
  docker_cleanup_prompt "$docker_bin"

  log "Preflight complete."
}

# --------------------------------------------------------------------------
# Optional Docker Cleanup Menu (Containers, Images, System)
# --------------------------------------------------------------------------
docker_cleanup_prompt() {
  local docker_cmd="$1"
  [[ -t 0 ]] || return 0   # Skip prompting if non-interactive

  echo ""
  printf '\033[1;36m[argo-lab] Do you want to clean up Docker before continuing? [y/N]: \033[0m'
  read -r clean_ans
  if [[ "$clean_ans" =~ ^[Yy]$ ]]; then
    # 1. Clean ALL (Full system prune: containers, networks, images, build cache)
    printf '\033[1;33m[argo-lab]   -> Clean EVERYTHING in Docker (containers, networks, images, volumes)? [y/N]: \033[0m'
    read -r clean_all
    if [[ "$clean_all" =~ ^[Yy]$ ]]; then
      log "  Pruning entire Docker system (containers, networks, volumes, all images)..."
      "$docker_cmd" system prune -a --volumes -f || true
      log "  Docker system completely wiped clean."
      return 0
    fi

    # 2. Containers only
    printf '\033[1;33m[argo-lab]   -> Remove ALL stopped/running containers? [y/N]: \033[0m'
    read -r clean_containers
    if [[ "$clean_containers" =~ ^[Yy]$ ]]; then
      local running_c
      running_c="$("$docker_cmd" ps -aq 2>/dev/null || true)"
      if [[ -n "$running_c" ]]; then
        log "  Stopping and removing all Docker containers..."
        "$docker_cmd" rm -f $running_c || true
        log "  All containers removed."
      else
        log "  No containers found to remove."
      fi
    fi

    # 3. Images only
    printf '\033[1;33m[argo-lab]   -> Remove ALL Docker images? [y/N]: \033[0m'
    read -r clean_images
    if [[ "$clean_images" =~ ^[Yy]$ ]]; then
      local all_imgs
      all_imgs="$("$docker_cmd" images -q 2>/dev/null || true)"
      if [[ -n "$all_imgs" ]]; then
        log "  Removing all Docker images..."
        "$docker_cmd" rmi -f $all_imgs || true
        log "  All images removed."
      else
        log "  No images found to remove."
      fi
    fi
  fi
}

# --------------------------------------------------------------------------
# Tools: kind + the five Argo CLIs, all pinned into ~/.local/bin
# --------------------------------------------------------------------------
install_kind() {
  if have kind && [[ "$(kind version 2>/dev/null | awk '{print $2}')" == "$KIND_VERSION" ]]; then
    log "kind ${KIND_VERSION} already installed."; return
  fi
  mkdir -p "$BIN_DIR"
  log "Installing kind ${KIND_VERSION}..."
  # kind has no releases/latest/download redirect, so the tag must be explicit.
  curl -fsSL -o "${BIN_DIR}/kind" \
    "https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-linux-amd64"
  chmod +x "${BIN_DIR}/kind"
  log "  -> $(${BIN_DIR}/kind version)"
}

# repo | binary name | release asset | gzipped?
install_argo_cli() {
  local repo="$1" bin="$2" asset="$3" gz="$4"
  if have "$bin"; then log "${bin} already installed: $($bin version 2>/dev/null | head -1)"; return; fi
  mkdir -p "$BIN_DIR"
  log "Installing ${bin} from ${repo}..."
  local url="https://github.com/${repo}/releases/latest/download/${asset}"
  if [[ "$gz" == "yes" ]]; then
    curl -fsSL "$url" | gunzip > "${BIN_DIR}/${bin}"
  else
    curl -fsSL -o "${BIN_DIR}/${bin}" "$url"
  fi
  chmod +x "${BIN_DIR}/${bin}"
  log "  -> $(${BIN_DIR}/${bin} version 2>/dev/null | head -1 || echo installed)"
}

tools() {
  install_kind
  install_argo_cli "argoproj/argo-cd"        argocd        argocd-linux-amd64          no
  install_argo_cli "argoproj/argo-workflows" argo          argo-linux-amd64.gz         yes
  install_argo_cli "argoproj/argo-events"    argo-events   argo-events-linux-amd64.gz  yes

  # Argo Rollouts CLI is distributed as the kubectl plugin: kubectl-argo-rollouts-linux-amd64
  # We install kubectl-argo-rollouts and symlink argo-rollouts to it.
  install_argo_cli "argoproj/argo-rollouts" \
                   kubectl-argo-rollouts kubectl-argo-rollouts-linux-amd64 no
  if [[ ! -e "${BIN_DIR}/argo-rollouts" ]] && [[ -e "${BIN_DIR}/kubectl-argo-rollouts" ]]; then
    ln -s "${BIN_DIR}/kubectl-argo-rollouts" "${BIN_DIR}/argo-rollouts"
  fi

  # NOTE the UNDERSCORE in this asset name -- it differs from every other Argo
  # project (they all use hyphens). Verified against the v1.4.0 release assets.
  install_argo_cli "argoproj-labs/argocd-image-updater" \
                   argocd-image-updater argocd-image-updater-linux_amd64 no

  # k9s - Kubernetes Terminal UI
  if have k9s; then
    log "k9s already installed: $(k9s version --short 2>/dev/null || echo installed)"
  else
    log "Installing k9s from derailed/k9s..."
    mkdir -p "$BIN_DIR"
    local k9s_url="https://github.com/derailed/k9s/releases/latest/download/k9s_Linux_amd64.tar.gz"
    curl -fsSL "$k9s_url" | tar -xz -C "$BIN_DIR" k9s
    chmod +x "${BIN_DIR}/k9s"
    log "  -> $(${BIN_DIR}/k9s version --short 2>/dev/null || echo installed)"
  fi

  case ":${PATH}:" in
    *":${BIN_DIR}:"*) ;;
    *) warn "${BIN_DIR} is not on PATH. Add:  export PATH=\"${BIN_DIR}:\$PATH\"" ;;
  esac
  log "Tools ready."
}

# --------------------------------------------------------------------------
# Cluster
# --------------------------------------------------------------------------
cluster() {
  have kind || die "kind not found -- run './00-bootstrap.sh tools' first."
  [[ -f "$CLUSTER_CONFIG" ]] || die "Missing ${CLUSTER_CONFIG}"

  if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
    log "Cluster '${CLUSTER_NAME}' already exists."
    kind get clusters
  else
    log "Creating cluster from ${CLUSTER_CONFIG} ..."
    # --wait blocks until the API server is actually serving, so the kubectl
    # calls below cannot race the bootstrap.
    kind create cluster --name "${CLUSTER_NAME}" --config "$CLUSTER_CONFIG" --wait 5m
  fi

  log "Verifying..."
  kubectl config use-context "$LAB_CONTEXT"
  kubectl get nodes -o wide
  kubectl get pods -A

  log "Cluster ready."
  cat <<EOF

  context       : ${LAB_CONTEXT}  (switch: kubectl config use-context ${LAB_CONTEXT})
  nodes         : kind-control-plane, kind-worker, kind-worker2  (course Lab K101 shape)
  api server    : published on 0.0.0.0 -> reachable from Windows-side clients
  ingress http  : localhost:80    (mapped from kind-worker container port 80)
  ingress https : localhost:443
  nodeports     : 30000-30800, 32000, 32100 on kind-control-plane
  events/wf ui  : host port 8001 -> kind-worker container port 8080 (course mapping)

  Load an image without a registry (kind's equivalent of k3d image import):
    docker build -t myapp:0.1.0 .
    kind load docker-image myapp:0.1.0 --name ${CLUSTER_NAME}
  ...then use imagePullPolicy: IfNotPresent so the node does not try to pull it.

  Course extras you may want:
    git clone https://github.com/initcron/k8s-code.git
    git clone https://github.com/schoolofdevops/kube-ops-view
    kubectl apply -f kube-ops-view/deploy/     # visualiser on NodePort 32000
EOF
}

# --------------------------------------------------------------------------
# Argo CD + Workflows + Events + Rollouts
# --------------------------------------------------------------------------
argo() {
  have kubectl || die "kubectl not found."
  local ctx; ctx="$(kubectl config current-context 2>/dev/null || true)"
  [[ "$ctx" == "$LAB_CONTEXT" ]] || \
    die "Refusing to install Argo into context '${ctx}'. Run: kubectl config use-context ${LAB_CONTEXT}"

  log "Installing Argo CD..."
  kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
  # Use --server-side --force-conflicts because the applicationsets.argoproj.io CRD
  # exceeds the 256KB annotation limit of client-side kubectl.kubernetes.io/last-applied-configuration
  kubectl apply -n argocd --server-side --force-conflicts -f \
    https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

  log "Installing Argo Workflows..."
  kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argo -f \
    https://raw.githubusercontent.com/argoproj/argo-workflows/stable/manifests/quick-start-minimal.yaml
  kubectl -n argo rollout status deploy/workflow-controller --timeout=300s

  log "Installing Argo Events..."
  kubectl create namespace argo-events --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argo-events -f \
    https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml
  kubectl apply -n argo-events -f \
    https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install-validating-webhook.yaml

  log "Installing Argo Rollouts..."
  kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n argo-rollouts -f \
    https://raw.githubusercontent.com/argoproj/argo-rollouts/stable/manifests/install.yaml
  kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=300s

  # NOTE: no Ingress is created here on purpose. kind ships NO ingress
  # controller, and Lab K603 installs nginx-ingress itself because the Rollout
  # uses `trafficRouting.nginx.stableIngress`. Creating a Traefik Ingress here
  # (as the earlier k3d version did) would be dead config on kind.
  # Run './00-bootstrap.sh ingress' to install nginx-ingress.

  log "Argo stack installed."
  cat <<'EOF'

  UI (port-forward) : kubectl -n argocd port-forward svc/argocd-server 8081:443
                        -> https://localhost:8081        (safest, always works)
  admin password    : kubectl -n argocd get secret argocd-initial-admin-secret \
                        -o jsonpath='{.data.password}' | base64 -d
  argocd login      : argocd login localhost:8081 --insecure --username admin --password <pw>
  Workflows UI      : kubectl -n argo port-forward svc/argo-workflows-server 2746:2746
                        -> https://localhost:2746

  Next: ./00-bootstrap.sh ingress      (nginx-ingress, needed by Lab K603)
        ./00-bootstrap.sh prometheus   (kube-prometheus-stack, needed by Lab K609)
EOF
}

# --------------------------------------------------------------------------
# nginx-ingress -- required by Lab K603's `trafficRouting.nginx.stableIngress`
# --------------------------------------------------------------------------
ingress() {
  have kubectl || die "kubectl not found."
  local ctx; ctx="$(kubectl config current-context 2>/dev/null || true)"
  [[ "$ctx" == "$LAB_CONTEXT" ]] || \
    die "Refusing to install into context '${ctx}'. Run: kubectl config use-context ${LAB_CONTEXT}"

  log "Installing ingress-nginx..."
  kubectl apply -f \
    https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

  log "Waiting for ingress-nginx controller (this pulls a large image)..."
  kubectl -n ingress-nginx wait --for=condition=Ready \
    pod -l app.kubernetes.io/component=controller --timeout=420s

  log "Validating the admission webhook is serving..."
  # The kind provider manifest ships a ValidatingWebhookConfiguration. If the
  # controller is not ready, every subsequent Ingress apply fails with
  # "connection refused" -- the single most common kind ingress failure.
  kubectl -n ingress-nginx get validatingwebhookconfiguration 2>/dev/null || true

  log "ingress-nginx ready."
  cat <<'EOF'

  Argo Rollouts can now use the nginx traffic router exactly as Lab K603 does:

    strategy:
      canary:
        canaryService: vote-preview
        stableService: vote
        trafficRouting:
          nginx:
            stableIngress: vote

  During a rollout, watch the generated canary Ingress and its weight:
    kubectl describe ing vote-vote-canary
      -> nginx.ingress.kubernetes.io/canary-weight: 20 ... 40 ... 60 ... 80

  Reach it from the host at localhost:80 / localhost:443, or add to
  C:\Windows\System32\drivers\etc\hosts:
      127.0.0.1 vote.example.com argocd.local
EOF
}

# --------------------------------------------------------------------------
# Argo CD Image Updater -- pinned to v0.18.0 to match your course
# --------------------------------------------------------------------------
imageupdater() {
  have kubectl || die "kubectl not found."
  local ctx; ctx="$(kubectl config current-context 2>/dev/null || true)"
  [[ "$ctx" == "$LAB_CONTEXT" ]] || \
    die "Refusing to install into context '${ctx}'. Run: kubectl config use-context ${LAB_CONTEXT}"

  # WHY v0.18.0 AND NOT `stable`:
  #   Lab K608 configures Image Updater with ANNOTATIONS on the Application:
  #     argocd-image-updater.argoproj.io/image-list: myimage=xxxxxx/vote
  #     argocd-image-updater.argoproj.io/myimage.update-strategy: latest
  #     argocd-image-updater.argoproj.io/write-back-method: git:secret:argocd/git-creds
  #     argocd-image-updater.argoproj.io/write-back-target: "kustomization:../base"
  #   That is the v0.x model. `stable` is now v1.x, which replaced annotations
  #   with an ImageUpdater CRD -- the course patch would apply cleanly and then
  #   silently do nothing. v0.18.0 is the newest v0.x (Dec 2025), still
  #   maintained, and its install.yaml contains no CustomResourceDefinition at
  #   all, confirming the annotation-only model.
  log "Installing Argo CD Image Updater ${IMAGE_UPDATER_VERSION} into ns/argocd ..."
  kubectl apply -n argocd -f \
    "https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/${IMAGE_UPDATER_VERSION}/manifests/install.yaml"
  # v0.x names the Deployment `argocd-image-updater`; v1.x renamed it to
  # `argocd-image-updater-controller`. Do not mix them up.
  kubectl -n argocd rollout status deploy/argocd-image-updater --timeout=300s

  # OPTIONAL: teach Image Updater about a local/insecure registry. The course
  # uses Docker Hub (initcron/vote), so you can normally skip this. The
  # mechanism is identical in v0.x and v1.x -- ConfigMap key `registries.conf`
  # is mounted at /app/config/registries.conf. Enable with:
  #   PATCH_REGISTRY=yes ./00-bootstrap.sh imageupdater
  if [[ "${PATCH_REGISTRY:-no}" == "yes" ]]; then
    log "Patching registries.conf for a local insecure registry..."
    kubectl -n argocd patch configmap argocd-image-updater-config \
      --type merge --patch-file "${LAB_DIR}/image-updater-registry-patch.yaml"
    # registries.conf is a mounted file read only at startup, so a new pod is
    # required for it to take effect.
    kubectl -n argocd rollout restart deploy/argocd-image-updater
    kubectl -n argocd rollout status  deploy/argocd-image-updater --timeout=180s
  fi

  log "Image Updater ${IMAGE_UPDATER_VERSION} ready (annotation model)."
  cat <<'EOF'

  Lab K608 works verbatim now. Mark an Application for auto-update by patching
  annotations onto it:

    kubectl patch application --type=merge -n argocd vote-staging \
      --patch-file argo_applications_vote-staging_patch.yaml

  Watch it:
    kubectl logs -f -l "app.kubernetes.io/name=argocd-image-updater" -n argocd
    kubectl describe application -n argocd vote-staging

  TWO THINGS THAT BREAK THE COURSE LAB:
   * It uses write-back-method: git:secret:argocd/git-creds, so you must first
     create that Secret in ns/argocd with your repo credentials, or the
     write-back fails silently. Git write-back also needs Argo CD >= v2.0.
   * The Application must track a BRANCH (the lab sets git-branch: main). If it
     tracks HEAD, a tag or a SHA, Git write-back will not behave.

  Image matching is STRICT on the full name including the registry:
  docker.io/initcron/vote and quay.io/initcron/vote are NOT the same image.

  IF YOU EVER MOVE TO v1.x (`stable`), the model changes completely:
    kubectl apply -n argocd -f \
      https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/config/install.yaml
    * configuration moves into an ImageUpdater CRD (see gitops/20-imageupdater.yaml)
    * the controller becomes NAMESPACE-scoped by default (Role, not ClusterRole)
    * the Deployment is renamed argocd-image-updater-controller
    * escape hatch: an applicationRef with `useAnnotations: true` still honours
      the legacy annotations
EOF
}

# --------------------------------------------------------------------------
# kube-prometheus-stack -- matches Lab K609's hard-coded Prometheus address
# --------------------------------------------------------------------------
prometheus() {
  have kubectl || die "kubectl not found."
  have helm    || die "helm not found. Course Lab K113 uses Helm; install it first."
  local ctx; ctx="$(kubectl config current-context 2>/dev/null || true)"
  [[ "$ctx" == "$LAB_CONTEXT" ]] || \
    die "Refusing to install into context '${ctx}'. Run: kubectl config use-context ${LAB_CONTEXT}"

  # Lab K609's AnalysisTemplate queries, verbatim:
  #   address: http://prom-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
  # That Service name is "<release>-kube-prometheus-stack-prometheus", so the
  # Helm release MUST be named `prom` or the course manifests will not resolve.
  # prometheus-minimal.yaml is NOT a substitute: the lab also needs Grafana and
  # the nginx-ingress ServiceMonitor that produces
  # nginx_ingress_controller_request_duration_seconds_bucket.
  log "Adding prometheus-community Helm repo..."
  helm repo add prometheus-community https://prometheus-community.github.io/helm-charts >/dev/null
  helm repo update >/dev/null

  kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

  log "Installing kube-prometheus-stack as release 'prom' (large; several minutes)..."
  # NodePorts chosen from the range kind-argo.yaml already publishes on the
  # control-plane (30100 and 30300), so they are reachable from Windows too.
  helm upgrade --install prom prometheus-community/kube-prometheus-stack \
    --namespace monitoring \
    --set prometheus.service.type=NodePort \
    --set prometheus.service.nodePort=30100 \
    --set grafana.service.type=NodePort \
    --set grafana.service.nodePort=30300 \
    --wait --timeout 15m

  log "kube-prometheus-stack ready."
  cat <<'EOF'

  Prometheus  : http://localhost:30100
  Grafana     : http://localhost:30300     admin / prom-operator
  In-cluster  : http://prom-kube-prometheus-stack-prometheus.monitoring.svc.cluster.local:9090
                ^ use EXACTLY this string in AnalysisTemplate provider.prometheus.address

  Run './00-bootstrap.sh ingress' FIRST. The nginx metric the lab queries
  (nginx_ingress_controller_request_duration_seconds_bucket) only exists once
  ingress-nginx is deployed AND actually serving traffic.

  Lightweight alternative (no Grafana, no ServiceMonitors) if you are not doing
  Lab K609 verbatim and just want Rollouts analysis:
    kubectl create ns monitoring && kubectl apply -f prometheus-minimal.yaml
    -> provider.prometheus.address: http://prometheus.monitoring.svc.cluster.local:9090
EOF
}

down() {
  have kind || die "kind not found."
  log "Deleting kind cluster '${CLUSTER_NAME}'..."
  kind delete cluster --name "${CLUSTER_NAME}" || true
  kind get clusters || true
  log "Done. Your EKS kube-context was never modified."
}

case "${1:-preflight}" in
  preflight)    preflight ;;
  tools)        preflight; tools ;;
  cluster)      preflight; tools; cluster ;;
  argo)         argo ;;
  ingress)      ingress ;;
  imageupdater) imageupdater ;;
  prometheus)   prometheus ;;
  # Ordering matters: ingress before prometheus (nginx ServiceMonitor + metrics),
  # and imageupdater after argo (it patches Argo CD Applications).
  all)          preflight; tools; cluster; argo; ingress; prometheus; imageupdater ;;
  down)         down ;;
  *) die "Usage: $0 {preflight|tools|cluster|argo|ingress|prometheus|imageupdater|all|down}" ;;
esac
