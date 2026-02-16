# Database Setup Guide - StoreApp

Guida completa per configurare il database PostgreSQL del progetto.

---

## Prerequisiti

- **Podman Desktop** installato (oppure Docker)
- **DBeaver** (o altro client PostgreSQL)

---

## Quick Start (3 Passi)

### 1. Avvia Podman Machine

```powershell
# Verifica stato Podman
podman machine list

# Se non è avviata, avviala
podman machine start
```

### 2. Avvia PostgreSQL

```powershell
# Dalla root del progetto
cd c:\Users\marlombard\personal\storeapp

# Avvia container PostgreSQL
podman run -d `
  --name storeapp-postgres `
  -e POSTGRES_DB=storeapp `
  -e POSTGRES_USER=postgres `
  -e POSTGRES_PASSWORD=postgres `
  -p 5432:5432 `
  -v storeapp-postgres-data:/var/lib/postgresql/data `
  postgres:15-alpine

# Verifica che sia attivo
podman ps
```

**Output atteso:**

```
CONTAINER ID  IMAGE                     STATUS      PORTS                   NAMES
xxxxx         postgres:15-alpine        Up 10s      0.0.0.0:5432->5432/tcp  storeapp-postgres
```

### 3. Esegui Migration in DBeaver

1. **Apri DBeaver**
2. **Crea nuova connessione PostgreSQL**:
   - Host: `localhost`
   - Port: `5432`
   - Database: `storeapp`
   - Username: `postgres`
   - Password: `postgres`
3. **Test Connection** → OK
4. **Apri file**: `database/migrations/ALL_MIGRATIONS.sql`
5. **Esegui tutto** (Ctrl+Enter o F5)
6. **Verifica output** - vedrai messaggio di successo

---

## Dettagli PostgreSQL con Podman

### Credenziali Database

- **Host**: `localhost`
- **Port**: `5432`
- **Database**: `storeapp`
- **Username**: `postgres`
- **Password**: `postgres`

### Comandi Utili

```powershell
# Ferma PostgreSQL
podman stop storeapp-postgres

# Riavvia PostgreSQL
podman start storeapp-postgres

# Vedi log in tempo reale
podman logs -f storeapp-postgres

# Entra nel database via CLI
podman exec -it storeapp-postgres psql -U postgres -d storeapp

# Backup database
podman exec storeapp-postgres pg_dump -U postgres storeapp > backup.sql

# Restore database
podman exec -i storeapp-postgres psql -U postgres storeapp < backup.sql
```

### Troubleshooting

**Podman Machine non attiva:**

```powershell
podman machine start
```

**Port 5432 già occupato:**

```powershell
# Verifica cosa occupa la porta
netstat -ano | findstr :5432

# Cambia porta nel comando run (usa 5433)
-p 5433:5432
```

**Container già esistente:**

```powershell
# Rimuovi container esistente
podman rm -f storeapp-postgres

# Ricrea
podman run -d --name storeapp-postgres ...
```

> 💡 **Guida completa Podman**: [PODMAN-SETUP.md](./PODMAN-SETUP.md)  
> ⚡ **Comandi rapidi**: [QUICKSTART.md](./QUICKSTART.md)

---

## Cosa Viene Creato

Eseguendo `ALL_MIGRATIONS.sql` otterrai:

### Tabelle (12)

- `users` - Utenti con autenticazione
- `groups` - Gruppi vacanza
- `group_members` - Membri dei gruppi con ruoli (ADMIN/MEMBER)
- `photos` - Foto condivise
- `likes` - Like alle foto
- `events` - Eventi pianificati
- `event_attendees` - Partecipanti eventi con RSVP
- `documents` - Documenti condivisi
- `document_versions` - Versioning automatico
- `expenses` - Spese di gruppo
- `expense_splits` - Suddivisione spese
- `comments` - Commenti su foto/eventi/documenti

### Viste (5)

- `group_summary` - Statistiche gruppi
- `photo_stats` - Statistiche foto con like/commenti
- `user_stats` - Statistiche utenti
- `event_calendar` - Calendario eventi con presenze
- `user_expense_balance` - Bilancio spese per utente/gruppo

### Trigger (3)

- Auto-aggiunge creatore come ADMIN del gruppo
- Aggiorna versione corrente documento
- Valida che somma split = importo spesa

### Dati di Test

- 4 utenti (Mario, Laura, Giovanni, Sara)
- 3 gruppi (Sardegna, Dolomiti, Toscana)
- 6 eventi
- 7 spese con split
- 4 foto con like e commenti
- 3 documenti

**Credenziali test:**

- Email: `mario@example.com`
- Password: `Test123!`

---

## Verifica Setup

### Query di Test in DBeaver

```sql
-- 1. Conta tabelle create
SELECT COUNT(*) as total_tables
FROM information_schema.tables
WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
-- Expected: 12

