#!/usr/bin/env bash
# eso.sh - Instalación de External Secrets Operator + ClusterSecretStore

readonly ESO_NAMESPACE="external-secrets"
readonly ESO_CHART_VERSION="0.15.1"

install_eso() {
    log_header "External Secrets Operator"

    helm_repo_add external-secrets https://charts.external-secrets.io
    helm_repo_update

    helm_install external-secrets external-secrets/external-secrets "$ESO_NAMESPACE" \
        --values "${AUTOKUBE_ROOT}/manifests/eso/values.yaml" \
        --version "$ESO_CHART_VERSION"

    # Esperar a que el webhook esté ready (necesario para CRDs)
    wait_for_deployment "external-secrets-webhook" "$ESO_NAMESPACE" 120
    wait_for_deployment "external-secrets-cert-controller" "$ESO_NAMESPACE" 120

    log_success "External Secrets Operator instalado"
}

eso_post_install() {
    log_step "Configurando ClusterSecretStore..."

    # Esperar un momento para que los CRDs estén completamente disponibles
    sleep 5

    # Aplicar ClusterSecretStore apuntando a Vault
    kubectl apply -f "${AUTOKUBE_ROOT}/manifests/eso/cluster-secret-store.yaml.tpl"

    # Esperar a que esté ready
    log_info "Esperando a que ClusterSecretStore vault-backend esté ready..."
    local end_time=$((SECONDS + 60))
    while [ $SECONDS -lt $end_time ]; do
        local status
        status=$(kubectl get clustersecretstore vault-backend -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [ "$status" = "True" ]; then
            log_success "ClusterSecretStore vault-backend está ready"
            return 0
        fi
        sleep 5
    done

    log_warn "ClusterSecretStore vault-backend no alcanzó estado Ready. Verificar conectividad con Vault."
}
