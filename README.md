# 🚀 Kubernetes StatefulSet Database Deployments

Deployments completos de bancos de dados com **replicação read/write** usando **StatefulSet** em clusters **K3s**, com configuração automática de replicação.

## 📋 Bancos de Dados Disponíveis

| Banco | Status | Automação | Arquitetura |
|-------|--------|-----------|-------------|
| PostgreSQL 15 | ✅ Pronto | 100% Automático | 1 Primary + 2 Replicas (Read/Write) |
| MongoDB 7.0 | ✅ Pronto | Automático* | 1 Primary + 2 Secondary (Replica Set) |
| MySQL 8.0 | ✅ Pronto | 100% Automático | 1 Primary + 2 Replicas (Read/Write) |

## 🐘 PostgreSQL Primary-Replica

### Características
- **Versão**: PostgreSQL 15
- **Arquitetura**: 1 Primary + 2 Replicas (Read/Write)
- **Replicação**: Streaming Replication (automática)
- **Storage**: Local-path (K3s)
- **Automação**: 100% automática

### Deploy
```bash
kubectl apply -f postgres.yaml
```

### Estrutura do Cluster
```
postgres-0 (PRIMARY)    ← Escritas (Write)
    ↓
postgres-1 (REPLICA)    ← Leituras (Read)
postgres-2 (REPLICA)    ← Leituras (Read)
```

### Serviços
- **postgres-primary**: Conexões de escrita → `postgres-0`
- **postgres-replicas**: Conexões de leitura → `postgres-1,postgres-2`
- **postgres-headless**: Descoberta interna dos pods

### Conexão
```bash
# Escrita (Primary)
kubectl exec -it postgres-0 -- psql -U postgres

# Leitura (Replicas)
kubectl exec -it postgres-1 -- psql -U postgres
```

### Verificação
```bash
# Status de replicação no primary
kubectl exec postgres-0 -- psql -U postgres -c "SELECT * FROM pg_stat_replication;"

# Verificar dados replicados nas replicas
kubectl exec postgres-1 -- psql -U postgres -c "SELECT * FROM pg_stat_wal_receiver;"
```

---

## 🍃 MongoDB Replica Set

### Características
- **Versão**: MongoDB 7.0
- **Arquitetura**: 1 Primary + 2 Secondary
- **Replicação**: Replica Set (automática)
- **Storage**: Local-path (K3s)
- **Automação**: Automática com Job

### Deploy Automático
```bash
# Método 1: Script completo
./deploy-mongodb.sh

# Método 2: Manual
kubectl apply -f mongodb.yaml
kubectl apply -f mongodb-init-job.yaml
```

### Estrutura do Cluster
```
mongodb-0 (PRIMARY)     ← Escritas
    ↓
mongodb-1 (SECONDARY)   ← Leituras
mongodb-2 (SECONDARY)   ← Leituras
```

### Serviços
- **mongodb-primary**: Conexões de escrita → `mongodb-0`
- **mongodb-replicas**: Conexões de leitura → `mongodb-1,mongodb-2`
- **mongodb-headless**: Descoberta interna dos pods

### Conexão
```bash
# Escrita (Primary)
kubectl exec -it mongodb-0 -- mongosh

# Leitura (Secondary)
kubectl exec -it mongodb-1 -- mongosh --eval "db.getMongo().setReadPref('secondary')"
```

### Verificação
```bash
# Status do Replica Set
kubectl exec mongodb-0 -- mongosh --eval "rs.status()"

# Inserir dados no Primary
kubectl exec mongodb-0 -- mongosh --eval "use testdb; db.test.insertOne({msg: 'Hello World'})"

# Verificar no Secondary
kubectl exec mongodb-1 -- mongosh testdb --eval "db.getMongo().setReadPref('secondary'); db.test.find()"
```

---

## 🐬 MySQL Primary-Replica

### Características
- **Versão**: MySQL 8.0
- **Arquitetura**: 1 Primary + 2 Replicas (Read/Write)
- **Replicação**: Binary Log Replication (automática)
- **Storage**: Local-path (K3s)
- **Automação**: 100% automática

### Deploy
```bash
kubectl apply -f 3.yaml
```

### Estrutura do Cluster
```
mysql-0 (PRIMARY)     ← Escritas (Write)
    ↓
mysql-1 (REPLICA)     ← Leituras (Read)
mysql-2 (REPLICA)     ← Leituras (Read)
```

### Serviços
- **mysql-master**: Conexões de escrita (write) → `mysql-0`
- **mysql-slave**: Conexões de leitura (read) → `mysql-1,mysql-2`
- **mysql-headless**: Descoberta interna dos pods

### Conexão
```bash
# Escrita (Primary)
kubectl exec -it mysql-0 -- mysql -u root -p

# Leitura (Replicas)
kubectl exec -it mysql-1 -- mysql -u root -p
```

### Verificação
```bash
# Status de replicação no primary
kubectl exec mysql-0 -- mysql -u root -prootpass -e "SHOW MASTER STATUS;"

# Status das replicas
kubectl exec mysql-1 -- mysql -u root -prootpass -e "SHOW REPLICA STATUS\G"
kubectl exec mysql-2 -- mysql -u root -prootpass -e "SHOW REPLICA STATUS\G"
```

---

## 🛠️ Estrutura dos Arquivos

