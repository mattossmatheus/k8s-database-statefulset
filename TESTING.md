# 🧪 Guia de Testes e Verificação

Este documento contém todos os comandos para testar e verificar o funcionamento dos deployments de banco de dados.

## 🐘 PostgreSQL - Testes de Replicação

### 1. Deploy e Verificação Inicial
```bash
# Deploy
kubectl apply -f postgres.yaml

# Aguardar pods subirem
kubectl wait --for=condition=ready pod -l app=postgres --timeout=300s

# Verificar status
kubectl get pods -l app=postgres
kubectl get svc -l app=postgres
```

### 2. Verificar Configuração de Replicação
```bash
# Status de replicação no master
kubectl exec postgres-0 -- psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"

# Verificar se slaves estão em recovery mode
kubectl exec postgres-1 -- psql -U postgres -c "SELECT pg_is_in_recovery();"
kubectl exec postgres-2 -- psql -U postgres -c "SELECT pg_is_in_recovery();"

# Verificar configuração do wal receiver nos slaves
kubectl exec postgres-1 -- psql -U postgres -c "SELECT status, received_lsn FROM pg_stat_wal_receiver;"
```

### 3. Teste de Replicação de Dados
```bash
# Criar banco e tabela no master
kubectl exec postgres-0 -- psql -U postgres -c "
CREATE DATABASE testdb;
\c testdb;
CREATE TABLE users (id SERIAL PRIMARY KEY, name VARCHAR(100), created_at TIMESTAMP DEFAULT NOW());
INSERT INTO users (name) VALUES ('Usuario Master'), ('Teste Replicacao');
"

# Verificar dados nos slaves (aguardar alguns segundos)
sleep 10

kubectl exec postgres-1 -- psql -U postgres -d testdb -c "SELECT * FROM users;"
kubectl exec postgres-2 -- psql -U postgres -d testdb -c "SELECT * FROM users;"
```

### 4. Teste de Failover Manual
```bash
# Simular falha do master (deletar pod)
kubectl delete pod postgres-0

# Aguardar restart automático
kubectl wait --for=condition=ready pod postgres-0 --timeout=300s

# Verificar se replicação continua funcionando
kubectl exec postgres-0 -- psql -U postgres -d testdb -c "INSERT INTO users (name) VALUES ('Pos Failover');"
sleep 5
kubectl exec postgres-1 -- psql -U postgres -d testdb -c "SELECT * FROM users WHERE name = 'Pos Failover';"
```

---

## 🍃 MongoDB - Testes de Replica Set

### 1. Deploy e Verificação Inicial
```bash
# Deploy completo
kubectl apply -f mongodb.yaml
kubectl apply -f mongodb-init-job.yaml

# OU usar script
./deploy-mongodb.sh

# Aguardar pods subirem
kubectl wait --for=condition=ready pod -l app=mongodb --timeout=300s

# Verificar status
kubectl get pods -l app=mongodb
kubectl get svc -l app=mongodb
kubectl get jobs
```

### 2. Verificar Configuração do Replica Set
```bash
# Status completo do replica set
kubectl exec mongodb-0 -- mongosh --eval "rs.status()"

# Status resumido (apenas estados)
kubectl exec mongodb-0 -- mongosh --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

# Configuração do replica set
kubectl exec mongodb-0 -- mongosh --eval "rs.conf()"

# Verificar se secondary pode ler
kubectl exec mongodb-1 -- mongosh --eval "db.getMongo().setReadPref('secondary'); db.runCommand('ping')"
```

### 3. Teste de Replicação de Dados
```bash
# Inserir dados no primary
kubectl exec mongodb-0 -- mongosh --eval "
use testdb;
db.users.insertMany([
  {name: 'Usuario Primary', role: 'admin', created: new Date()},
  {name: 'Teste Replicacao', role: 'user', created: new Date()}
]);
db.users.find();
"

# Verificar replicação nos secondaries (aguardar alguns segundos)
sleep 10

kubectl exec mongodb-1 -- mongosh testdb --eval "
db.getMongo().setReadPref('secondary');
db.users.find();
"

kubectl exec mongodb-2 -- mongosh testdb --eval "
db.getMongo().setReadPref('secondary');
db.users.find();
"
```

### 4. Teste de Failover Automático
```bash
# Simular falha do primary (deletar pod)
kubectl delete pod mongodb-0

# Aguardar nova eleição (pode demorar até 30 segundos)
sleep 30

# Verificar novo primary
kubectl exec mongodb-1 -- mongosh --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

# Inserir dados no novo primary
NEW_PRIMARY=$(kubectl exec mongodb-1 -- mongosh --quiet --eval "rs.status().members.find(m => m.stateStr === 'PRIMARY').name.split('.')[0]" 2>/dev/null || echo "mongodb-1")
kubectl exec $NEW_PRIMARY -- mongosh testdb --eval "
db.users.insertOne({name: 'Pos Failover', role: 'test', created: new Date()});
"

# Aguardar mongodb-0 voltar e verificar sincronização
kubectl wait --for=condition=ready pod mongodb-0 --timeout=300s
sleep 30
kubectl exec mongodb-0 -- mongosh testdb --eval "
db.getMongo().setReadPref('secondary');
db.users.find({name: 'Pos Failover'});
"
```

