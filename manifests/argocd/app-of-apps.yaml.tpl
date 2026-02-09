apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: __GITOPS_REPO_URL__
    targetRevision: __GITOPS_TARGET_REVISION__
    path: __GITOPS_PATH__
    helm:
      parameters:
        - name: global.repoURL
          value: __GITOPS_REPO_URL__
        - name: global.targetRevision
          value: __GITOPS_TARGET_REVISION__
        - name: global.clusterType
          value: __CLUSTER_TYPE__
__ARC_REPOS_PARAMS__
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
