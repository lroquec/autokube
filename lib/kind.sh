#!/usr/bin/env bash
# kind.sh - Ciclo de vida del cluster Kind

kind_cluster_exists() {
    kind get clusters 2>/dev/null | grep -q "^${CFG_CLUSTER_NAME}$"
}

kind_container_running() {
    local state
    state=$(docker inspect -f '{{.State.Status}}' "${CFG_CLUSTER_NAME}-control-plane" 2>/dev/null || echo "not_found")
    [ "$state" = "running" ]
}

kind_container_exists() {
    docker inspect "${CFG_CLUSTER_NAME}-control-plane" &>/dev/null
}

kind_up() {
    log_header "Cluster Kind"

    if kind_container_running; then
        log_success "Cluster '${CFG_CLUSTER_NAME}' ya está ejecutándose"
        kubectl cluster-info --context "kind-${CFG_CLUSTER_NAME}" &>/dev/null || true
        return 0
    fi

    if kind_container_exists; then
        log_info "Cluster '${CFG_CLUSTER_NAME}' existe pero está parado. Arrancando..."
        docker start "${CFG_CLUSTER_NAME}-control-plane"
        # Esperar a que el API server esté listo
        retry 30 2 kubectl cluster-info --context "kind-${CFG_CLUSTER_NAME}" &>/dev/null
        log_success "Cluster '${CFG_CLUSTER_NAME}' arrancado"
        return 0
    fi

    # Crear cluster nuevo
    log_step "Creando cluster Kind '${CFG_CLUSTER_NAME}'..."

    # Renderizar template
    local config_file="${CFG_DATA_DIR}/kind-cluster.yaml"
    render_template \
        "${AUTOKUBE_ROOT}/manifests/kind-cluster.yaml.tpl" \
        "$config_file" \
        "CLUSTER_NAME" "$CFG_CLUSTER_NAME" \
        "HTTP_PORT" "$CFG_HTTP_PORT" \
        "HTTPS_PORT" "$CFG_HTTPS_PORT" \
        "DATA_DIR" "$CFG_DATA_DIR"

    kind create cluster --config "$config_file" --wait 120s

    # Verificar conectividad
    kubectl cluster-info --context "kind-${CFG_CLUSTER_NAME}"
    log_success "Cluster '${CFG_CLUSTER_NAME}' creado y funcionando"
}

kind_down() {
    local container_name="${CFG_CLUSTER_NAME}-control-plane"

    if ! kind_container_exists; then
        log_warn "Cluster '${CFG_CLUSTER_NAME}' no existe"
        return 0
    fi

    if kind_container_running; then
        log_step "Parando cluster '${CFG_CLUSTER_NAME}'..."
        docker stop "$container_name"
        log_success "Cluster parado"
    else
        log_info "Cluster '${CFG_CLUSTER_NAME}' ya está parado"
    fi
}

kind_destroy() {
    if kind_cluster_exists; then
        log_step "Eliminando cluster '${CFG_CLUSTER_NAME}'..."
        kind delete cluster --name "$CFG_CLUSTER_NAME"
        log_success "Cluster eliminado"
    else
        log_info "Cluster '${CFG_CLUSTER_NAME}' no existe"
    fi
}