### 5. Teste de Carga Simples
```bash
# Inserir muitos documentos no primary
kubectl exec mongodb-0 -- mongosh testdb --eval "
for(let i = 0; i < 1000; i++) {
  db.loadtest.insertOne({
    index: i,
    data: 'Load test data ' + i,
    timestamp: new Date(),
    random: Math.random()
  });
}
print('Inserted 1000 documents');
"

# Verificar replicação nos secondaries
kubectl exec mongodb-1 -- mongosh testdb --eval "
db.getMongo().setReadPref('secondary');
print('Count on secondary:', db.loadtest.countDocuments());
"
```

---

## 🔧 Comandos de Troubleshooting

### PostgreSQL Debug
```bash
# Logs detalhados
kubectl logs postgres-0 --tail=100
kubectl logs postgres-1 --tail=100

# Verificar configuração do postgresql.conf
kubectl exec postgres-0 -- cat /var/lib/postgresql/data/postgresql.conf | grep -E "(wal_level|max_wal_senders|wal_keep_size)"

# Verificar pg_hba.conf
kubectl exec postgres-0 -- cat /var/lib/postgresql/data/pg_hba.conf

# Verificar recovery.conf nos slaves
kubectl exec postgres-1 -- cat /var/lib/postgresql/data/postgresql.auto.conf

# Status de conexões
kubectl exec postgres-0 -- psql -U postgres -c "SELECT * FROM pg_stat_activity WHERE application_name LIKE 'walreceiver';"
```

### MongoDB Debug
```bash
# Logs detalhados
kubectl logs mongodb-0 --tail=100
kubectl logs job/mongodb-init-replica

# Configuração detalhada do replica set
kubectl exec mongodb-0 -- mongosh --eval "JSON.stringify(rs.conf(), null, 2)"

# Status de rede entre os pods
kubectl exec mongodb-0 -- mongosh --eval "rs.status().members.forEach(m => {
  print(m.name + ' - Health: ' + m.health + ' - State: ' + m.stateStr + ' - Ping: ' + (m.pingMs || 'N/A') + 'ms');
})"

# Verificar oplog (deve estar sincronizado)
kubectl exec mongodb-0 -- mongosh --eval "db.printReplicationInfo()"
kubectl exec mongodb-1 -- mongosh --eval "db.getMongo().setReadPref('secondary'); db.printSlaveReplicationInfo()"

# Forçar reconfiguração se necessário
kubectl exec mongodb-0 -- mongosh --eval "
rs.reconfig({
  _id: 'rs0',
  members: [
    {_id: 0, host: 'mongodb-0.mongodb-headless:27017', priority: 2},
    {_id: 1, host: 'mongodb-1.mongodb-headless:27017'},
    {_id: 2, host: 'mongodb-2.mongodb-headless:27017'}
  ]
}, {force: true})
"
```

---

## 📊 Scripts de Monitoramento

### Script de Verificação PostgreSQL
```bash
#!/bin/bash
echo "=== PostgreSQL Cluster Status ==="
echo "Pods:"
kubectl get pods -l app=postgres
echo -e "\nReplication Status:"
kubectl exec postgres-0 -- psql -U postgres -c "SELECT client_addr, state, sync_state FROM pg_stat_replication;"
echo -e "\nSlave Status:"
kubectl exec postgres-1 -- psql -U postgres -c "SELECT pg_is_in_recovery();"
kubectl exec postgres-2 -- psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### Script de Verificação MongoDB
```bash
#!/bin/bash
echo "=== MongoDB Replica Set Status ==="
echo "Pods:"
kubectl get pods -l app=mongodb
echo -e "\nReplica Set Status:"
kubectl exec mongodb-0 -- mongosh --quiet --eval "
rs.status().members.forEach(function(member) {
  print(member.name + ' - ' + member.stateStr + ' (Health: ' + member.health + ')');
});
"
```

### Script de Limpeza
```bash
#!/bin/bash
echo "Removendo todos os recursos..."
kubectl delete -f postgres.yaml 2>/dev/null || true
kubectl delete -f mongodb.yaml 2>/dev/null || true
kubectl delete job mongodb-init-replica 2>/dev/null || true
echo "Aguardando pods terminarem..."
kubectl wait --for=delete pod -l app=postgres --timeout=120s 2>/dev/null || true
kubectl wait --for=delete pod -l app=mongodb --timeout=120s 2>/dev/null || true
echo "Limpeza concluída!"
```

---

## 🎯 Benchmarks e Performance

### PostgreSQL - Teste de Performance
```bash
# Instalar pgbench no pod
kubectl exec postgres-0 -- psql -U postgres -c "CREATE DATABASE benchdb;"

# Inicializar pgbench
kubectl exec postgres-0 -- pgbench -i -s 10 -U postgres benchdb

# Executar benchmark
kubectl exec postgres-0 -- pgbench -c 10 -j 2 -t 1000 -U postgres benchdb
```

### MongoDB - Teste de Performance
```bash
# Inserir dados em lote
kubectl exec mongodb-0 -- mongosh perfdb --eval "
const bulk = db.perftest.initializeUnorderedBulkOp();
for(let i = 0; i < 10000; i++) {
  bulk.insert({
    _id: i,
    data: 'Performance test data ' + i,
    timestamp: new Date(),
    random: Math.random() * 1000
  });
}
bulk.execute();
print('Inserted 10000 documents for performance test');
"

# Teste de leitura
kubectl exec mongodb-1 -- mongosh perfdb --eval "
db.getMongo().setReadPref('secondary');
const startTime = new Date();
const count = db.perftest.countDocuments();
const endTime = new Date();
print('Count: ' + count + ', Time: ' + (endTime - startTime) + 'ms');
"
```

---

**💡 Dica**: Salve estes comandos em scripts para facilitar os testes repetitivos!
