#!/usr/bin/env bash
# deps.sh - Detección e instalación de dependencias

# Versiones de referencia
readonly KIND_VERSION="v0.31.0"
readonly YQ_VERSION="v4.52.1"
readonly JQ_VERSION="1.8"
readonly ARGOCD_CLI_VERSION="v2.14.11"

# Verificar si Docker está funcionando
check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker no está instalado. Instálalo desde https://docs.docker.com/get-docker/"
        return 1
    fi
    if ! docker info &>/dev/null 2>&1; then
        log_error "Docker no está ejecutándose. Arranca Docker Desktop o el servicio dockerd."
        return 1
    fi
    log_success "Docker OK ($(docker version --format '{{.Server.Version}}' 2>/dev/null || echo 'unknown'))"
}

# Verificar si un comando existe con versión mínima (solo verifica existencia)
check_tool() {
    local name=$1
    if command -v "$name" &>/dev/null; then
        return 0
    fi
    return 1
}

# Instalar kind
install_kind() {
    local os arch
    os=$(detect_os)
    arch=$(detect_arch)

    log_step "Instalando kind ${KIND_VERSION}..."
    local url="https://github.com/kubernetes-sigs/kind/releases/download/${KIND_VERSION}/kind-${os}-${arch}"

    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install kind
    else
        local dest="${HOME}/.local/bin/kind"
        mkdir -p "${HOME}/.local/bin"
        curl -fsSL "$url" -o "$dest"
        chmod +x "$dest"
        log_info "kind instalado en $dest"
    fi
}

# Instalar kubectl
install_kubectl() {
    local os arch
    os=$(detect_os)
    arch=$(detect_arch)

    log_step "Instalando kubectl..."
    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install kubectl
    else
        local version
        version=$(curl -fsSL https://dl.k8s.io/release/stable.txt)
        local dest="${HOME}/.local/bin/kubectl"
        mkdir -p "${HOME}/.local/bin"
        curl -fsSL "https://dl.k8s.io/release/${version}/bin/${os}/${arch}/kubectl" -o "$dest"
        chmod +x "$dest"
        log_info "kubectl instalado en $dest"
    fi
}

# Instalar helm
install_helm() {
    log_step "Instalando helm..."
    local os
    os=$(detect_os)

    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install helm
    else
        curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
}

# Instalar yq
install_yq() {
    local os arch
    os=$(detect_os)
    arch=$(detect_arch)

    log_step "Instalando yq ${YQ_VERSION}..."
    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install yq
    else
        local binary="yq_${os}_${arch}"
        local dest="${HOME}/.local/bin/yq"
        mkdir -p "${HOME}/.local/bin"
        curl -fsSL "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${binary}" -o "$dest"
        chmod +x "$dest"
        log_info "yq instalado en $dest"
    fi
}

# Instalar jq
install_jq() {
    local os arch
    os=$(detect_os)
    arch=$(detect_arch)

    log_step "Instalando jq..."
    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install jq
    else
        local binary
        case "${os}-${arch}" in
            linux-amd64) binary="jq-linux-amd64" ;;
            linux-arm64) binary="jq-linux-arm64" ;;
            *) log_error "jq: plataforma no soportada ${os}-${arch}"; return 1 ;;
        esac
        local dest="${HOME}/.local/bin/jq"
        mkdir -p "${HOME}/.local/bin"
        curl -fsSL "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/${binary}" -o "$dest"
        chmod +x "$dest"
        log_info "jq instalado en $dest"
    fi
}

# Instalar vault CLI
install_vault() {
    log_step "Instalando vault CLI..."
    local os
    os=$(detect_os)

    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew tap hashicorp/tap 2>/dev/null || true
        brew install hashicorp/tap/vault
    else
        local arch
        arch=$(detect_arch)
        local vault_version="1.19.2"
        local url="https://releases.hashicorp.com/vault/${vault_version}/vault_${vault_version}_${os}_${arch}.zip"
        local tmpdir
        tmpdir=$(mktemp -d)
        curl -fsSL "$url" -o "${tmpdir}/vault.zip"
        unzip -o "${tmpdir}/vault.zip" -d "${tmpdir}" >/dev/null
        mkdir -p "${HOME}/.local/bin"
        mv "${tmpdir}/vault" "${HOME}/.local/bin/vault"
        chmod +x "${HOME}/.local/bin/vault"
        rm -rf "${tmpdir}"
        log_info "vault instalado en ${HOME}/.local/bin/vault"
    fi
}

# Instalar argocd CLI
install_argocd_cli() {
    local os arch
    os=$(detect_os)
    arch=$(detect_arch)

    log_step "Instalando argocd CLI ${ARGOCD_CLI_VERSION}..."
    if [ "$os" = "darwin" ] && command -v brew &>/dev/null; then
        brew install argocd
    else
        local dest="${HOME}/.local/bin/argocd"
        mkdir -p "${HOME}/.local/bin"
        curl -fsSL "https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_CLI_VERSION}/argocd-${os}-${arch}" -o "$dest"
        chmod +x "$dest"
        log_info "argocd instalado en $dest"
    fi
}

# Verificar e instalar todas las dependencias
check_and_install_deps() {
    log_header "Verificando dependencias"

    # Asegurar que ~/.local/bin está en PATH
    if [[ ":$PATH:" != *":${HOME}/.local/bin:"* ]]; then
        export PATH="${HOME}/.local/bin:$PATH"
    fi

    local tools_to_install=()

    # Docker y Kind solo son necesarios para clusters Kind
    if is_kind_cluster; then
        check_docker || exit 1

        if check_tool kind; then
            log_success "kind OK ($(kind version 2>/dev/null || echo 'installed'))"
        else
            tools_to_install+=(kind)
        fi
    else
        log_info "Cluster externo: Docker y Kind no son necesarios"
    fi

    if check_tool kubectl; then
        log_success "kubectl OK ($(kubectl version --client -o json 2>/dev/null | jq -r '.clientVersion.gitVersion' 2>/dev/null || echo 'installed'))"
    else
        tools_to_install+=(kubectl)
    fi

    if check_tool helm; then
        log_success "helm OK ($(helm version --short 2>/dev/null || echo 'installed'))"
    else
        tools_to_install+=(helm)
    fi

    if check_tool yq; then
        log_success "yq OK ($(yq --version 2>/dev/null || echo 'installed'))"
    else
        tools_to_install+=(yq)
    fi

    if check_tool jq; then
        log_success "jq OK ($(jq --version 2>/dev/null || echo 'installed'))"
    else
        tools_to_install+=(jq)
    fi

    if check_tool vault; then
        log_success "vault OK ($(vault version 2>/dev/null || echo 'installed'))"
    else
        tools_to_install+=(vault)
    fi

    if check_tool argocd; then
        log_success "argocd CLI OK ($(argocd version --client --short 2>/dev/null || echo 'installed'))"
    else
        tools_to_install+=(argocd)
    fi

    if [ ${#tools_to_install[@]} -gt 0 ]; then
        log_info "Herramientas a instalar: ${tools_to_install[*]}"
        for tool in "${tools_to_install[@]}"; do
            case "$tool" in
                kind)     install_kind ;;
                kubectl)  install_kubectl ;;
                helm)     install_helm ;;
                yq)       install_yq ;;
                jq)       install_jq ;;
                vault)    install_vault ;;
                argocd)   install_argocd_cli ;;
            esac
        done
        log_success "Todas las dependencias instaladas"
    else
        log_success "Todas las dependencias están disponibles"
    fi
}
