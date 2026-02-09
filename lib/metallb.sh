#!/usr/bin/env bash
# metallb.sh - Instalación y configuración de MetalLB

readonly METALLB_NAMESPACE="metallb-system"
readonly METALLB_CHART_VERSION="0.14.9"

install_metallb() {
    log_header "MetalLB"

    helm_repo_add metallb https://metallb.github.io/metallb
    helm_repo_update

    ensure_namespace "$METALLB_NAMESPACE"

    log_step "Instalando MetalLB ${METALLB_CHART_VERSION}..."
    helm upgrade --install metallb metallb/metallb \
        --version "$METALLB_CHART_VERSION" \
        --namespace "$METALLB_NAMESPACE" \
        --values "${AUTOKUBE_ROOT}/manifests/metallb/values.yaml" \
        --wait \
        --timeout 5m

    # Esperar a que el controller esté ready
    wait_for_deployment "metallb-controller" "$METALLB_NAMESPACE" 120

    log_success "MetalLB instalado"

    # Configurar pool de IPs
    metallb_configure
}

metallb_configure() {
    log_step "Configurando MetalLB IPAddressPool..."

    local pool_file="${CFG_DATA_DIR}/metallb-ipaddresspool.yaml"
    render_template \
        "${AUTOKUBE_ROOT}/manifests/metallb/ipaddresspool.yaml.tpl" \
        "$pool_file" \
        "ADDRESS_RANGE" "$CFG_METALLB_ADDRESS_RANGE"
    kubectl apply -f "$pool_file"

    kubectl apply -f "${AUTOKUBE_ROOT}/manifests/metallb/l2advertisement.yaml"

    log_success "MetalLB configurado (rango: $CFG_METALLB_ADDRESS_RANGE)"
}
