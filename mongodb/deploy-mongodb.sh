#!/bin/bash
echo "🚀 Iniciando deploy MongoDB Master-Slave..."

# Aplicar StatefulSet
kubectl apply -f mongodb.yaml

echo "⏳ Aguardando pods subirem..."
kubectl wait --for=condition=Ready pod/mongodb-0 --timeout=300s

# Aplicar Job de configuração
kubectl apply -f mongodb-init-job.yaml

echo "⏳ Aguardando configuração do Replica Set..."
kubectl wait --for=condition=Complete job/mongodb-init-replica --timeout=120s

echo "✅ MongoDB Master-Slave configurado automaticamente!"
echo ""
echo "📊 Status final:"
kubectl exec mongodb-0 -- mongosh --eval "rs.status()" | grep -E "(stateStr|name.*mongodb)"