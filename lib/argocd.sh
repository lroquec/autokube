#!/usr/bin/env bash
# argocd.sh - Bootstrap ArgoCD + gestión de Applications

readonly ARGOCD_NAMESPACE="argocd"
readonly ARGOCD_CHART_VERSION="9.4.1"

install_argocd() {
    log_header "ArgoCD"

    helm_repo_add argo https://argoproj.github.io/argo-helm
    helm_repo_update

    helm_install argo-cd argo/argo-cd "$ARGOCD_NAMESPACE" \
        --values "${AUTOKUBE_ROOT}/manifests/argocd/values.yaml" \
        --version "$ARGOCD_CHART_VERSION"

    # Esperar a que el server esté ready
    wait_for_deployment "argo-cd-argocd-server" "$ARGOCD_NAMESPACE" 180

    log_success "ArgoCD instalado"
}

# Crear una Application de ArgoCD apuntando a un Helm chart
# Uso: create_argocd_app <name> <chart> <repo_url> <version> <namespace> <values_file> [sync_wave]
create_argocd_app() {
    local name=$1
    local chart=$2
    local repo_url=$3
    local chart_version=$4
    local namespace=$5
    local values_file=$6
    local sync_wave=${7:-0}

    local values_content=""
    if [ -f "$values_file" ]; then
        values_content=$(cat "$values_file")
    fi

    # Generar el YAML con values inline
    local app_yaml="${CFG_DATA_DIR}/argocd-app-${name}.yaml"
    cat > "$app_yaml" <<APPEOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${name}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "${sync_wave}"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    chart: ${chart}
    repoURL: ${repo_url}
    targetRevision: "${chart_version}"
    helm:
      values: |
$(echo "$values_content" | sed 's/^/        /')
  destination:
    server: https://kubernetes.default.svc
    namespace: ${namespace}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
APPEOF

    kubectl apply -f "$app_yaml"
    log_info "Application '$name' creada en ArgoCD"
}

# Crear Applications para todos los componentes habilitados
create_argocd_applications() {
    log_header "Creando Applications en ArgoCD"

    # Añadir repos Helm necesarios para que ArgoCD los resuelva
    add_helm_repos_to_argocd

    if component_enabled kgateway; then
        create_argocd_app "kgateway" "kgateway" \
            "oci://cr.kgateway.dev/kgateway-dev/charts" \
            "${KGATEWAY_VERSION}" \
            "kgateway-system" \
            "${AUTOKUBE_ROOT}/manifests/kgateway/values.yaml" \
            "-3"
    fi

    if component_enabled vault; then
        create_argocd_app "vault" "vault" \
            "https://helm.releases.hashicorp.com" \
            "${VAULT_CHART_VERSION}" \
            "vault" \
            "${AUTOKUBE_ROOT}/manifests/vault/values.yaml" \
            "-3"
    fi

    if component_enabled eso; then
        create_argocd_app "external-secrets" "external-secrets" \
            "https://charts.external-secrets.io" \
            "${ESO_CHART_VERSION}" \
            "external-secrets" \
            "${AUTOKUBE_ROOT}/manifests/eso/values.yaml" \
            "-1"
    fi

    if component_enabled sonarqube; then
        create_argocd_app "sonarqube" "sonarqube" \
            "https://SonarSource.github.io/helm-chart-sonarqube" \
            "${SONARQUBE_CHART_VERSION}" \
            "sonarqube" \
            "${AUTOKUBE_ROOT}/manifests/sonarqube/values.yaml" \
            "-2"
    fi

    if component_enabled kyverno; then
        create_argocd_app "kyverno" "kyverno" \
            "https://kyverno.github.io/kyverno/" \
            "${KYVERNO_CHART_VERSION}" \
            "kyverno" \
            "${AUTOKUBE_ROOT}/manifests/kyverno/values.yaml" \
            "-2"
    fi

    log_success "Applications creadas en ArgoCD"
}

# Registrar repos Helm en ArgoCD para que pueda resolver los charts
add_helm_repos_to_argocd() {
    log_step "Registrando repos Helm en ArgoCD..."

    # ArgoCD usa ConfigMaps/Secrets para repos.
    # Añadimos via kubectl parcheando el configmap de ArgoCD.
    local repos='[]'

    if component_enabled vault; then
        repos=$(echo "$repos" | jq '. + [{"type":"helm","name":"hashicorp","url":"https://helm.releases.hashicorp.com"}]')
    fi
    if component_enabled eso; then
        repos=$(echo "$repos" | jq '. + [{"type":"helm","name":"external-secrets","url":"https://charts.external-secrets.io"}]')
    fi
    if component_enabled sonarqube; then
        repos=$(echo "$repos" | jq '. + [{"type":"helm","name":"sonarqube","url":"https://SonarSource.github.io/helm-chart-sonarqube"}]')
    fi
    if component_enabled kyverno; then
        repos=$(echo "$repos" | jq '. + [{"type":"helm","name":"kyverno","url":"https://kyverno.github.io/kyverno/"}]')
    fi
    if component_enabled kgateway; then
        repos=$(echo "$repos" | jq '. + [{"type":"helm","name":"kgateway","url":"cr.kgateway.dev/kgateway-dev/charts","enableOCI":"true"}]')
    fi

    # Parchear el configmap de argocd-cm con los repos
    kubectl patch configmap argocd-cm -n "$ARGOCD_NAMESPACE" \
        --type merge -p "{\"data\":{\"repositories\":\"$(echo "$repos" | sed 's/"/\\"/g')\"}}" 2>/dev/null || true

    # Método más fiable: crear Secrets por cada repo
    for row in $(echo "$repos" | jq -r '.[] | @base64'); do
        local repo_name repo_url repo_type enable_oci
        repo_name=$(echo "$row" | base64 -d | jq -r '.name')
        repo_url=$(echo "$row" | base64 -d | jq -r '.url')
        repo_type=$(echo "$row" | base64 -d | jq -r '.type')
        enable_oci=$(echo "$row" | base64 -d | jq -r '.enableOCI // "false"')

        kubectl apply -f - <<REPOEOF 2>/dev/null || true
apiVersion: v1
kind: Secret
metadata:
  name: repo-${repo_name}
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: helm
  name: ${repo_name}
  url: ${repo_url}
  enableOCI: "${enable_oci}"
REPOEOF
    done

    log_success "Repos Helm registrados en ArgoCD"
}

