# Autokube

Instalador de entorno Kubernetes local para desarrollo. Un solo comando despliega un cluster [Kind](https://kind.sigs.k8s.io/) con todo lo necesario: ArgoCD, Vault, External Secrets, kgateway, SonarQube y Kyverno. Todo accesible vía HTTPS con certificados autofirmados.

```
./autokube up
```

## Arquitectura

```
Host (Mac/Linux)
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

- **Docker** (Docker Desktop en Mac, dockerd en Linux) — debe estar ejecutándose
- **macOS** (Intel/Apple Silicon) o **Linux** (amd64/arm64)
- Puertos **80** y **443** disponibles en el host (configurables)

El resto de dependencias se instalan automáticamente:

| Herramienta | Versión | Instalación Mac | Instalación Linux |
|---|---|---|---|
| kind | v0.31.0 | `brew install` | Binario en `~/.local/bin` |
| kubectl | latest stable | `brew install` | Binario en `~/.local/bin` |
| helm | latest stable | `brew install` | Script oficial |
| yq | v4.52.1 | `brew install` | Binario en `~/.local/bin` |
| jq | 1.8 | `brew install` | Binario en `~/.local/bin` |
| vault CLI | 1.19.2 | `brew install hashicorp/tap/vault` | Zip desde releases |
| argocd CLI | v2.14.11 | `brew install` | Binario en `~/.local/bin` |

## Inicio rápido

```bash
# 1. Clonar el repositorio
git clone <repo-url> && cd autokube

# 2. (Opcional) Personalizar configuración
cp autokube.yaml.example autokube.yaml

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
  enabled: true                     # Usar ArgoCD para gestionar componentes
  repoURL: ""                       # URL del repo Git (REQUERIDO si gitops.enabled)
  targetRevision: "main"            # Branch o tag
  path: "apps"                      # Path a las Application CRs en el repo

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

**Modo imperativo** (por defecto si `gitops.repoURL` está vacío): cada componente se instala directamente con Helm.

**Modo GitOps** (cuando `gitops.enabled: true` y `gitops.repoURL` configurado): ArgoCD se instala imperativamente y gestiona el resto de componentes desde el repositorio Git remoto mediante app-of-apps.

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

Desplegado en modo producción standalone con almacenamiento Raft. Los datos persisten en el host mediante extraMounts de Kind.

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
- Password de admin mostrado en `./autokube status`

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

### Estructura del repositorio remoto

El directorio `gitops/` contiene la estructura que debe existir en el repositorio Git remoto configurado en `gitops.repoURL`:

```
gitops/
├── apps/                          # ArgoCD Application CRs (app-of-apps)
│   ├── kgateway.yaml
│   ├── vault.yaml
│   ├── eso.yaml
│   ├── eso-config.yaml
│   ├── sonarqube.yaml
│   ├── kyverno.yaml
│   └── routes.yaml
└── components/                    # Configuración de cada componente
    ├── vault/                     # Chart.yaml + values.yaml
    ├── kgateway/                  # Chart.yaml + values.yaml
    ├── eso/                       # Chart.yaml + values.yaml
    ├── eso-config/                # ClusterSecretStore manifest
    ├── sonarqube/                 # Chart.yaml + values.yaml
    ├── kyverno/                   # Chart.yaml + values.yaml
    ├── kyverno-policies/          # ClusterPolicy manifests
    └── routes/                    # Gateway, HTTPRoutes, ReferenceGrants
```

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
| 1 | Routes | Depende de kgateway ready |

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
│   ├── argocd.sh                   # Bootstrap ArgoCD + GitOps
│   ├── vault.sh                    # Install, init, unseal, configurar
│   ├── eso.sh                      # Install ESO + ClusterSecretStore
│   ├── kgateway.sh                 # Install kgateway + Gateway + HTTPRoutes
│   ├── sonarqube.sh                # Install SonarQube Community
│   ├── kyverno.sh                  # Install Kyverno + políticas
│   └── networking.sh               # TLS secrets, ReferenceGrants
├── manifests/                      # Templates y values para instalación imperativa
│   ├── kind-cluster.yaml.tpl
│   ├── argocd/
│   ├── vault/
│   ├── eso/
│   ├── kgateway/
│   │   └── httproutes/
│   ├── sonarqube/
│   └── kyverno/
│       └── policies/
├── gitops/                         # Contenido para repo GitOps remoto
│   ├── apps/
│   └── components/
├── data/                           # Datos persistentes (gitignored)
└── .gitignore
```

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
