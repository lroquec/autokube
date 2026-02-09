#!/usr/bin/env bash
# ssl.sh - Generación de CA + wildcard cert y gestión de trust store

readonly SSL_DIR_REL="ssl"

ssl_dir() {
    echo "${CFG_DATA_DIR}/${SSL_DIR_REL}"
}

# Generar CA y certificado wildcard
generate_ssl_certs() {
    local ssl_path
    ssl_path=$(ssl_dir)

    if [ -f "${ssl_path}/ca.crt" ] && [ -f "${ssl_path}/tls.crt" ] && [ -f "${ssl_path}/tls.key" ]; then
        log_success "Certificados SSL ya existen en ${ssl_path}/"
        return 0
    fi

    log_step "Generando certificados SSL..."
    mkdir -p "$ssl_path"

    local domain="*.${CFG_BASE_DOMAIN}"

    # Generar CA
    openssl genrsa -out "${ssl_path}/ca.key" 4096 2>/dev/null
    openssl req -x509 -new -nodes \
        -key "${ssl_path}/ca.key" \
        -sha256 -days 3650 \
        -out "${ssl_path}/ca.crt" \
        -subj "/C=ES/ST=Local/L=Dev/O=Autokube/CN=Autokube CA" \
        2>/dev/null

    # Generar key del servidor
    openssl genrsa -out "${ssl_path}/tls.key" 2048 2>/dev/null

    # CSR con SANs
    local san_cnf="${ssl_path}/san.cnf"
    cat > "$san_cnf" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C = ES
ST = Local
L = Dev
O = Autokube
CN = ${domain}

[v3_req]
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${domain}
DNS.2 = ${CFG_BASE_DOMAIN}
DNS.3 = argocd.${CFG_BASE_DOMAIN}
DNS.4 = vault.${CFG_BASE_DOMAIN}
DNS.5 = sonarqube.${CFG_BASE_DOMAIN}
EOF

    openssl req -new \
        -key "${ssl_path}/tls.key" \
        -out "${ssl_path}/tls.csr" \
        -config "$san_cnf" \
        2>/dev/null

    # Firmar con CA
    openssl x509 -req \
        -in "${ssl_path}/tls.csr" \
        -CA "${ssl_path}/ca.crt" \
        -CAkey "${ssl_path}/ca.key" \
        -CAcreateserial \
        -out "${ssl_path}/tls.crt" \
        -days 3650 \
        -sha256 \
        -extensions v3_req \
        -extfile "$san_cnf" \
        2>/dev/null

    # Limpiar archivos temporales
    rm -f "${ssl_path}/tls.csr" "${ssl_path}/san.cnf" "${ssl_path}/ca.srl"

    log_success "Certificados SSL generados en ${ssl_path}/"
}

# Instalar CA en el trust store del sistema
trust_ca() {
    local ssl_path
    ssl_path=$(ssl_dir)

    if [ ! -f "${ssl_path}/ca.crt" ]; then
        log_error "CA no encontrada en ${ssl_path}/ca.crt"
        return 1
    fi

    local os
    os=$(detect_os)

    log_step "Instalando CA en trust store del sistema..."

    case "$os" in
        darwin)
            sudo security add-trusted-cert -d -r trustRoot \
                -k /Library/Keychains/System.keychain \
                "${ssl_path}/ca.crt"
            ;;
        linux)
            if [ -d /usr/local/share/ca-certificates ]; then
                sudo cp "${ssl_path}/ca.crt" /usr/local/share/ca-certificates/autokube-ca.crt
                sudo update-ca-certificates
            elif [ -d /etc/pki/ca-trust/source/anchors ]; then
                sudo cp "${ssl_path}/ca.crt" /etc/pki/ca-trust/source/anchors/autokube-ca.crt
                sudo update-ca-trust
            else
                log_error "No se encontró directorio de trust store en este sistema Linux"
                return 1
            fi
            ;;
    esac

    log_success "CA instalada en trust store"
}

# Eliminar CA del trust store
untrust_ca() {
    local os
    os=$(detect_os)

    log_step "Eliminando CA del trust store..."

    case "$os" in
        darwin)
            sudo security delete-certificate -c "Autokube CA" /Library/Keychains/System.keychain 2>/dev/null || true
            ;;
        linux)
            if [ -f /usr/local/share/ca-certificates/autokube-ca.crt ]; then
                sudo rm -f /usr/local/share/ca-certificates/autokube-ca.crt
                sudo update-ca-certificates --fresh
            elif [ -f /etc/pki/ca-trust/source/anchors/autokube-ca.crt ]; then
                sudo rm -f /etc/pki/ca-trust/source/anchors/autokube-ca.crt
                sudo update-ca-trust
            fi
            ;;
    esac

    log_info "CA eliminada del trust store"
}
