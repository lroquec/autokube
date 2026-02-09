kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: __CLUSTER_NAME__
nodes:
  - role: control-plane
    extraPortMappings:
      - containerPort: 31080
        hostPort: __HTTP_PORT__
        protocol: TCP
      - containerPort: 31443
        hostPort: __HTTPS_PORT__
        protocol: TCP
    extraMounts:
      - hostPath: __DATA_DIR__/vault/raft
        containerPath: /vault/data
      - hostPath: __DATA_DIR__/sonarqube
        containerPath: /sonarqube/data
      - hostPath: __DATA_DIR__/kind/local-path
        containerPath: /var/local-path-provisioner
