apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: vault-route
  namespace: kgateway-system
spec:
  parentRefs:
    - name: main-gateway
      namespace: kgateway-system
      sectionName: https
  hostnames:
    - "vault.__BASE_DOMAIN__"
  rules:
    - backendRefs:
        - name: vault
          namespace: vault
          port: 8200