-- 2. Lista tutte le tabelle
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
ORDER BY table_name;

-- 3. Verifica dati di test
SELECT COUNT(*) FROM users;         -- Expected: 4
SELECT COUNT(*) FROM groups;        -- Expected: 3
SELECT COUNT(*) FROM expenses;      -- Expected: 7
SELECT COUNT(*) FROM photos;        -- Expected: 4

-- 4. Testa viste
SELECT * FROM group_summary;
SELECT * FROM photo_stats;

-- 5. Test bilancio spese (Gruppo Sardegna)
SELECT
    user_name,
    total_paid,
    total_owed,
    balance
FROM user_expense_balance
WHERE group_id = 1
ORDER BY balance DESC;
```

**Output atteso bilancio:**

```
user_name      | total_paid | total_owed | balance
---------------+------------+------------+---------
Mario Rossi    | 690.00     | 272.50     | +417.50  (credito)
Sara Neri      | 120.00     | 272.50     | -152.50  (debito)
Giovanni Verdi | 200.00     | 272.50     | -72.50   (debito)
Laura Bianchi  | 80.00      | 272.50     | -192.50  (debito)
```

### Test Trigger

```sql
-- Verifica trigger auto-admin
-- Crea nuovo gruppo
INSERT INTO groups (name, created_by) VALUES ('Test Trigger', 1);

-- Verifica che Mario (user_id=1) sia ADMIN
SELECT gm.user_id, u.name, gm.role
FROM group_members gm
JOIN users u ON gm.user_id = u.id
WHERE gm.group_id = (SELECT MAX(id) FROM groups);
-- Expected: user_id=1, name='Mario Rossi', role='ADMIN'
```

---

## Operazioni Comuni

### Reset Completo Database

**ATTENZIONE: Cancella TUTTI i dati!**

```sql
-- In DBeaver
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;

-- Poi ri-esegui ALL_MIGRATIONS.sql
```

### Rimuovi Solo Dati di Test

```sql
-- Cancella solo i dati, mantieni struttura
TRUNCATE users, groups, photos, events, documents, expenses, comments CASCADE;

-- Resetta sequenze ID
ALTER SEQUENCE users_id_seq RESTART WITH 1;
ALTER SEQUENCE groups_id_seq RESTART WITH 1;
ALTER SEQUENCE photos_id_seq RESTART WITH 1;
ALTER SEQUENCE events_id_seq RESTART WITH 1;
ALTER SEQUENCE documents_id_seq RESTART WITH 1;
ALTER SEQUENCE expenses_id_seq RESTART WITH 1;
ALTER SEQUENCE comments_id_seq RESTART WITH 1;
```

### Backup e Restore

```powershell
# Backup completo
$date = Get-Date -Format "yyyy-MM-dd"
podman exec storeapp-postgres pg_dump -U postgres storeapp > "backup_$date.sql"

# Backup solo schema (senza dati)
podman exec storeapp-postgres pg_dump -U postgres --schema-only storeapp > schema.sql

# Backup solo dati
podman exec storeapp-postgres pg_dump -U postgres --data-only storeapp > data.sql

# Restore
podman exec -i storeapp-postgres psql -U postgres storeapp < backup.sql
```

---

## Prossimi Passi

Ora che il database è pronto:

1. **Database creato** - 12 tabelle + 5 viste
2. **Dati di test** - pronti per sviluppo
3. **Setup backend** - Quarkus + JPA entities
4. **Setup frontend** - Angular + Material UI
5. **Connetti tutto** - API REST

### Guide Disponibili

- **Podman completo**: [PODMAN-SETUP.md](./PODMAN-SETUP.md)
- **Quick reference**: [QUICKSTART.md](./QUICKSTART.md)
- **Backend setup**: [../docs/backend-setup.md](../docs/backend-setup.md)
- **Frontend setup**: [../docs/frontend-setup.md](../docs/frontend-setup.md)
- **Project plan**: [../ROADMAP.md](../ROADMAP.md)

---

## Tips

- **Lascia PostgreSQL sempre acceso** durante lo sviluppo (consuma poca RAM)
- **Usa le viste** per query complesse già ottimizzate
- **Testa i trigger** prima di usarli in produzione
- **Fai backup regolari** durante lo sviluppo
- **Usa DBeaver** per esplorare il database visualmente

---

## Supporto

- **Podman non parte**: `podman machine start`
- **Porta occupata**: cambia porta nel comando `run` (`-p 5433:5432`)
- **Container già esiste**: `podman rm -f storeapp-postgres`
- **Reset completo**: DROP SCHEMA + ri-esegui `ALL_MIGRATIONS.sql`

**Buon sviluppo!**
