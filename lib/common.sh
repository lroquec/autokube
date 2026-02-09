#!/usr/bin/env bash
# common.sh - Logging, colores, retry, helpers

set -euo pipefail

# Colores
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Logging
log_info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
log_success() { echo -e "${GREEN}[OK]${NC}    $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }
log_step()    { echo -e "${CYAN}${BOLD}▸${NC} $*"; }
log_header()  { echo -e "\n${BOLD}═══ $* ═══${NC}\n"; }

# Retry con backoff exponencial
# Uso: retry <intentos> <delay_inicial> <comando...>
retry() {
    local max_attempts=$1
    local delay=$2
    shift 2
    local attempt=1

    while [ $attempt -le "$max_attempts" ]; do
        if "$@"; then
            return 0
        fi
        if [ $attempt -lt "$max_attempts" ]; then
            log_warn "Intento $attempt/$max_attempts falló. Reintentando en ${delay}s..."
            sleep "$delay"
            delay=$((delay * 2))
        fi
        attempt=$((attempt + 1))
    done

    log_error "Comando falló tras $max_attempts intentos: $*"
    return 1
}

# Esperar a que un recurso k8s esté ready
# Uso: wait_for_ready <tipo> <nombre> <namespace> <timeout>
wait_for_ready() {
    local type=$1
    local name=$2
    local namespace=$3
    local timeout=${4:-300}

    log_info "Esperando a que $type/$name esté ready en namespace $namespace (timeout: ${timeout}s)..."
    if kubectl wait "$type/$name" -n "$namespace" --for=condition=ready --timeout="${timeout}s" 2>/dev/null; then
        log_success "$type/$name está ready"
        return 0
    fi
    log_error "Timeout esperando $type/$name"
    return 1
}

# Esperar a que un deployment tenga todas las réplicas ready
wait_for_deployment() {
    local name=$1
    local namespace=$2
    local timeout=${3:-300}

    log_info "Esperando deployment $name en $namespace (timeout: ${timeout}s)..."
    if kubectl rollout status "deployment/$name" -n "$namespace" --timeout="${timeout}s" 2>/dev/null; then
        log_success "Deployment $name está ready"
        return 0
    fi
    log_error "Timeout esperando deployment $name"
    return 1
}

# Esperar a que un pod con un label esté running
wait_for_pods() {
    local label=$1
    local namespace=$2
    local timeout=${3:-300}
    local end_time=$((SECONDS + timeout))

    log_info "Esperando pods con label $label en $namespace..."
    while [ $SECONDS -lt $end_time ]; do
        local ready
        ready=$(kubectl get pods -n "$namespace" -l "$label" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
        if [ -n "$ready" ] && ! echo "$ready" | grep -q "False"; then
            log_success "Pods con label $label están ready"
            return 0
        fi
        sleep 5
    done
    log_error "Timeout esperando pods con label $label"
    return 1
}

# Esperar a que un namespace exista
wait_for_namespace() {
    local ns=$1
    local timeout=${2:-60}
    local end_time=$((SECONDS + timeout))

    while [ $SECONDS -lt $end_time ]; do
        if kubectl get namespace "$ns" &>/dev/null; then
            return 0
        fi
        sleep 2
    done
    log_error "Timeout esperando namespace $ns"
    return 1
}

# Crear namespace si no existe
ensure_namespace() {
    local ns=$1
    if ! kubectl get namespace "$ns" &>/dev/null; then
        kubectl create namespace "$ns"
        log_info "Namespace $ns creado"
    fi
}

# Verificar que un comando existe
require_cmd() {
    local cmd=$1
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Comando requerido no encontrado: $cmd"
        return 1
    fi
}

# Detectar OS
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux" ;;
        *)      log_error "OS no soportado: $(uname -s)"; exit 1 ;;
    esac
}

# Detectar arquitectura
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        arm64|aarch64) echo "arm64" ;;
        *)             log_error "Arquitectura no soportada: $(uname -m)"; exit 1 ;;
    esac
}

# Confirmar acción destructiva
confirm_action() {
    local message=$1
    echo -e "${YELLOW}${BOLD}⚠  $message${NC}"
    read -r -p "¿Continuar? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) log_info "Operación cancelada."; return 1 ;;
    esac
}

# Template rendering: reemplaza __VAR__ con valor
render_template() {
    local template_file=$1
    local output_file=$2
    shift 2

    local content
    content=$(cat "$template_file")

    while [ $# -gt 0 ]; do
        local key=$1
        local value=$2
        content="${content//__${key}__/${value}}"
        shift 2
    done

    echo "$content" > "$output_file"
}

# Trap para cleanup
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Autokube terminó con errores (código: $exit_code)"
    fi
}
