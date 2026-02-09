#!/usr/bin/env bash
# helm.sh - Helpers para Helm

# Añadir repo Helm si no existe
helm_repo_add() {
    local name=$1
    local url=$2

    if ! helm repo list 2>/dev/null | grep -q "^${name}"; then
        helm repo add "$name" "$url"
        log_info "Helm repo '$name' añadido"
    fi
}

# Actualizar repos
helm_repo_update() {
    helm repo update >/dev/null 2>&1
}

# Install o upgrade un chart
# Uso: helm_install <release> <chart> <namespace> [--values file] [extra args...]
helm_install() {
    local release=$1
    local chart=$2
    local namespace=$3
    shift 3

    ensure_namespace "$namespace"

    log_step "Instalando/actualizando $release en namespace $namespace..."
    helm upgrade --install "$release" "$chart" \
        --namespace "$namespace" \
        --wait \
        --timeout 10m \
        "$@"

    log_success "$release instalado en $namespace"
}

# Verificar si un release existe
helm_release_exists() {
    local release=$1
    local namespace=$2
    helm status "$release" -n "$namespace" &>/dev/null
}

# Instalar Gateway API CRDs
install_gateway_api_crds() {
    local version="v1.4.1"

    if kubectl get crd gateways.gateway.networking.k8s.io &>/dev/null; then
        log_info "Gateway API CRDs ya instalados"
        return 0
    fi

    log_step "Instalando Gateway API CRDs ${version}..."
    kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${version}/standard-install.yaml"
    log_success "Gateway API CRDs instalados"
}
