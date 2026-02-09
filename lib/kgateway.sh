#!/usr/bin/env bash
# kgateway.sh - Instalación y configuración de kgateway (Solo.io)

readonly KGATEWAY_NAMESPACE="kgateway-system"
readonly KGATEWAY_VERSION="v2.2.0"

install_kgateway() {
    log_header "kgateway"

    # Instalar Gateway API CRDs
    install_gateway_api_crds

    ensure_namespace "$KGATEWAY_NAMESPACE"

    # Instalar kgateway via Helm OCI
    log_step "Instalando kgateway ${KGATEWAY_VERSION}..."
    helm upgrade --install kgateway \
        "oci://cr.kgateway.dev/kgateway-dev/charts/kgateway" \
        --version "${KGATEWAY_VERSION}" \
        --namespace "$KGATEWAY_NAMESPACE" \
        --values "${AUTOKUBE_ROOT}/manifests/kgateway/values.yaml" \
        --wait \
        --timeout 5m

    log_success "kgateway instalado"
}

kgateway_patch_nodeports() {
    log_step "Parcheando NodePorts del gateway..."

    # Esperar a que el Gateway esté Accepted
    log_info "Esperando a que el Gateway esté accepted..."
    local gw_timeout=$((SECONDS + 180))
    while [ $SECONDS -lt $gw_timeout ]; do
        local accepted
        accepted=$(kubectl get gateway main-gateway -n "$KGATEWAY_NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || echo "")
        if [ "$accepted" = "True" ]; then
            log_success "Gateway accepted"
            break
        fi
        sleep 5
    done

    # Esperar a que el Service exista
    log_info "Esperando Service del gateway..."
    local svc_timeout=$((SECONDS + 60))
    while [ $SECONDS -lt $svc_timeout ]; do
        if kubectl get svc main-gateway -n "$KGATEWAY_NAMESPACE" &>/dev/null; then
            break
        fi
        sleep 3
    done

    kubectl patch svc main-gateway -n "$KGATEWAY_NAMESPACE" --type='json' -p='[
        {"op": "replace", "path": "/spec/ports/0/nodePort", "value": 31080},
        {"op": "replace", "path": "/spec/ports/1/nodePort", "value": 31443}
    ]'
    log_success "Gateway NodePorts fijados (31080/31443)"
}

kgateway_post_install() {
    log_step "Configurando kgateway Gateway y rutas..."

    ensure_namespace "$KGATEWAY_NAMESPACE"

    # Aplicar Gateway
    local gateway_file="${CFG_DATA_DIR}/kgateway-gateway.yaml"
    render_template \
        "${AUTOKUBE_ROOT}/manifests/kgateway/gateway.yaml.tpl" \
        "$gateway_file" \
        "BASE_DOMAIN" "$CFG_BASE_DOMAIN"
    kubectl apply -f "$gateway_file"

    # Parchear NodePorts
    kgateway_patch_nodeports

    # Crear ReferenceGrants y HTTPRoutes para cada componente habilitado
    if component_enabled argocd; then
        ensure_namespace "argocd"
        create_reference_grant "argocd"
        local argocd_route="${CFG_DATA_DIR}/httproute-argocd.yaml"
        render_template \
            "${AUTOKUBE_ROOT}/manifests/kgateway/httproutes/argocd.yaml.tpl" \
            "$argocd_route" \
            "BASE_DOMAIN" "$CFG_BASE_DOMAIN"
        kubectl apply -f "$argocd_route"
        log_info "HTTPRoute argocd.${CFG_BASE_DOMAIN} creado"
    fi

    if component_enabled vault; then
        ensure_namespace "vault"
        create_reference_grant "vault"
        local vault_route="${CFG_DATA_DIR}/httproute-vault.yaml"
        render_template \
            "${AUTOKUBE_ROOT}/manifests/kgateway/httproutes/vault.yaml.tpl" \
            "$vault_route" \
            "BASE_DOMAIN" "$CFG_BASE_DOMAIN"
        kubectl apply -f "$vault_route"
        log_info "HTTPRoute vault.${CFG_BASE_DOMAIN} creado"
    fi

    if component_enabled sonarqube; then
        ensure_namespace "sonarqube"
        create_reference_grant "sonarqube"
        local sq_route="${CFG_DATA_DIR}/httproute-sonarqube.yaml"
        render_template \
            "${AUTOKUBE_ROOT}/manifests/kgateway/httproutes/sonarqube.yaml.tpl" \
            "$sq_route" \
            "BASE_DOMAIN" "$CFG_BASE_DOMAIN"
        kubectl apply -f "$sq_route"
        log_info "HTTPRoute sonarqube.${CFG_BASE_DOMAIN} creado"
    fi

    log_success "kgateway configurado con Gateway y HTTPRoutes"
}
