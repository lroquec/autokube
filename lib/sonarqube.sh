#!/usr/bin/env bash
# sonarqube.sh - Instalación de SonarQube Community

readonly SONARQUBE_NAMESPACE="sonarqube"
readonly SONARQUBE_CHART_VERSION="2026.1.0"

install_sonarqube() {
    log_header "SonarQube Community"

    helm_repo_add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
    helm_repo_update

    ensure_namespace "$SONARQUBE_NAMESPACE"

    # SonarQube necesita vm.max_map_count en el nodo
    if is_kind_cluster; then
        log_info "Configurando vm.max_map_count en el nodo Kind..."
        docker exec "${CFG_CLUSTER_NAME}-control-plane" sysctl -w vm.max_map_count=524288 >/dev/null 2>&1 || true
        docker exec "${CFG_CLUSTER_NAME}-control-plane" sysctl -w fs.file-max=131072 >/dev/null 2>&1 || true
    else
        log_warn "Cluster externo: asegúrate de que vm.max_map_count >= 524288 en los nodos (sysctl -w vm.max_map_count=524288)"
    fi

    local values_file="${AUTOKUBE_ROOT}/manifests/sonarqube/values.yaml"
    is_kind_cluster || values_file="${AUTOKUBE_ROOT}/manifests/sonarqube/values-external.yaml"

    log_step "Instalando SonarQube Community ${SONARQUBE_CHART_VERSION}..."
    helm upgrade --install sonarqube sonarqube/sonarqube \
        --version "$SONARQUBE_CHART_VERSION" \
        --namespace "$SONARQUBE_NAMESPACE" \
        --values "$values_file" \
        --timeout 10m \
        --wait

    log_success "SonarQube Community instalado"
    log_info "Credenciales por defecto: admin / admin"
}
