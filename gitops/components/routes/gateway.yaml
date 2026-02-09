apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
  namespace: kgateway-system
  annotations:
    gateway.kgateway.dev/parameters: kgateway-params
spec:
  gatewayClassName: kgateway
  listeners:
    - name: http
      protocol: HTTP
      port: 8080
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 8443
      tls:
        mode: Terminate
        certificateRefs:
          - name: wildcard-tls
            namespace: kgateway-system
      allowedRoutes:
        namespaces:
          from: All
