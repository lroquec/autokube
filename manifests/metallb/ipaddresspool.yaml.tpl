apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: autokube-pool
  namespace: metallb-system
spec:
  addresses:
    - __ADDRESS_RANGE__
