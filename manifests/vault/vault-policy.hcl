# Policy para External Secrets Operator
# Permite lectura de secretos en kv/data/*
path "kv/data/*" {
  capabilities = ["read"]
}

path "kv/metadata/*" {
  capabilities = ["read", "list"]
}
