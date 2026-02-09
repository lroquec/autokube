#!/usr/bin/env bash
# external.sh - Conexión a cluster externo y desinstalación de componentes

external_cluster_connect() {
    log_step "Conectando a cluster externo..."

    # Cambiar contexto si se configuró uno específico
    if [ -n "$CFG_CLUSTER_CONTEXT" ]; then
        if ! kubectl config use-context "$CFG_CLUSTER_CONTEXT" &>/dev/null; then
            log_error "No se pudo cambiar al contexto '$CFG_CLUSTER_CONTEXT'. Verifica tu kubeconfig."
            return 1
        fi
        log_info "Usando contexto: $CFG_CLUSTER_CONTEXT"
    else
        local current_ctx
        current_ctx=$(kubectl config current-context 2>/dev/null || echo "")
        if [ -z "$current_ctx" ]; then
            log_error "No hay contexto de kubeconfig activo. Configura cluster.context o selecciona uno con kubectl."
            return 1
        fi
        log_info "Usando contexto actual: $current_ctx"
    fi

    # Verificar conectividad
    if ! kubectl cluster-info &>/dev/null; then
        log_error "No se puede conectar al cluster. Verifica tu kubeconfig y conectividad."
        return 1
    fi

    log_success "Conectado al cluster externo"
}

uninstall_components() {
    log_header "Desinstalando componentes de Autokube"

    # Orden inverso de instalación
    local releases=(
        "kyverno:kyverno"
        "sonarqube:sonarqube"
        "external-secrets:external-secrets"
        "vault:vault"
        "kgateway:kgateway-system"
        "metallb:metallb-system"
        "argo-cd:argocd"
    )

    for release_ns in "${releases[@]}"; do
        local release="${release_ns%%:*}"
        local ns="${release_ns##*:}"
        if helm status "$release" -n "$ns" &>/dev/null; then
            log_step "Desinstalando $release..."
            helm uninstall "$release" -n "$ns" --wait 2>/dev/null || true
            log_info "$release desinstalado"
        fi
    done

    log_success "Componentes desinstalados"
}
