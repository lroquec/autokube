apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: argocd-route
  namespace: kgateway-system
spec:
  parentRefs:
    - name: main-gateway
      namespace: kgateway-system
      sectionName: https
  hostnames:
    - "argocd.__BASE_DOMAIN__"
  rules:
    - backendRefs:
        - name: argocd-server
          namespace: argocd
          port: 80
