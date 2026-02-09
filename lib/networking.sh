#!/usr/bin/env bash
# networking.sh - TLS secrets, ReferenceGrants, rutas

# Crear TLS secret en un namespace
create_tls_secret_in_ns() {
    local namespace=$1
    local secret_name="${2:-wildcard-tls}"
    local ssl_path
    ssl_path=$(ssl_dir)

    ensure_namespace "$namespace"

    if kubectl get secret "$secret_name" -n "$namespace" &>/dev/null; then
        # Actualizar el secret existente
        kubectl create secret tls "$secret_name" \
            --cert="${ssl_path}/tls.crt" \
            --key="${ssl_path}/tls.key" \
            -n "$namespace" \
            --dry-run=client -o yaml | kubectl apply -f -
    else
        kubectl create secret tls "$secret_name" \
            --cert="${ssl_path}/tls.crt" \
            --key="${ssl_path}/tls.key" \
            -n "$namespace"
    fi
}

# Crear TLS secrets en todos los namespaces necesarios
create_tls_secrets() {
    log_step "Creando TLS secrets..."

    local namespaces=("kgateway-system")
    for ns in "${namespaces[@]}"; do
        create_tls_secret_in_ns "$ns"
        log_info "TLS secret creado en namespace $ns"
    done

    log_success "TLS secrets creados"
}

# Crear ReferenceGrant en un namespace para permitir cross-namespace references
create_reference_grant() {
    local target_namespace=$1
    local from_namespace=${2:-kgateway-system}

    kubectl apply -f - <<EOF
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-from-${from_namespace}
  namespace: ${target_namespace}
spec:
  from:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      namespace: ${from_namespace}
  to:
    - group: ""
      kind: Service
EOF
    log_info "ReferenceGrant creado en $target_namespace para $from_namespace"
}

# Aplicar HTTPRoute desde template
apply_httproute() {
    local template=$1
    local service_name=$2
    local service_namespace=$3
    local service_port=$4
    local hostname=$5

    local rendered
    rendered=$(cat "$template")
    rendered="${rendered//__SERVICE_NAME__/${service_name}}"
    rendered="${rendered//__SERVICE_NAMESPACE__/${service_namespace}}"
    rendered="${rendered//__SERVICE_PORT__/${service_port}}"
    rendered="${rendered//__HOSTNAME__/${hostname}}"
    rendered="${rendered//__BASE_DOMAIN__/${CFG_BASE_DOMAIN}}"

    echo "$rendered" | kubectl apply -f -
}