### PostgreSQL
```
postgres.yaml           # StatefulSet completo com automação
├── ConfigMap          # Scripts de inicialização
├── StatefulSet        # 3 replicas (1 primary + 2 replicas)
├── Services           # Primary, Replicas, Headless
└── Automação         # Detecção automática de role (primary/replica)
```

### MongoDB
```
mongodb.yaml            # StatefulSet principal
mongodb-init-job.yaml   # Job de configuração automática
deploy-mongodb.sh       # Script de deploy completo
├── ConfigMap          # Scripts de inicialização
├── StatefulSet        # 3 replicas (1 primary + 2 secondary)
├── Services           # Primary, Replicas, Headless
└── Job               # Configuração automática do Replica Set
```

### MySQL
```
3.yaml                  # StatefulSet completo com automação
├── ConfigMap          # Scripts de inicialização e replicação
├── StatefulSet        # 3 replicas (1 primary + 2 replicas)
├── Services           # Primary, Replica, Headless
└── Automação         # Configuração automática de Binary Log Replication
```

---

## ⚙️ Requisitos

### Cluster Kubernetes
- **K3s** (testado) ou qualquer Kubernetes
- **StorageClass**: `local-path` (padrão K3s)
- **Recursos mínimos**: 2GB RAM, 2 CPU cores

### Instalação K3s
```bash
# Instalar K3s
curl -sfL https://get.k3s.io | sh -

# Configurar kubectl
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

---

## 🔍 Troubleshooting

### PostgreSQL
```bash
# Verificar logs
kubectl logs postgres-0

# Verificar status de replicação
kubectl exec postgres-0 -- psql -U postgres -c "\x" -c "SELECT * FROM pg_stat_replication;"

# Verificar se replica está recebendo dados
kubectl exec postgres-1 -- psql -U postgres -c "SELECT pg_is_in_recovery();"
```

### MongoDB
```bash
# Verificar logs do pod
kubectl logs mongodb-0

# Verificar logs do Job de inicialização
kubectl logs job/mongodb-init-replica

# Status detalhado do Replica Set
kubectl exec mongodb-0 -- mongosh --eval "rs.status().members.forEach(m => print(m.name + ': ' + m.stateStr))"

# Forçar reconfiguração (se necessário)
kubectl exec mongodb-0 -- mongosh --eval "rs.reconfig({_id:'rs0', members:[{_id:0, host:'mongodb-0.mongodb-headless:27017'}, {_id:1, host:'mongodb-1.mongodb-headless:27017'}, {_id:2, host:'mongodb-2.mongodb-headless:27017'}]}, {force:true})"
```

### MySQL
```bash
# Verificar logs
kubectl logs mysql-0

# Status de replicação no primary
kubectl exec mysql-0 -- mysql -u root -prootpass -e "SHOW MASTER STATUS;"

# Verificar status das replicas
kubectl exec mysql-1 -- mysql -u root -prootpass -e "SHOW REPLICA STATUS\G" | grep -E "(Replica_IO_Running|Replica_SQL_Running|Master_Log_File|Read_Master_Log_Pos)"
kubectl exec mysql-2 -- mysql -u root -prootpass -e "SHOW REPLICA STATUS\G" | grep -E "(Replica_IO_Running|Replica_SQL_Running|Master_Log_File|Read_Master_Log_Pos)"

# Verificar usuário de replicação
kubectl exec mysql-0 -- mysql -u root -prootpass -e "SELECT User, Host FROM mysql.user WHERE User='repl';"
```

### Problemas Comuns
1. **StorageClass não encontrado**: Verificar se `local-path` está disponível
   ```bash
   kubectl get storageclass
   ```

2. **Pods não iniciam**: Verificar recursos disponíveis
   ```bash
   kubectl describe pod <pod-name>
   ```

3. **MongoDB replica set não configura**: Aguardar mais tempo ou executar Job manualmente
   ```bash
   kubectl delete job mongodb-init-replica
   kubectl apply -f mongodb-init-job.yaml
   ```

---


### Testes de Replicação

#### PostgreSQL
```bash
# Inserir no primary (write)
kubectl exec postgres-0 -- psql -U postgres -c "CREATE TABLE test (id INT, msg TEXT); INSERT INTO test VALUES (1, 'Hello from primary');"

# Verificar na replica (read)
kubectl exec postgres-1 -- psql -U postgres -c "SELECT * FROM test;"
```

#### MongoDB
```bash
# Inserir no primary
kubectl exec mongodb-0 -- mongosh --eval "use testdb; db.replication_test.insertOne({msg: 'Hello from primary', timestamp: new Date()})"

# Verificar no secondary
kubectl exec mongodb-1 -- mongosh testdb --eval "db.getMongo().setReadPref('secondary'); db.replication_test.find()"
```

#### MySQL
```bash
# Inserir no primary (write)
kubectl exec mysql-0 -- mysql -u root -prootpass -e "CREATE DATABASE testdb; USE testdb; CREATE TABLE test (id INT PRIMARY KEY, msg VARCHAR(100)); INSERT INTO test VALUES (1, 'Hello from primary');"

# Verificar nas replicas (read)
kubectl exec mysql-1 -- mysql -u root -prootpass -e "USE testdb; SELECT * FROM test;"
kubectl exec mysql-2 -- mysql -u root -prootpass -e "USE testdb; SELECT * FROM test;"
```

---


