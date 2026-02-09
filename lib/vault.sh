#!/usr/bin/env bash
# vault.sh - Instalación, init, unseal y configuración de Vault

readonly VAULT_NAMESPACE="vault"
readonly VAULT_CHART_VERSION="0.32.0"

install_vault_helm() {
    log_header "Vault"

    helm_repo_add hashicorp https://helm.releases.hashicorp.com
    helm_repo_update

    ensure_namespace "$VAULT_NAMESPACE"

    log_step "Instalando Vault ${VAULT_CHART_VERSION}..."
    helm upgrade --install vault hashicorp/vault \
        --version "$VAULT_CHART_VERSION" \
        --namespace "$VAULT_NAMESPACE" \
        --values "${AUTOKUBE_ROOT}/manifests/vault/values.yaml" \
        --timeout 5m

    # Vault no pasa --wait porque arranca en sealed state
    log_info "Esperando a que el pod vault-0 exista..."
    retry 30 5 kubectl get pod vault-0 -n "$VAULT_NAMESPACE" &>/dev/null

    log_success "Vault instalado (pendiente init/unseal)"
}

vault_post_install() {
    log_step "Post-instalación de Vault..."

    local init_file="${CFG_DATA_DIR}/vault/init.json"

    # Esperar a que el pod esté al menos Running (aunque no Ready, estará sealed)
    log_info "Esperando a que vault-0 esté Running..."
    local end_time=$((SECONDS + 120))
    while [ $SECONDS -lt $end_time ]; do
        local phase
        phase=$(kubectl get pod vault-0 -n "$VAULT_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "")
        if [ "$phase" = "Running" ]; then
            break
        fi
        sleep 5
    done

    # Determinar si necesitamos init o solo unseal
    local vault_status
    vault_status=$(kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- vault status -format=json 2>/dev/null || echo '{"initialized": false, "sealed": true}')

    local initialized
    initialized=$(echo "$vault_status" | jq -r '.initialized')

    if [ "$initialized" = "false" ]; then
        vault_init "$init_file"
    fi

    # Unseal
    local sealed
    vault_status=$(kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- vault status -format=json 2>/dev/null || echo '{"sealed": true}')
    sealed=$(echo "$vault_status" | jq -r '.sealed')

    if [ "$sealed" = "true" ]; then
        vault_unseal "$init_file"
    else
        log_info "Vault ya está unseal"
    fi

    # Esperar a que Vault esté Ready
    retry 12 5 kubectl get pod vault-0 -n "$VAULT_NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -q "True"

    # Configurar KV, K8s auth, policy y role
    vault_configure "$init_file"

    log_success "Vault configurado completamente"
}

vault_init() {
    local init_file=$1

    log_step "Inicializando Vault..."

    local init_output
    init_output=$(kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- \
        vault operator init -key-shares=1 -key-threshold=1 -format=json)

    echo "$init_output" > "$init_file"
    chmod 600 "$init_file"

    log_success "Vault inicializado. Keys guardadas en $init_file"
}

vault_unseal() {
    local init_file=$1

    if [ ! -f "$init_file" ]; then
        log_error "No se encontró $init_file para unseal"
        return 1
    fi

    log_step "Unsealing Vault..."

    local unseal_key
    unseal_key=$(jq -r '.unseal_keys_b64[0]' "$init_file")

    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- \
        vault operator unseal "$unseal_key" >/dev/null

    log_success "Vault unsealed"
}

vault_configure() {
    local init_file=$1

    if [ ! -f "$init_file" ]; then
        log_error "No se encontró $init_file para configuración"
        return 1
    fi

    local root_token
    root_token=$(jq -r '.root_token' "$init_file")

    log_step "Configurando Vault (KV v2, K8s auth, policy ESO)..."

    # Habilitar KV v2 si no está
    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- \
        sh -c "VAULT_TOKEN=${root_token} vault secrets enable -path=kv kv-v2 2>/dev/null || true"

    # Habilitar Kubernetes auth
    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- \
        sh -c "VAULT_TOKEN=${root_token} vault auth enable kubernetes 2>/dev/null || true"

    # Configurar Kubernetes auth
    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- \
        sh -c "VAULT_TOKEN=${root_token} vault write auth/kubernetes/config \
            kubernetes_host=\"https://\${KUBERNETES_SERVICE_HOST}:\${KUBERNETES_SERVICE_PORT}\""

    # Crear policy para ESO
    kubectl cp "${AUTOKUBE_ROOT}/manifests/vault/vault-policy.hcl" \
        "vault-0:/tmp/eso-policy.hcl" -n "$VAULT_NAMESPACE"

    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- \
        sh -c "VAULT_TOKEN=${root_token} vault policy write eso-policy /tmp/eso-policy.hcl"

    # Crear role para ESO
    kubectl exec vault-0 -n "$VAULT_NAMESPACE" -- \
        sh -c "VAULT_TOKEN=${root_token} vault write auth/kubernetes/role/eso-role \
            bound_service_account_names=external-secrets \
            bound_service_account_namespaces=external-secrets \
            policies=eso-policy \
            ttl=1h"

    log_success "Vault configurado: KV v2, K8s auth, policy y role para ESO"
}
