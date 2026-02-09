# Autokube

Instalador de entorno Kubernetes local para desarrollo. Un solo comando despliega un cluster [Kind](https://kind.sigs.k8s.io/) con todo lo necesario: ArgoCD, Vault, External Secrets, kgateway, SonarQube y Kyverno. Todo accesible vía HTTPS con certificados autofirmados.

```
./autokube up
```

## Arquitectura

```
Host (Mac/Linux/WSL2)
  ├── ./autokube up/down/destroy/status
  ├── config: autokube.yaml
  ├── data/ (persistente, montado en Kind via extraMounts)
  │
  └── Kind Cluster (single-node)
        ├── kgateway (NodePort 31080/31443 → host 80/443)
        │     └── HTTPRoutes: *.127.0.0.1.nip.io → servicios internos
        ├── ArgoCD (gestiona componentes via GitOps o instalación imperativa)
        ├── Vault (modo producción, Raft storage, auto-unseal)
        ├── External Secrets Operator (conectado a Vault)
        ├── SonarQube Community (con PostgreSQL embebido)
        └── Kyverno (policy engine, políticas en modo Audit)
```

## Requisitos previos

- **Docker** (Docker Desktop en Mac/Windows, dockerd en Linux) — debe estar ejecutándose
- **macOS** (Intel/Apple Silicon), **Linux** (amd64/arm64) o **Windows** (vía WSL2)
- Puertos **80** y **443** disponibles en el host (configurables)

El resto de dependencias se instalan automáticamente:

| Herramienta | Versión | Instalación Mac | Instalación Linux |
|---|---|---|---|
| kind | v0.31.0 | `brew install` | Binario en `~/.local/bin` |
| kubectl | latest stable | `brew install` | Binario en `~/.local/bin` |
| helm | latest stable | `brew install` | Script oficial |
| yq | v4.52.x | `brew install` | Binario en `~/.local/bin` |
| jq | 1.7+ | `brew install` | Binario en `~/.local/bin` |
| vault CLI | 1.19+ | `brew install hashicorp/tap/vault` | Zip desde releases |
| argocd CLI | v3.3+ | `brew install` | Binario en `~/.local/bin` |

## Inicio rápido

```bash
# 1. Clonar el repositorio
git clone <repo-url> && cd autokube

# 2. (Opcional) Personalizar configuración
cp autokube.yaml.example autokube.yaml
# Editar autokube.yaml según necesidades

# 3. Levantar todo
./autokube up

# 4. Acceder a los servicios
#    https://argocd.127.0.0.1.nip.io
#    https://vault.127.0.0.1.nip.io
#    https://sonarqube.127.0.0.1.nip.io
```

## Comandos

| Comando | Descripción |
|---|---|
| `./autokube up` | Crea/arranca el cluster y despliega todos los componentes |
| `./autokube down` | Para el cluster preservando todos los datos |
| `./autokube destroy` | Elimina el cluster (pregunta si borrar datos) |
| `./autokube destroy --keep-data` | Elimina el cluster pero preserva datos persistentes |
| `./autokube status` | Muestra estado del cluster, componentes, URLs y credenciales |
| `./autokube trust-ca` | Instala la CA autofirmada en el trust store del sistema |
| `./autokube help` | Muestra ayuda |

### Ciclo de vida

```
./autokube up       →  Cluster running, servicios accesibles
./autokube down     →  Cluster parado, datos intactos
./autokube up       →  Cluster reanudado, todo como estaba
./autokube destroy  →  Cluster eliminado
./autokube up       →  Cluster recreado desde cero (con --keep-data, los datos de Vault persisten)
```

## Configuración

Copia `autokube.yaml.example` a `autokube.yaml` y personaliza. Si no existe, se usan los valores por defecto.

```yaml
cluster:
  name: autokube                    # Nombre del cluster Kind

network:
  baseDomain: "127.0.0.1.nip.io"   # Dominio base (usa nip.io para DNS automático)
  httpPort: 80                      # Puerto HTTP en el host
  httpsPort: 443                    # Puerto HTTPS en el host

ssl:
  enabled: true                     # Generar certificados autofirmados
  trustCA: false                    # Instalar CA en trust store del sistema (requiere sudo)

gitops:
  enabled: true                     # Usar ArgoCD para gestionar componentes desde repo remoto
  repoURL: ""                       # URL del repo Git (REQUERIDO si gitops.enabled)
  targetRevision: "main"            # Branch o tag
  path: "gitops/apps"              # Path al Helm chart app-of-apps en el repo

components:                         # Habilitar/deshabilitar componentes individualmente
  argocd:
    enabled: true
  vault:
    enabled: true
  eso:
    enabled: true
  kgateway:
    enabled: true
  sonarqube:
    enabled: true
  kyverno:
    enabled: true

persistence:
  dataDir: "./data"                 # Directorio de datos persistentes
```

### Modos de instalación

| Modo | Condición | Descripción |
|---|---|---|
| **GitOps remoto** | `gitops.enabled: true` + `gitops.repoURL` configurado | ArgoCD gestiona todos los componentes desde el repo Git remoto mediante app-of-apps |
| **ArgoCD local** | `argocd.enabled: true` + `gitops.repoURL` vacío | ArgoCD gestiona componentes con Applications inline (valores desde ficheros locales) |
| **Imperativo** | `argocd.enabled: false` | Cada componente se instala directamente con Helm |

En todos los modos, ArgoCD se instala siempre de forma imperativa (no puede gestionarse a sí mismo en bootstrap).

### Autenticación para repositorios privados

Si `gitops.repoURL` apunta a un repo privado HTTPS, autokube extrae las credenciales automáticamente de `~/.git-credentials`. También acepta variables de entorno:

```bash
export AUTOKUBE_GITOPS_USERNAME="tu-usuario"
export AUTOKUBE_GITOPS_TOKEN="ghp_xxxxx"
./autokube up
```

## Componentes

### Versiones

| Componente | Chart | Versión | Repositorio |
|---|---|---|---|
| ArgoCD | `argo/argo-cd` | 9.4.1 | `https://argoproj.github.io/argo-helm` |
| Vault | `hashicorp/vault` | 0.32.0 | `https://helm.releases.hashicorp.com` |
| External Secrets | `external-secrets/external-secrets` | 0.15.1 | `https://charts.external-secrets.io` |
| kgateway | `kgateway` (OCI) | v2.2.0 | `oci://cr.kgateway.dev/kgateway-dev/charts` |
| SonarQube | `sonarqube/sonarqube` | 2026.1.0 | `https://SonarSource.github.io/helm-chart-sonarqube` |
| Kyverno | `kyverno/kyverno` | 3.7.0 | `https://kyverno.github.io/kyverno/` |
| Gateway API CRDs | — | v1.4.1 | kubernetes-sigs/gateway-api |

### kgateway (Solo.io)

Gateway API nativo que actúa como ingress controller. Usa un Service tipo NodePort con puertos fijos mapeados al host a través de Kind, lo que funciona tanto en Mac (Docker Desktop) como en Linux sin necesidad de MetalLB.

| Puerto | Flujo |
|---|---|
| Host 80 → Kind node 31080 → kgateway 8080 | HTTP |
| Host 443 → Kind node 31443 → kgateway 8443 | HTTPS (TLS termination) |

### Vault (HashiCorp)

Desplegado en modo producción standalone con almacenamiento Raft. Los datos persisten en el host mediante extraMounts de Kind (`data/vault/raft` → `/vault/data`).

- **Init**: Primera ejecución genera 1 unseal key + root token, guardados en `data/vault/init.json`
- **Unseal**: Automático en cada `./autokube up` posterior
- **Configuración automática**: KV v2, Kubernetes auth, policy y role para ESO

### External Secrets Operator

Conectado automáticamente a Vault mediante un `ClusterSecretStore`. Permite crear `ExternalSecret` resources que leen secretos de Vault y los sincronizan como Kubernetes Secrets.

```yaml
# Ejemplo de uso (una vez configurado)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: mi-secreto
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: ClusterSecretStore
  target:
    name: mi-secreto-k8s
  data:
    - secretKey: password
      remoteRef:
        key: kv/data/mi-app
        property: password
```

### SonarQube Community

Análisis estático de código. Incluye PostgreSQL embebido.

- Credenciales por defecto: `admin` / `admin`
- Requiere mínimo 2GB RAM para SonarQube + 512MB para PostgreSQL
- `vm.max_map_count` se configura automáticamente en el nodo Kind

### Kyverno

Policy engine para Kubernetes. Se despliega con dos políticas en **modo Audit** (solo avisan, no bloquean):

| Política | Descripción |
|---|---|
| `disallow-latest-tag` | Avisa si una imagen usa el tag `:latest` |
| `require-resources` | Avisa si un container no tiene `resources.requests` y `resources.limits` |

### ArgoCD

Plataforma GitOps para despliegue declarativo. Se instala siempre de forma imperativa (no puede gestionarse a sí mismo en bootstrap).

- Modo insecure (TLS terminado en kgateway)
- Password de admin mostrado en `./autokube status` y en `./autokube up`

## Networking

### URLs de acceso

| Servicio | URL |
|---|---|
| ArgoCD | `https://argocd.127.0.0.1.nip.io` |
| Vault | `https://vault.127.0.0.1.nip.io` |
| SonarQube | `https://sonarqube.127.0.0.1.nip.io` |

### Certificados SSL

Se genera una CA local y un certificado wildcard para `*.127.0.0.1.nip.io` (validez: 10 años). Los certificados se guardan en `data/ssl/`.

Para evitar avisos del navegador, instala la CA en el trust store del sistema:

```bash
./autokube trust-ca    # Requiere sudo
```

### Cross-namespace routing

kgateway crea HTTPRoutes en su namespace (`kgateway-system`) que apuntan a Services en otros namespaces. Para permitirlo, se crean `ReferenceGrant` resources en cada namespace destino (argocd, vault, sonarqube).

## Persistencia

Los datos persisten gracias a los `extraMounts` de Kind, que mapean directorios del host al nodo del cluster:

| Datos | Host | Contenedor Kind | Descripción |
|---|---|---|---|
| Vault Raft | `data/vault/raft` | `/vault/data` | Backend de almacenamiento Raft |
| SonarQube | `data/sonarqube` | `/sonarqube/data` | BD PostgreSQL + datos SonarQube |
| PVs generales | `data/kind/local-path` | `/var/local-path-provisioner` | PVs dinámicos (ArgoCD Redis, etc.) |
| Vault keys | `data/vault/init.json` | — (solo host) | Unseal keys + root token |
| Certificados | `data/ssl/` | — (solo host) | CA + certificado wildcard |

- `docker stop` / `docker start` (vía `down`/`up`) preserva todo el estado.
- `kind delete` + recrear (vía `destroy --keep-data` + `up`) también preserva datos gracias a los mounts del host.

## GitOps

### Estructura del directorio gitops/

El directorio `gitops/` contiene toda la configuración que ArgoCD usa en modo GitOps remoto. Debe existir en el repositorio Git configurado en `gitops.repoURL`.

```
gitops/
├── apps/                          # Helm chart app-of-apps (ArgoCD lo renderiza)
│   ├── Chart.yaml                 # Metadatos del chart
│   ├── values.yaml                # Valores por defecto (repoURL, targetRevision)
│   └── templates/                 # Application CRs como templates Helm
│       ├── vault.yaml             # Multi-source: Helm chart + values del repo
│       ├── kgateway.yaml          # Multi-source: OCI chart + values del repo
│       ├── eso.yaml               # Multi-source: Helm chart + values del repo
│       ├── sonarqube.yaml         # Multi-source: Helm chart + values del repo
│       ├── kyverno.yaml           # Multi-source: Helm chart + values del repo
│       ├── eso-config.yaml        # Single-source: manifests del repo
│       ├── kyverno-policies.yaml  # Single-source: manifests del repo
│       └── routes.yaml            # Single-source: manifests del repo
└── components/                    # Configuración de cada componente
    ├── vault/values.yaml          # Helm values (sin prefijo de chart)
    ├── kgateway/values.yaml
    ├── eso/values.yaml
    ├── sonarqube/values.yaml
    ├── kyverno/values.yaml
    ├── eso-config/                # ClusterSecretStore manifest
    │   └── cluster-secret-store.yaml
    ├── kyverno-policies/          # ClusterPolicy manifests
    │   ├── disallow-latest-tag.yaml
    │   └── require-resources.yaml
    └── routes/                    # Gateway, HTTPRoutes, ReferenceGrants
        ├── gateway.yaml
        ├── httproute-argocd.yaml
        ├── httproute-vault.yaml
        ├── httproute-sonarqube.yaml
        ├── referencegrant-argocd.yaml
        ├── referencegrant-vault.yaml
        └── referencegrant-sonarqube.yaml
```

Las Applications de Helm charts (vault, kgateway, eso, sonarqube, kyverno) usan **multi-source**: el chart se descarga del repositorio oficial de Helm y los values se leen del repo Git (via referencia `$values`). No hay Chart.yaml wrappers en los directorios de componentes.

### Sync Waves

ArgoCD despliega los componentes en orden mediante sync waves:

| Wave | Componente | Razón |
|---|---|---|
| -3 | kgateway | Infraestructura de red primero |
| -3 | Vault | Debe existir antes de que ESO conecte |
| -2 | Kyverno | Policy engine independiente |
| -2 | SonarQube | Independiente, puede tardar en arrancar |
| -1 | External Secrets | CRDs y operator antes del ClusterSecretStore |
| 0 | ESO Config | Depende de Vault + ESO CRDs |
| 0 | Kyverno Policies | Depende de Kyverno CRDs |
| 1 | Routes | Depende de kgateway ready |

### Post-instalación

En modo GitOps, ArgoCD gestiona los componentes pero hay acciones que siempre se ejecutan imperativamente:

- **Vault init/unseal**: Inicialización y desellado de Vault (no puede ser declarativo)
- **Vault configuración**: KV v2, Kubernetes auth, policy y role para ESO
- **Gateway NodePorts**: Parcheo del Service creado por el Gateway controller a NodePort 31080/31443

## Estructura del proyecto

```
autokube/
├── autokube                        # CLI principal (bash)
├── autokube.yaml.example           # Config de ejemplo
├── lib/
│   ├── common.sh                   # Logging, colores, retry, helpers
│   ├── config.sh                   # Parsing YAML con yq
│   ├── deps.sh                     # Detección/instalación dependencias
│   ├── kind.sh                     # Ciclo de vida cluster Kind
│   ├── ssl.sh                      # Generación CA + wildcard cert
│   ├── helm.sh                     # Helpers Helm
│   ├── argocd.sh                   # Bootstrap ArgoCD + GitOps + Applications
│   ├── vault.sh                    # Install, init, unseal, configurar
│   ├── eso.sh                      # Install ESO + ClusterSecretStore
│   ├── kgateway.sh                 # Install kgateway + Gateway + HTTPRoutes
│   ├── sonarqube.sh                # Install SonarQube Community
│   ├── kyverno.sh                  # Install Kyverno + políticas
│   └── networking.sh               # TLS secrets, ReferenceGrants
├── manifests/                      # Templates y values para instalación imperativa
│   ├── kind-cluster.yaml.tpl
│   ├── argocd/
│   │   ├── values.yaml
│   │   └── app-of-apps.yaml.tpl
│   ├── vault/
│   ├── eso/
│   ├── kgateway/
│   │   └── httproutes/
│   ├── sonarqube/
│   └── kyverno/
│       └── policies/
├── gitops/                         # Contenido para repo GitOps remoto
│   ├── apps/                       # Helm chart app-of-apps
│   └── components/                 # Values y manifests por componente
├── data/                           # Datos persistentes (gitignored)
└── .gitignore
```

## Windows (WSL2)

Autokube funciona en Windows a través de WSL2, que proporciona un entorno Linux completo.

### Requisitos

1. **WSL2** instalado y configurado (no WSL1)
2. **Docker Desktop** con el backend WSL2 activado (Settings → General → Use the WSL 2 based engine), y la integración habilitada para tu distribución (Settings → Resources → WSL Integration)

### Instalación

```bash
# Dentro de WSL (importante: clonar en el filesystem de WSL, NO en /mnt/c/)
git clone <repo-url> ~/projects/autokube
cd ~/projects/autokube
cp autokube.yaml.example autokube.yaml
./autokube up
```

> **Rendimiento**: Clona siempre dentro del filesystem de WSL (`~/`, `/home/...`). Usar `/mnt/c/` (el disco de Windows montado) es extremadamente lento para operaciones de I/O.

### Acceso desde el navegador de Windows

Las URLs funcionan directamente desde el navegador de Windows porque WSL2 reenvía `localhost` automáticamente:

- `https://argocd.127.0.0.1.nip.io`
- `https://vault.127.0.0.1.nip.io`
- `https://sonarqube.127.0.0.1.nip.io`

### Certificados SSL en Windows

El comando `./autokube trust-ca` instala la CA solo en el trust store de Linux (WSL). Para evitar avisos de certificado en el navegador de Windows, importa la CA manualmente:

1. Copia el certificado al disco de Windows:
   ```bash
   cp data/ssl/ca.crt /mnt/c/Users/<tu-usuario>/Desktop/autokube-ca.crt
   ```
2. En Windows, haz doble clic en `autokube-ca.crt` → **Instalar certificado**
3. Selecciona **Máquina local** → **Colocar todos los certificados en el siguiente almacén** → **Entidades de certificación raíz de confianza**
4. Reinicia el navegador

### Diferencias con Mac/Linux nativo

| Aspecto | Mac/Linux | WSL2 |
|---|---|---|
| Docker | Docker Desktop / dockerd | Docker Desktop con backend WSL2 |
| Dependencias | brew (Mac) / binarios (Linux) | Binarios en `~/.local/bin` (igual que Linux) |
| Trust CA | Keychain (Mac) / update-ca-trust (Linux) | Solo Linux dentro de WSL; en Windows, importar manualmente |
| Puertos | Directos en el host | WSL2 reenvía localhost a Windows automáticamente |
| Rendimiento I/O | Nativo | Nativo en filesystem WSL; muy lento en `/mnt/c/` |

## Troubleshooting

### Puerto 80/443 ocupado

Cambia los puertos en `autokube.yaml`:

```yaml
network:
  httpPort: 8080
  httpsPort: 8443
```

Las URLs pasarán a ser `https://argocd.127.0.0.1.nip.io:8443`, etc.

### Docker no está ejecutándose

```
[ERROR] Docker no está ejecutándose. Arranca Docker Desktop o el servicio dockerd.
```

Arranca Docker Desktop (Mac) o `sudo systemctl start docker` (Linux).

### SonarQube no arranca

SonarQube necesita `vm.max_map_count >= 524288`. Autokube lo configura automáticamente dentro del nodo Kind, pero si falla:

```bash
docker exec autokube-control-plane sysctl -w vm.max_map_count=524288
```

### Vault sealed tras reinicio

`./autokube up` hace unseal automático usando las keys guardadas en `data/vault/init.json`. Si el unseal falla, puedes hacerlo manualmente:

```bash
export VAULT_ADDR=https://vault.127.0.0.1.nip.io
vault operator unseal $(jq -r '.unseal_keys_b64[0]' data/vault/init.json)
```

### Certificados no confiables en el navegador

```bash
./autokube trust-ca
```

Esto instala la CA en el trust store del sistema. En Mac usa el Keychain; en Linux, `update-ca-certificates` o `update-ca-trust`.

### Recrear cluster con datos existentes

```bash
./autokube destroy --keep-data
./autokube up
# Vault se inicializa con los datos existentes, solo necesita unseal
```

### WSL2: Docker no accesible

Si `docker info` falla dentro de WSL, asegúrate de que Docker Desktop está ejecutándose en Windows y que la integración WSL está habilitada para tu distribución en Settings → Resources → WSL Integration.

### ArgoCD apps en OutOfSync

Algunas apps (kyverno, routes) pueden mostrar OutOfSync en ArgoCD por diffs en CRDs grandes o campos defaulteados por controllers. Si las apps muestran **Healthy**, es normal y no requiere acción.
