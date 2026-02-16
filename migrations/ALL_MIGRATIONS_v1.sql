-- =====================================================
-- ALL MIGRATIONS - StoreApp Database
-- Description: Complete database setup in one file
-- Execute this entire file in DBeaver
-- =====================================================

-- =====================================================
-- V1: Create USERS table
-- =====================================================

CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL UNIQUE,
    name VARCHAR(100) NOT NULL,
    bio TEXT,
    avatar_url VARCHAR(500),
    google_id VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT email_format CHECK (
        email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}$'
    ),
    CONSTRAINT auth_method CHECK (
        google_id IS NOT NULL OR password_hash IS NOT NULL
    )
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_google_id ON users(google_id) WHERE google_id IS NOT NULL;

COMMENT ON TABLE users IS 'Registered users with authentication info';
COMMENT ON COLUMN users.google_id IS 'Google OAuth ID if user registered via Google';
COMMENT ON COLUMN users.password_hash IS 'BCrypt hash if user registered via email/password';
COMMENT ON COLUMN users.avatar_url IS 'URL to avatar image in object storage';


-- =====================================================
-- V2: Create GROUPS and GROUP_MEMBERS tables
-- =====================================================

CREATE TABLE groups (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    vacation_start_date DATE,
    vacation_end_date DATE,
    cover_image_url VARCHAR(500),
    created_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT valid_vacation_dates CHECK (
        vacation_end_date IS NULL OR 
        vacation_start_date IS NULL OR 
        vacation_end_date >= vacation_start_date
    )
);

CREATE TABLE group_members (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL DEFAULT 'MEMBER',
    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT unique_group_member UNIQUE (group_id, user_id),
    CONSTRAINT valid_role CHECK (role IN ('ADMIN', 'MEMBER'))
);

CREATE INDEX idx_groups_created_by ON groups(created_by);
CREATE INDEX idx_groups_vacation_dates ON groups(vacation_start_date, vacation_end_date);
CREATE INDEX idx_group_members_group_id ON group_members(group_id);
CREATE INDEX idx_group_members_user_id ON group_members(user_id);

COMMENT ON TABLE groups IS 'Vacation groups';
COMMENT ON TABLE group_members IS 'Users belonging to groups with their role';
COMMENT ON COLUMN group_members.role IS 'ADMIN can manage group, MEMBER has read/write access';

-- NOTA: Il creatore viene aggiunto come ADMIN lato applicativo (GroupService.createGroup)
-- Non c'è più il trigger automatico nel database


-- =====================================================
-- V3: Create PHOTOS and LIKES tables
-- =====================================================

CREATE TABLE photos (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    group_id BIGINT REFERENCES groups(id) ON DELETE CASCADE,
    title VARCHAR(200),
    description TEXT,
    file_url VARCHAR(500) NOT NULL,
    thumbnail_url VARCHAR(500),
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(50) NOT NULL,
    uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT valid_mime_type CHECK (
        mime_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic')
    ),
    CONSTRAINT valid_file_size CHECK (
        file_size > 0 AND file_size <= 52428800  -- max 50MB
    )
);

CREATE TABLE likes (
    id BIGSERIAL PRIMARY KEY,
    photo_id BIGINT NOT NULL REFERENCES photos(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT unique_like UNIQUE (photo_id, user_id)
);

CREATE INDEX idx_photos_user_id ON photos(user_id);
CREATE INDEX idx_photos_group_id ON photos(group_id) WHERE group_id IS NOT NULL;
CREATE INDEX idx_photos_uploaded_at ON photos(uploaded_at DESC);
CREATE INDEX idx_likes_photo_id ON likes(photo_id);
CREATE INDEX idx_likes_user_id ON likes(user_id);

COMMENT ON TABLE photos IS 'User uploaded photos';
COMMENT ON TABLE likes IS 'Photo likes/favorites';
COMMENT ON COLUMN photos.group_id IS 'Optional: associate photo with a vacation group';
COMMENT ON COLUMN photos.file_url IS 'URL to full-size image in object storage';
COMMENT ON COLUMN photos.thumbnail_url IS 'URL to thumbnail (300x300) in object storage';


-- =====================================================
-- V4: Create EVENTS and EVENT_ATTENDEES tables
-- =====================================================

CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    created_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title VARCHAR(200) NOT NULL,
    description TEXT,
    event_date DATE NOT NULL,
    start_time TIME,
    end_time TIME,
    location VARCHAR(300),
    location_lat DECIMAL(10, 8),
    location_lng DECIMAL(11, 8),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT valid_time_range CHECK (
        end_time IS NULL OR 
        start_time IS NULL OR 
        end_time > start_time
    ),
    CONSTRAINT valid_coordinates CHECK (
        (location_lat IS NULL AND location_lng IS NULL) OR
        (location_lat BETWEEN -90 AND 90 AND location_lng BETWEEN -180 AND 180)
    )
);

