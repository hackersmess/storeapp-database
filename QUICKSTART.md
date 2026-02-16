# Quick Start PostgreSQL con Podman

## ⚠️ IMPORTANTE: Prima Avvia Podman Machine (Windows)

```powershell
# 1. Avvia la macchina virtuale Podman
podman machine start

# 2. Verifica che sia avviata
podman machine list
```

---

## Comandi Rapidi

### 1⃣ Avvia PostgreSQL (prima volta)

```powershell
podman run -d `
  --name storeapp-postgres `
  -e POSTGRES_DB=storeapp `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=postgres `
  -p 5432:5432 `
  -v storeapp-postgres-data:/var/lib/postgresql/data `
  postgres:15-alpine
```

### 2⃣ Verifica che funzioni

```powershell
podman ps
```

Output atteso:

```
CONTAINER ID  IMAGE                     STATUS         PORTS                   NAMES
xxxxx         postgres:15-alpine        Up 5 seconds   0.0.0.0:5432->5432/tcp  storeapp-postgres
```

### 3⃣ Connetti DBeaver

- Host: `localhost`
- Port: `5432`
- Database: `storeapp`
- Username: `postgres`
- Password: `postgres`

### 4⃣ Esegui Migration

In DBeaver, apri ed esegui in ordine:

1. `V1__create_users_table.sql`
2. `V2__create_groups_tables.sql`
3. `V3__create_photos_table.sql`
4. `V4__create_events_tables.sql`
5. `V5__create_documents_tables.sql`
6. `V6__create_expenses_tables.sql`
7. `V7__create_comments_table.sql`
8. `V8__create_views.sql`
9. `V9__insert_sample_data.sql`

---

## Comandi Utili

```powershell
# 🚀 AVVIO COMPLETO (esegui in ordine)
# 1. Avvia la macchina Podman
podman machine start

# 2. Avvia PostgreSQL
podman start storeapp-postgres

# 3. Verifica che funzioni
podman ps

# ⏸️ FERMA TUTTO
# Ferma PostgreSQL
podman stop storeapp-postgres

# Ferma la macchina Podman (opzionale, risparmia risorse)
podman machine stop

# 🔄 RIAVVIA PostgreSQL (se già running)

# 📋 Vedi log
podman logs -f storeapp-postgres

# 💻 Entra nel container
podman exec -it storeapp-postgres psql -U postgres -d storeapp

# 💾 Backup
podman exec storeapp-postgres pg_dump -U postgres storeapp > backup.sql

# 🗑️ Reset completo (CANCELLA TUTTO!)
podman stop storeapp-postgres
podman rm -f storeapp-postgres
podman volume rm storeapp-postgres-data
```

---

## Setup Completato!

Ora sei pronto per:

- Sviluppare il backend Quarkus
- Creare le API REST
- Connettere il frontend Angular

Vedi: [../docs/backend-setup.md](../docs/backend-setup.md)