# Esperar a que todas las Applications estén sincronizadas
wait_for_argocd_apps() {
    log_step "Esperando sync de ArgoCD Applications..."

    local apps
    apps=$(kubectl get applications -n "$ARGOCD_NAMESPACE" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$apps" ]; then
        log_warn "No hay Applications en ArgoCD"
        return 0
    fi

    local timeout=600
    local end_time=$((SECONDS + timeout))

    while [ $SECONDS -lt $end_time ]; do
        local all_healthy=true
        local status_line=""

        for app in $apps; do
            local health sync_status
            health=$(kubectl get application "$app" -n "$ARGOCD_NAMESPACE" \
                -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
            sync_status=$(kubectl get application "$app" -n "$ARGOCD_NAMESPACE" \
                -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")

            status_line="${status_line} ${app}=${sync_status}/${health}"

            if [ "$health" != "Healthy" ] || [ "$sync_status" != "Synced" ]; then
                all_healthy=false
            fi
        done

        if [ "$all_healthy" = "true" ]; then
            log_success "Todas las Applications sincronizadas y healthy"
            return 0
        fi

        log_info "Estado:${status_line}"
        sleep 15
    done

    # Mostrar estado final aunque no todas estén healthy
    log_warn "Timeout esperando sync. Estado actual:"
    for app in $apps; do
        local health sync_status
        health=$(kubectl get application "$app" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "Unknown")
        sync_status=$(kubectl get application "$app" -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        log_info "  $app: sync=$sync_status health=$health"
    done
}

# --- Funciones para modo GitOps remoto ---

configure_argocd_repo() {
    if [ -z "$CFG_GITOPS_REPO_URL" ]; then
        log_warn "No se configuró gitops.repoURL, saltando configuración de repo"
        return 0
    fi

    log_step "Configurando repositorio GitOps en ArgoCD..."

    local username=""
    local password=""

    # Extraer credenciales de ~/.git-credentials si el repo es HTTPS
    if [[ "$CFG_GITOPS_REPO_URL" == https://* ]] && [ -f "$HOME/.git-credentials" ]; then
        # Extraer el hostname del repo URL
        local repo_host
        repo_host=$(echo "$CFG_GITOPS_REPO_URL" | sed 's|https://||' | cut -d'/' -f1)

        # Buscar credenciales para ese host en .git-credentials
        local cred_line
        cred_line=$(grep "https://.*@${repo_host}" "$HOME/.git-credentials" | head -1)
        if [ -n "$cred_line" ]; then
            # Formato: https://user:token@host
            local userpass
            userpass=$(echo "$cred_line" | sed "s|https://||" | sed "s|@${repo_host}.*||")
            username=$(echo "$userpass" | cut -d':' -f1)
            password=$(echo "$userpass" | cut -d':' -f2-)
            log_info "Credenciales encontradas en ~/.git-credentials para ${repo_host}"
        fi
    fi

    # También aceptar credenciales via variables de entorno
    if [ -n "${AUTOKUBE_GITOPS_USERNAME:-}" ]; then
        username="$AUTOKUBE_GITOPS_USERNAME"
    fi
    if [ -n "${AUTOKUBE_GITOPS_TOKEN:-}" ]; then
        password="$AUTOKUBE_GITOPS_TOKEN"
    fi

    # Crear Secret de tipo repository en ArgoCD
    if [ -n "$username" ] && [ -n "$password" ]; then
        kubectl apply -f - <<REPOEOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitops
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${CFG_GITOPS_REPO_URL}
  username: ${username}
  password: ${password}
REPOEOF
    else
        # Repo público o sin credenciales
        kubectl apply -f - <<REPOEOF
apiVersion: v1
kind: Secret
metadata:
  name: repo-gitops
  namespace: ${ARGOCD_NAMESPACE}
  labels:
    argocd.argoproj.io/secret-type: repository
stringData:
  type: git
  url: ${CFG_GITOPS_REPO_URL}
REPOEOF
        log_warn "No se encontraron credenciales para ${CFG_GITOPS_REPO_URL}. Si es privado, falla."
    fi

    log_success "Repositorio GitOps configurado"
}

apply_app_of_apps() {
    if [ -z "$CFG_GITOPS_REPO_URL" ]; then
        log_warn "No se configuró gitops.repoURL, saltando app-of-apps"
        return 0
    fi

    log_step "Aplicando app-of-apps..."

    local app_file="${CFG_DATA_DIR}/app-of-apps.yaml"
    render_template \
        "${AUTOKUBE_ROOT}/manifests/argocd/app-of-apps.yaml.tpl" \
        "$app_file" \
        "GITOPS_REPO_URL" "$CFG_GITOPS_REPO_URL" \
        "GITOPS_TARGET_REVISION" "$CFG_GITOPS_TARGET_REVISION" \
        "GITOPS_PATH" "$CFG_GITOPS_PATH"

    kubectl apply -f "$app_file"

    log_success "App-of-apps aplicada"
}
