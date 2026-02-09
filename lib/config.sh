#!/usr/bin/env bash
# config.sh - Parsing YAML config con yq

# Directorio raíz del proyecto
AUTOKUBE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUTOKUBE_CONFIG="${AUTOKUBE_CONFIG:-${AUTOKUBE_ROOT}/autokube.yaml}"

# Valores por defecto
CFG_CLUSTER_NAME="autokube"
CFG_BASE_DOMAIN="127.0.0.1.nip.io"
CFG_HTTP_PORT="80"
CFG_HTTPS_PORT="443"
CFG_SSL_ENABLED="true"
CFG_SSL_TRUST_CA="false"
CFG_GITOPS_ENABLED="true"
CFG_GITOPS_REPO_URL=""
CFG_GITOPS_TARGET_REVISION="main"
CFG_GITOPS_PATH="apps"
CFG_COMP_ARGOCD="true"
CFG_COMP_VAULT="true"
CFG_COMP_ESO="true"
CFG_COMP_KGATEWAY="true"
CFG_COMP_SONARQUBE="true"
CFG_COMP_KYVERNO="true"
CFG_DATA_DIR="${AUTOKUBE_ROOT}/data"

# Helper para leer un valor del YAML (devuelve default si no existe o es null)
cfg_read() {
    local path=$1
    local default=${2:-}
    local value
    value=$(yq eval "$path // \"\"" "$AUTOKUBE_CONFIG" 2>/dev/null || echo "")
    if [ -z "$value" ] || [ "$value" = "null" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Cargar configuración
load_config() {
    if [ ! -f "$AUTOKUBE_CONFIG" ]; then
        log_warn "No se encontró $AUTOKUBE_CONFIG, usando valores por defecto"
        log_info "Puedes copiar autokube.yaml.example a autokube.yaml para personalizar"
        return 0
    fi

    log_info "Cargando configuración desde $AUTOKUBE_CONFIG"

    CFG_CLUSTER_NAME=$(cfg_read '.cluster.name' "$CFG_CLUSTER_NAME")
    CFG_BASE_DOMAIN=$(cfg_read '.network.baseDomain' "$CFG_BASE_DOMAIN")
    CFG_HTTP_PORT=$(cfg_read '.network.httpPort' "$CFG_HTTP_PORT")
    CFG_HTTPS_PORT=$(cfg_read '.network.httpsPort' "$CFG_HTTPS_PORT")
    CFG_SSL_ENABLED=$(cfg_read '.ssl.enabled' "$CFG_SSL_ENABLED")
    CFG_SSL_TRUST_CA=$(cfg_read '.ssl.trustCA' "$CFG_SSL_TRUST_CA")
    CFG_GITOPS_ENABLED=$(cfg_read '.gitops.enabled' "$CFG_GITOPS_ENABLED")
    CFG_GITOPS_REPO_URL=$(cfg_read '.gitops.repoURL' "$CFG_GITOPS_REPO_URL")
    CFG_GITOPS_TARGET_REVISION=$(cfg_read '.gitops.targetRevision' "$CFG_GITOPS_TARGET_REVISION")
    CFG_GITOPS_PATH=$(cfg_read '.gitops.path' "$CFG_GITOPS_PATH")
    CFG_COMP_ARGOCD=$(cfg_read '.components.argocd.enabled' "$CFG_COMP_ARGOCD")
    CFG_COMP_VAULT=$(cfg_read '.components.vault.enabled' "$CFG_COMP_VAULT")
    CFG_COMP_ESO=$(cfg_read '.components.eso.enabled' "$CFG_COMP_ESO")
    CFG_COMP_KGATEWAY=$(cfg_read '.components.kgateway.enabled' "$CFG_COMP_KGATEWAY")
    CFG_COMP_SONARQUBE=$(cfg_read '.components.sonarqube.enabled' "$CFG_COMP_SONARQUBE")
    CFG_COMP_KYVERNO=$(cfg_read '.components.kyverno.enabled' "$CFG_COMP_KYVERNO")

    local data_dir
    data_dir=$(cfg_read '.persistence.dataDir' "./data")
    # Resolver path relativo
    if [[ "$data_dir" == ./* ]] || [[ "$data_dir" == ../* ]]; then
        CFG_DATA_DIR="${AUTOKUBE_ROOT}/${data_dir}"
    else
        CFG_DATA_DIR="$data_dir"
    fi

    # Validaciones
    if [ "$CFG_GITOPS_ENABLED" = "true" ] && [ "$CFG_COMP_ARGOCD" = "true" ] && [ -z "$CFG_GITOPS_REPO_URL" ]; then
        log_warn "GitOps habilitado pero gitops.repoURL no configurado. Se usará instalación imperativa."
        CFG_GITOPS_ENABLED="false"
    fi

    log_success "Configuración cargada (cluster: $CFG_CLUSTER_NAME, dominio: $CFG_BASE_DOMAIN)"
}

# Verificar si un componente está habilitado
component_enabled() {
    local component=$1
    case "$component" in
        argocd)    [ "$CFG_COMP_ARGOCD" = "true" ] ;;
        vault)     [ "$CFG_COMP_VAULT" = "true" ] ;;
        eso)       [ "$CFG_COMP_ESO" = "true" ] ;;
        kgateway)  [ "$CFG_COMP_KGATEWAY" = "true" ] ;;
        sonarqube) [ "$CFG_COMP_SONARQUBE" = "true" ] ;;
        kyverno)   [ "$CFG_COMP_KYVERNO" = "true" ] ;;
        *) return 1 ;;
    esac
}

# Mostrar configuración actual
print_config() {
    log_header "Configuración"
    echo "  Cluster:     $CFG_CLUSTER_NAME"
    echo "  Dominio:     $CFG_BASE_DOMAIN"
    echo "  Puertos:     HTTP=$CFG_HTTP_PORT HTTPS=$CFG_HTTPS_PORT"
    echo "  SSL:         $CFG_SSL_ENABLED (trust CA: $CFG_SSL_TRUST_CA)"
    echo "  GitOps:      $CFG_GITOPS_ENABLED"
    if [ "$CFG_GITOPS_ENABLED" = "true" ]; then
        echo "  Repo:        $CFG_GITOPS_REPO_URL ($CFG_GITOPS_TARGET_REVISION)"
    fi
    echo "  Componentes: argocd=$CFG_COMP_ARGOCD vault=$CFG_COMP_VAULT eso=$CFG_COMP_ESO"
    echo "               kgateway=$CFG_COMP_KGATEWAY sonarqube=$CFG_COMP_SONARQUBE kyverno=$CFG_COMP_KYVERNO"
    echo "  Data dir:    $CFG_DATA_DIR"
    echo ""
}
