#  Setup Database con Podman Desktop

##  Prerequisiti

- **Podman Desktop** installato
- Podman Machine avviata

---

##  Avvio Rapido

### 1. Avvia PostgreSQL

```powershell
# Dalla root del progetto
cd c:\Users\marlombard\personal\storeapp

# METODO 1: Podman nativo (RACCOMANDATO - non serve compose)
podman run -d `
  --name storeapp-postgres `
  -e POSTGRES_DB=storeapp `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=postgres `
  -p 5432:5432 `
  -v storeapp-postgres-data:/var/lib/postgresql/data `
  postgres:15-alpine

# METODO 2: Con podman-compose (se installato)
podman-compose up -d postgres

# METODO 3: Con docker-compose (se Podman è configurato come alias)
docker-compose up -d postgres
```

### 2. Verifica Container Attivo

```powershell
# Lista container in esecuzione
podman ps

# Dovresti vedere:
# CONTAINER ID  IMAGE                      STATUS      PORTS                   NAMES
# xxxxx         postgres:15-alpine         Up 10s      0.0.0.0:5432->5432/tcp  storeapp-postgres
```

### 3. Test Connessione

```powershell
# Entra nel container PostgreSQL
podman exec -it storeapp-postgres psql -U postgres -d storeapp

# Oppure
podman exec -it storeapp-postgres bash
psql -U postgres -d storeapp
```

---

##  Connessione DBeaver

### Configurazione Connessione

1. **Apri DBeaver**
2. **New Database Connection** → PostgreSQL
3. **Inserisci credenziali**:
   - **Host**: `localhost`
   - **Port**: `5432`
   - **Database**: `storeapp`
   - **Username**: `postgres`
   - **Password**: `postgres`
4. **Test Connection** → OK 
5. **Finish**

### Troubleshooting Connessione

Se DBeaver non si connette:

```powershell
# Verifica che il container sia in ascolto
podman port storeapp-postgres

# Output atteso:
# 5432/tcp -> 0.0.0.0:5432

# Verifica log PostgreSQL
podman logs storeapp-postgres

# Dovrebbe mostrare:
# database system is ready to accept connections
```

---

##  Esecuzione Migration

### Metodo 1: Da DBeaver (Raccomandato)

1. Connetti a `storeapp` database
2. Apri un nuovo SQL Editor (Ctrl+])
3. **Per ogni file** (in ordine V1 → V9):
   - Apri il file `.sql` da `database/migrations/`
   - Esegui lo script (Ctrl+Enter)
   - Verifica successo nel log

### Metodo 2: Script All-in-One

Crea questo file per eseguire tutte le migration in una volta:

**database/migrations/run-all.sql:**

```sql
-- =====================================================
-- Run all migrations in order
-- Execute this file in DBeaver
-- =====================================================

\echo ' Starting migrations...'

-- V1: Users
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V1__create_users_table.sql'
\echo ' V1 completed'

-- V2: Groups
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V2__create_groups_tables.sql'
\echo ' V2 completed'

-- V3: Photos
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V3__create_photos_table.sql'
\echo ' V3 completed'

-- V4: Events
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V4__create_events_tables.sql'
\echo ' V4 completed'

-- V5: Documents
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V5__create_documents_tables.sql'
\echo ' V5 completed'

-- V6: Expenses
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V6__create_expenses_tables.sql'
\echo ' V6 completed'

-- V7: Comments
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V7__create_comments_table.sql'
\echo ' V7 completed'

-- V8: Views
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V8__create_views.sql'
\echo ' V8 completed'

-- V9: Sample Data
\i 'c:/Users/marlombard/personal/storeapp/database/migrations/V9__insert_sample_data.sql'
\echo ' V9 completed'

\echo '� All migrations completed successfully!'
```

### Metodo 3: Da Podman CLI

```powershell
# Copia tutti gli script nel container
podman cp database/migrations storeapp-postgres:/tmp/

# Esegui tutte le migration
podman exec -it storeapp-postgres bash -c "
  for file in /tmp/migrations/V*.sql; do
    echo \"Executing: \$file\"
    psql -U postgres -d storeapp -f \$file
  done
"
```

---

##  Comandi Utili Podman

### Gestione Container