CREATE TABLE event_attendees (
    id BIGSERIAL PRIMARY KEY,
    event_id BIGINT NOT NULL REFERENCES events(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(20) NOT NULL DEFAULT 'MAYBE',
    checked_in BOOLEAN DEFAULT FALSE,
    checked_in_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT unique_attendee UNIQUE (event_id, user_id),
    CONSTRAINT valid_status CHECK (status IN ('GOING', 'NOT_GOING', 'MAYBE'))
);

CREATE INDEX idx_events_group_id ON events(group_id);
CREATE INDEX idx_events_event_date ON events(event_date);
CREATE INDEX idx_events_created_by ON events(created_by);
CREATE INDEX idx_event_attendees_event_id ON event_attendees(event_id);
CREATE INDEX idx_event_attendees_user_id ON event_attendees(user_id);

COMMENT ON TABLE events IS 'Planned events/activities for vacation groups';
COMMENT ON TABLE event_attendees IS 'RSVP and check-in status for event participants';
COMMENT ON COLUMN event_attendees.status IS 'RSVP status: GOING, NOT_GOING, or MAYBE';
COMMENT ON COLUMN event_attendees.checked_in IS 'Whether user actually attended the event';


-- =====================================================
-- V5: Create DOCUMENTS and DOCUMENT_VERSIONS tables
-- =====================================================

CREATE TABLE documents (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    created_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    title VARCHAR(300) NOT NULL,
    description TEXT,
    current_version INTEGER NOT NULL DEFAULT 1,
    file_type VARCHAR(100) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE document_versions (
    id BIGSERIAL PRIMARY KEY,
    document_id BIGINT NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    file_url VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    uploaded_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    change_description TEXT,
    uploaded_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT unique_document_version UNIQUE (document_id, version_number),
    CONSTRAINT valid_version_number CHECK (version_number > 0),
    CONSTRAINT valid_file_size CHECK (file_size > 0 AND file_size <= 104857600)  -- max 100MB
);

CREATE INDEX idx_documents_group_id ON documents(group_id);
CREATE INDEX idx_documents_created_by ON documents(created_by);
CREATE INDEX idx_document_versions_document_id ON document_versions(document_id);
CREATE INDEX idx_document_versions_uploaded_at ON document_versions(uploaded_at DESC);

COMMENT ON TABLE documents IS 'Shared documents with versioning support';
COMMENT ON TABLE document_versions IS 'Individual versions of each document';
COMMENT ON COLUMN documents.current_version IS 'Latest version number';
COMMENT ON COLUMN document_versions.version_number IS 'Sequential version number (1, 2, 3...)';
COMMENT ON COLUMN document_versions.change_description IS 'Optional description of what changed in this version';

-- Trigger to update document.current_version when new version is added
CREATE OR REPLACE FUNCTION update_document_current_version()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE documents 
    SET current_version = NEW.version_number,
        updated_at = NEW.uploaded_at
    WHERE id = NEW.document_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_document_version
AFTER INSERT ON document_versions
FOR EACH ROW
EXECUTE FUNCTION update_document_current_version();


-- =====================================================
-- V6: Create EXPENSES and EXPENSE_SPLITS tables
-- =====================================================

CREATE TABLE expenses (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
    paid_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    description VARCHAR(300) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'EUR',
    expense_date DATE NOT NULL,
    category VARCHAR(50),
    receipt_url VARCHAR(500),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT positive_amount CHECK (amount > 0),
    CONSTRAINT valid_currency CHECK (currency ~ '^[A-Z]{3}$')  -- ISO 4217
);

CREATE TABLE expense_splits (
    id BIGSERIAL PRIMARY KEY,
    expense_id BIGINT NOT NULL REFERENCES expenses(id) ON DELETE CASCADE,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    share_amount DECIMAL(10, 2) NOT NULL,
    
    -- Constraints
    CONSTRAINT unique_expense_split UNIQUE (expense_id, user_id),
    CONSTRAINT positive_share CHECK (share_amount > 0)
);

CREATE INDEX idx_expenses_group_id ON expenses(group_id);
CREATE INDEX idx_expenses_paid_by ON expenses(paid_by);
CREATE INDEX idx_expenses_expense_date ON expenses(expense_date DESC);
CREATE INDEX idx_expenses_category ON expenses(category) WHERE category IS NOT NULL;
CREATE INDEX idx_expense_splits_expense_id ON expense_splits(expense_id);
CREATE INDEX idx_expense_splits_user_id ON expense_splits(user_id);

COMMENT ON TABLE expenses IS 'Group expenses tracking';
COMMENT ON TABLE expense_splits IS 'How each expense is split among users';
COMMENT ON COLUMN expenses.paid_by IS 'User who actually paid the expense';
COMMENT ON COLUMN expense_splits.share_amount IS 'Amount this user owes for the expense';

-- Validation trigger: SUM(splits) must equal expense.amount
CREATE OR REPLACE FUNCTION validate_expense_splits()
RETURNS TRIGGER AS $$
DECLARE
    expense_total DECIMAL(10, 2);
    splits_total DECIMAL(10, 2);
BEGIN
    -- Get expense amount
    SELECT amount INTO expense_total
    FROM expenses
    WHERE id = NEW.expense_id;
    
    -- Calculate sum of all splits
    SELECT COALESCE(SUM(share_amount), 0) INTO splits_total
    FROM expense_splits
    WHERE expense_id = NEW.expense_id;
    
    -- Check if they match (allowing for small rounding errors)
    IF ABS(splits_total - expense_total) > 0.01 THEN
        RAISE EXCEPTION 'Sum of expense splits (%) does not match expense amount (%)', 
            splits_total, expense_total;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_validate_expense_splits
AFTER INSERT OR UPDATE ON expense_splits
FOR EACH ROW
EXECUTE FUNCTION validate_expense_splits();


-- =====================================================
-- V7: Create COMMENTS table
-- =====================================================

CREATE TABLE comments (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type VARCHAR(20) NOT NULL,
    entity_id BIGINT NOT NULL,
    text TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    
    -- Constraints
    CONSTRAINT comment_not_empty CHECK (length(trim(text)) > 0),
    CONSTRAINT valid_entity_type CHECK (entity_type IN ('PHOTO', 'EVENT', 'DOCUMENT'))
);

CREATE INDEX idx_comments_entity ON comments(entity_type, entity_id);
CREATE INDEX idx_comments_user_id ON comments(user_id);
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);

COMMENT ON TABLE comments IS 'User comments on various entities (polymorphic)';
COMMENT ON COLUMN comments.entity_type IS 'Type of entity being commented on: PHOTO, EVENT, or DOCUMENT';
COMMENT ON COLUMN comments.entity_id IS 'ID of the entity (photo_id, event_id, or document_id)';
COMMENT ON COLUMN comments.updated_at IS 'Last edit timestamp (NULL if never edited)';


-- =====================================================
-- V8: Create useful views
-- =====================================================

-- View: Group summary with statistics
CREATE VIEW group_summary AS
SELECT 
    g.id,
    g.name,
    g.description,
    g.vacation_start_date,
    g.vacation_end_date,
    g.cover_image_url,
    g.created_by,
    u.name as creator_name,
    COUNT(DISTINCT gm.user_id) as member_count,
    COUNT(DISTINCT p.id) as photo_count,
    COUNT(DISTINCT e.id) as event_count,
    COUNT(DISTINCT d.id) as document_count,
    COALESCE(SUM(ex.amount), 0) as total_expenses,
    g.created_at
FROM groups g
JOIN users u ON g.created_by = u.id
LEFT JOIN group_members gm ON g.id = gm.group_id
LEFT JOIN photos p ON g.id = p.group_id
LEFT JOIN events e ON g.id = e.group_id
LEFT JOIN documents d ON g.id = d.group_id
LEFT JOIN expenses ex ON g.id = ex.group_id
GROUP BY g.id, u.name;

COMMENT ON VIEW group_summary IS 'Group overview with aggregated statistics';

-- View: Photo statistics with author info
CREATE VIEW photo_stats AS
SELECT 
    p.id,
    p.user_id,
    p.group_id,
    p.title,
    p.description,
    p.file_url,
    p.thumbnail_url,
    p.uploaded_at,
    u.name as author_name,
    u.avatar_url as author_avatar,
    COUNT(DISTINCT l.id) as like_count,
    COUNT(DISTINCT c.id) as comment_count
FROM photos p
JOIN users u ON p.user_id = u.id
LEFT JOIN likes l ON p.id = l.photo_id
LEFT JOIN comments c ON p.id = c.entity_id AND c.entity_type = 'PHOTO'
GROUP BY p.id, u.id;

COMMENT ON VIEW photo_stats IS 'Photo details with like and comment counts';

-- View: User statistics
CREATE VIEW user_stats AS
SELECT 
    u.id,
    u.name,
    u.email,
    u.avatar_url,
    u.bio,
    COUNT(DISTINCT p.id) as photo_count,
    COUNT(DISTINCT l.id) as total_likes_received,
    COUNT(DISTINCT c.id) as total_comments_made,
    COUNT(DISTINCT gm.group_id) as group_count
FROM users u
LEFT JOIN photos p ON u.id = p.user_id
LEFT JOIN likes l ON p.id = l.photo_id
LEFT JOIN comments c ON u.id = c.user_id
LEFT JOIN group_members gm ON u.id = gm.user_id
GROUP BY u.id;

COMMENT ON VIEW user_stats IS 'User activity statistics';

-- View: Event calendar with attendance
CREATE VIEW event_calendar AS
SELECT 
    e.id,
    e.group_id,
    g.name as group_name,
    e.title,
    e.description,
    e.event_date,
    e.start_time,
    e.end_time,
    e.location,
    e.location_lat,
    e.location_lng,
    u.name as created_by_name,
    COUNT(DISTINCT ea.user_id) FILTER (WHERE ea.status = 'GOING') as going_count,
    COUNT(DISTINCT ea.user_id) FILTER (WHERE ea.status = 'MAYBE') as maybe_count,
    COUNT(DISTINCT ea.user_id) FILTER (WHERE ea.status = 'NOT_GOING') as not_going_count,
    COUNT(DISTINCT ea.user_id) FILTER (WHERE ea.checked_in = TRUE) as checked_in_count
FROM events e
JOIN groups g ON e.group_id = g.id
JOIN users u ON e.created_by = u.id
LEFT JOIN event_attendees ea ON e.id = ea.event_id
GROUP BY e.id, g.id, u.name;

COMMENT ON VIEW event_calendar IS 'Events with attendance statistics';

-- View: User expense balance per group
CREATE VIEW user_expense_balance AS
SELECT 
    e.group_id,
    gm.user_id,
    u.name as user_name,
    COALESCE(SUM(CASE WHEN e.paid_by = gm.user_id THEN e.amount ELSE 0 END), 0) as total_paid,
    COALESCE(SUM(es.share_amount), 0) as total_owed,
    COALESCE(SUM(CASE WHEN e.paid_by = gm.user_id THEN e.amount ELSE 0 END), 0) - 
    COALESCE(SUM(es.share_amount), 0) as balance
FROM group_members gm
JOIN users u ON gm.user_id = u.id
LEFT JOIN expenses e ON gm.group_id = e.group_id
LEFT JOIN expense_splits es ON e.id = es.expense_id AND gm.user_id = es.user_id
GROUP BY e.group_id, gm.user_id, u.name;

COMMENT ON VIEW user_expense_balance IS 'User balance per group (positive = credit, negative = debt)';


-- =====================================================
-- V9: Insert sample development data
-- =====================================================

-- Insert test users
INSERT INTO users (email, name, bio, password_hash) VALUES
('mario@example.com', 'Mario Rossi', 'Fotografo amatoriale', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u'), -- password: Test123!
('laura@example.com', 'Laura Bianchi', 'Amante della natura', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u'),
('giovanni@example.com', 'Giovanni Verdi', 'Travel blogger', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u'),
('sara@example.com', 'Sara Neri', 'Designer', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u');

-- Insert test groups
INSERT INTO groups (name, description, vacation_start_date, vacation_end_date, created_by) VALUES
('Sardegna 2026', 'Settimana in Sardegna', '2026-08-01', '2026-08-08', 1),
('Weekend Montagna', 'Weekend sulle Dolomiti', '2026-06-15', '2026-06-17', 2),
('Road Trip Toscana', 'Giro della Toscana', '2026-09-10', '2026-09-17', 3);

-- Insert group members (creator already added by trigger)
INSERT INTO group_members (group_id, user_id, role) VALUES
(1, 2, 'MEMBER'),
(1, 3, 'MEMBER'),
(1, 4, 'ADMIN'),
(2, 1, 'MEMBER'),
(2, 3, 'MEMBER'),
(3, 1, 'MEMBER'),
(3, 2, 'MEMBER');

-- Insert test events
INSERT INTO events (group_id, created_by, title, description, event_date, start_time, location) VALUES
(1, 1, 'Arrivo a Cagliari', 'Volo e check-in hotel', '2026-08-01', '14:00', 'Aeroporto Cagliari'),
(1, 1, 'Spiaggia Villasimius', 'Giornata al mare', '2026-08-02', '09:00', 'Villasimius Beach'),
(1, 4, 'Escursione Capo Testa', 'Trekking panoramico', '2026-08-03', '08:30', 'Capo Testa'),
(1, 2, 'Cena di gruppo', 'Ristorante tipico sardo', '2026-08-04', '20:00', 'Ristorante Sa Cardiga'),
(2, 2, 'Partenza per Cortina', 'Viaggio in auto', '2026-06-15', '06:00', 'Milano'),
(2, 2, 'Escursione Tre Cime', 'Trekking alle Tre Cime di Lavaredo', '2026-06-16', '07:00', 'Rifugio Auronzo');

-- Insert event attendees
INSERT INTO event_attendees (event_id, user_id, status) VALUES
(1, 1, 'GOING'),
(1, 2, 'GOING'),
(1, 3, 'GOING'),
(1, 4, 'GOING'),
(2, 1, 'GOING'),
(2, 2, 'GOING'),
(2, 3, 'MAYBE'),
(2, 4, 'GOING'),
(3, 1, 'GOING'),
(3, 2, 'NOT_GOING'),
(3, 4, 'GOING');

-- Insert test expenses
INSERT INTO expenses (group_id, paid_by, description, amount, currency, expense_date, category) VALUES
(1, 1, 'Volo Cagliari (4 persone)', 600.00, 'EUR', '2026-08-01', 'Trasporti'),
(1, 2, 'Supermercato', 80.00, 'EUR', '2026-08-01', 'Cibo'),
(1, 3, 'Hotel prima notte', 200.00, 'EUR', '2026-08-01', 'Alloggio'),
(1, 1, 'Benzina', 90.00, 'EUR', '2026-08-02', 'Trasporti'),
(1, 4, 'Cena ristorante', 120.00, 'EUR', '2026-08-04', 'Cibo'),
(2, 2, 'Hotel Cortina', 300.00, 'EUR', '2026-06-15', 'Alloggio'),
(2, 1, 'Benzina andata', 60.00, 'EUR', '2026-06-15', 'Trasporti');

-- Insert expense splits (equo per semplicità)
-- Gruppo Sardegna (4 persone: Mario, Laura, Giovanni, Sara)
INSERT INTO expense_splits (expense_id, user_id, share_amount) VALUES
-- Volo (600 / 4 = 150 each)
(1, 1, 150.00), (1, 2, 150.00), (1, 3, 150.00), (1, 4, 150.00),
-- Supermercato (80 / 4 = 20 each)
(2, 1, 20.00), (2, 2, 20.00), (2, 3, 20.00), (2, 4, 20.00),
-- Hotel (200 / 4 = 50 each)
(3, 1, 50.00), (3, 2, 50.00), (3, 3, 50.00), (3, 4, 50.00),
-- Benzina (90 / 4 = 22.50 each)
(4, 1, 22.50), (4, 2, 22.50), (4, 3, 22.50), (4, 4, 22.50),
-- Cena (120 / 4 = 30 each)
(5, 1, 30.00), (5, 2, 30.00), (5, 3, 30.00), (5, 4, 30.00);

-- Gruppo Weekend (3 persone: Laura, Mario, Giovanni)
INSERT INTO expense_splits (expense_id, user_id, share_amount) VALUES
-- Hotel (300 / 3 = 100 each)
(6, 1, 100.00), (6, 2, 100.00), (6, 3, 100.00),
-- Benzina (60 / 3 = 20 each)
(7, 1, 20.00), (7, 2, 20.00), (7, 3, 20.00);

-- Insert test documents
INSERT INTO documents (group_id, created_by, title, file_type, current_version) VALUES
(1, 1, 'Itinerario Sardegna', 'application/pdf', 1),
(1, 2, 'Biglietti Traghetto', 'application/pdf', 1),
(2, 2, 'Mappa Sentieri Dolomiti', 'image/jpeg', 1);

INSERT INTO document_versions (document_id, version_number, file_url, file_size, mime_type, uploaded_by, change_description) VALUES
(1, 1, 'https://storage.example.com/docs/itinerario-v1.pdf', 256000, 'application/pdf', 1, 'Prima versione'),
(2, 1, 'https://storage.example.com/docs/biglietti.pdf', 128000, 'application/pdf', 2, 'Upload iniziale'),
(3, 1, 'https://storage.example.com/docs/mappa.jpg', 512000, 'image/jpeg', 2, 'Mappa sentieri');

-- Insert test photos
INSERT INTO photos (user_id, group_id, title, description, file_url, thumbnail_url, file_size, mime_type) VALUES
(1, 1, 'Tramonto a Villasimius', 'Un bellissimo tramonto sulla spiaggia', 'https://storage.example.com/photos/tramonto.jpg', 'https://storage.example.com/thumbs/tramonto.jpg', 2048576, 'image/jpeg'),
(2, 1, 'Capo Testa', 'Vista panoramica', 'https://storage.example.com/photos/capo-testa.jpg', 'https://storage.example.com/thumbs/capo-testa.jpg', 3145728, 'image/jpeg'),
(3, 2, 'Tre Cime di Lavaredo', 'Montagne spettacolari', 'https://storage.example.com/photos/tre-cime.jpg', 'https://storage.example.com/thumbs/tre-cime.jpg', 4194304, 'image/jpeg'),
(4, 1, 'Cena tipica', 'Malloreddus alla campidanese', 'https://storage.example.com/photos/cena.jpg', 'https://storage.example.com/thumbs/cena.jpg', 1048576, 'image/jpeg');

-- Insert test likes
INSERT INTO likes (photo_id, user_id) VALUES
(1, 2), (1, 3), (1, 4),  -- 3 likes for photo 1
(2, 1), (2, 3),           -- 2 likes for photo 2
(3, 1), (3, 2),           -- 2 likes for photo 3
(4, 1), (4, 2), (4, 3);   -- 3 likes for photo 4

-- Insert test comments
INSERT INTO comments (user_id, entity_type, entity_id, text) VALUES
(2, 'PHOTO', 1, 'Bellissima foto! 😍'),
(3, 'PHOTO', 1, 'Che colori incredibili!'),
(1, 'PHOTO', 2, 'Complimenti Laura!'),
(4, 'EVENT', 2, 'Non vedo l''ora di andare in spiaggia!'),
(1, 'EVENT', 3, 'Portiamo scarpe da trekking'),
(2, 'DOCUMENT', 1, 'Ho aggiornato il programma del giorno 3');


-- =====================================================
-- MIGRATION COMPLETE! 
-- =====================================================

-- Verify installation
DO $$
DECLARE
    table_count INTEGER;
    view_count INTEGER;
    user_count INTEGER;
BEGIN
    -- Count tables
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    
    -- Count views
    SELECT COUNT(*) INTO view_count
    FROM information_schema.views 
    WHERE table_schema = 'public';
    
    -- Count users
    SELECT COUNT(*) INTO user_count FROM users;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🎉 DATABASE SETUP COMPLETE!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE '✅ Tables created: %', table_count;
    RAISE NOTICE '✅ Views created: %', view_count;
    RAISE NOTICE '✅ Sample users: %', user_count;
    RAISE NOTICE '✅ Sample groups: %', (SELECT COUNT(*) FROM groups);
    RAISE NOTICE '✅ Sample expenses: %', (SELECT COUNT(*) FROM expenses);
    RAISE NOTICE '✅ Sample photos: %', (SELECT COUNT(*) FROM photos);
    RAISE NOTICE '';
    RAISE NOTICE '📊 Test login credentials:';
    RAISE NOTICE '   Email: mario@example.com';
    RAISE NOTICE '   Password: Test123!';
    RAISE NOTICE '';
    RAISE NOTICE '🚀 Next steps:';
    RAISE NOTICE '   1. Check group_summary view';
    RAISE NOTICE '   2. Test expense balance calculation';
    RAISE NOTICE '   3. Start backend development';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
========================================
🎉 DATABASE SETUP COMPLETE!
========================================

✅ Tables created: 12
✅ Views created: 5
✅ Sample users: 4
✅ Sample groups: 3
✅ Sample expenses: 7
✅ Sample photos: 4

📊 Test login credentials:
   Email: mario@example.com
   Password: Test123!

🚀 Next steps:
   1. Check group_summary view
   2. Test expense balance calculation
   3. Start backend development

========================================
