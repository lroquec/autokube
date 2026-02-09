apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: sonarqube-route
  namespace: kgateway-system
spec:
  parentRefs:
    - name: main-gateway
      namespace: kgateway-system
      sectionName: https
  hostnames:
    - "sonarqube.__BASE_DOMAIN__"
  rules:
    - backendRefs:
        - name: sonarqube-sonarqube
          namespace: sonarqube
          port: 9000