```powershell
# Avvia PostgreSQL (se non già avviato)
podman start storeapp-postgres

# Ferma PostgreSQL
podman stop storeapp-postgres

# Ferma e rimuovi container
podman rm -f storeapp-postgres

# Ferma e rimuovi volumi (ATTENZIONE: cancella dati!)
podman volume rm storeapp-postgres-data

# Riavvia PostgreSQL
podman restart storeapp-postgres

# Vedi log in real-time
podman logs -f storeapp-postgres

# Statistiche container
podman stats storeapp-postgres

# Lista tutti i container (anche fermati)
podman ps -a
```

### Backup & Restore

```powershell
# Backup database
podman exec storeapp-postgres pg_dump -U postgres storeapp > backup.sql

# Restore database
podman exec -i storeapp-postgres psql -U postgres storeapp < backup.sql

# Backup automatico con timestamp
$date = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
podman exec storeapp-postgres pg_dump -U postgres storeapp > "backup_$date.sql"
```

### Pulizia

```powershell
# Rimuovi container
podman rm -f storeapp-postgres

# Rimuovi volumi (cancella dati!)
podman volume rm storeapp_postgres-data

# Rimuovi immagini non usate
podman image prune -a
```

---

##  PgAdmin Web UI (Opzionale)

Se preferisci un'interfaccia web invece di DBeaver:

```powershell
# Avvia PgAdmin container
podman run -d `
  --name storeapp-pgadmin `
  -e PGADMIN_DEFAULT_EMAIL=admin@storeapp.local `
  -e PGADMIN_DEFAULT_PASSWORD=admin `
  -e PGADMIN_CONFIG_SERVER_MODE=False `
  -p 5050:80 `
  dpage/pgadmin4:latest

# Apri browser: http://localhost:5050
# Login: admin@storeapp.local / admin
```

**Configurare connessione in PgAdmin:**

1. Add New Server
2. General → Name: `StoreApp Local`
3. Connection:
   - Host: `postgres` (nome del service)
   - Port: `5432`
   - Database: `storeapp`
   - Username: `postgres`
   - Password: `postgres`
4. Save

---

##  Verifica Setup Completo

```powershell
# 1. Container attivo
podman ps | Select-String "storeapp-postgres"

# 2. Database accessibile
podman exec storeapp-postgres psql -U postgres -d storeapp -c "SELECT version();"

# 3. Test query
podman exec storeapp-postgres psql -U postgres -d storeapp -c "SELECT COUNT(*) FROM users;"
# Expected: 4 (se hai eseguito V9)
```

---

##  Workflow Quotidiano

```powershell
# Mattina - Avvia DB (se fermato)
podman start storeapp-postgres

# Lavora con DBeaver/PgAdmin
# ...

# Sera - Ferma DB (opzionale, puoi lasciarlo acceso)
podman stop storeapp-postgres

# Oppure lascialo sempre acceso (consuma poca RAM)
```

---

##  Troubleshooting

### Port 5432 già occupato

```powershell
# Verifica cosa occupa la porta
netstat -ano | findstr :5432

# Cambia porta in docker-compose.yml
# "5433:5432" invece di "5432:5432"
```

### Container non si avvia

```powershell
# Controlla log
podman logs storeapp-postgres

# Rimuovi e ricrea
podman rm -f storeapp-postgres
podman volume rm storeapp-postgres-data

# Ricrea (copia il comando da sopra)
podman run -d `
  --name storeapp-postgres `
  -e POSTGRES_DB=storeapp `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=postgres `
  -p 5432:5432 `
  -v storeapp-postgres-data:/var/lib/postgresql/data `
  postgres:15-alpine
```

### Podman Machine non attiva

```powershell
# Lista macchine
podman machine list

# Avvia macchina default
podman machine start

# O crea nuova
podman machine init
podman machine start
```

---

##  Prossimi Passi

1.  Avvia PostgreSQL con Podman
2.  Connetti DBeaver
3.  Esegui migration V1-V9
4.  Verifica dati di test
5.  Setup backend Quarkus
6.  Connetti backend al DB

---

##  Link Utili

- [Podman Desktop](https://podman-desktop.io/)
- [Podman Compose](https://github.com/containers/podman-compose)
- [PostgreSQL Docker Hub](https://hub.docker.com/_/postgres)
