#!/usr/bin/env bash
# kyverno.sh - Instalación de Kyverno y políticas

readonly KYVERNO_NAMESPACE="kyverno"
readonly KYVERNO_CHART_VERSION="3.7.0"

install_kyverno() {
    log_header "Kyverno"

    helm_repo_add kyverno https://kyverno.github.io/kyverno/
    helm_repo_update

    helm_install kyverno kyverno/kyverno "$KYVERNO_NAMESPACE" \
        --values "${AUTOKUBE_ROOT}/manifests/kyverno/values.yaml" \
        --version "$KYVERNO_CHART_VERSION"

    log_success "Kyverno instalado"
}

kyverno_post_install() {
    log_step "Aplicando políticas Kyverno..."

    # Esperar a que Kyverno esté completamente ready
    wait_for_deployment "kyverno-admission-controller" "$KYVERNO_NAMESPACE" 120

    # Pequeña espera para que los webhooks estén registrados
    sleep 10

    # Aplicar políticas
    kubectl apply -f "${AUTOKUBE_ROOT}/manifests/kyverno/policies/"

    log_success "Políticas Kyverno aplicadas (modo Audit)"
}
