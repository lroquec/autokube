#!/usr/bin/env bash
# argocd.sh - Bootstrap ArgoCD + GitOps

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

configure_argocd_repo() {
    if [ -z "$CFG_GITOPS_REPO_URL" ]; then
        log_warn "No se configuró gitops.repoURL, saltando configuración de repo"
        return 0
    fi

    log_step "Configurando repositorio GitOps en ArgoCD..."

    # Obtener password de ArgoCD
    local argocd_pass
    argocd_pass=$(kubectl get secret argocd-initial-admin-secret -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.data.password}' | base64 -d)

    # Login via CLI
    local argocd_port
    argocd_port=$(kubectl get svc argo-cd-argocd-server -n "$ARGOCD_NAMESPACE" \
        -o jsonpath='{.spec.ports[?(@.name=="http")].port}')

    # Port-forward temporario para configuración
    kubectl port-forward svc/argo-cd-argocd-server -n "$ARGOCD_NAMESPACE" 8090:"$argocd_port" &>/dev/null &
    local pf_pid=$!
    sleep 3

    # Login
    argocd login localhost:8090 \
        --username admin \
        --password "$argocd_pass" \
        --insecure \
        --grpc-web 2>/dev/null || true

    # Añadir repositorio (público por defecto)
    argocd repo add "$CFG_GITOPS_REPO_URL" --insecure-skip-server-verification 2>/dev/null || true

    # Cerrar port-forward
    kill $pf_pid 2>/dev/null || true

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

wait_for_argocd_sync() {
    if [ -z "$CFG_GITOPS_REPO_URL" ]; then
        return 0
    fi

    log_step "Esperando sync de ArgoCD..."

    local timeout=600
    local end_time=$((SECONDS + timeout))

    while [ $SECONDS -lt $end_time ]; do
        local health
        health=$(kubectl get application app-of-apps -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.health.status}' 2>/dev/null || echo "")

        if [ "$health" = "Healthy" ]; then
            log_success "ArgoCD sync completado - todas las apps healthy"
            return 0
        fi

        local sync_status
        sync_status=$(kubectl get application app-of-apps -n "$ARGOCD_NAMESPACE" \
            -o jsonpath='{.status.sync.status}' 2>/dev/null || echo "Unknown")
        log_info "Sync status: $sync_status, Health: $health"
        sleep 15
    done

    log_warn "Timeout esperando sync completo de ArgoCD. Verificar manualmente."
}
