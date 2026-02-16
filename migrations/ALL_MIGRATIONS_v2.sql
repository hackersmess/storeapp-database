-- =====================================================
-- ALL MIGRATIONS V2 - StoreApp Database
-- Description: Complete database setup with Itinerary Module
-- Execute this entire file in DBeaver to recreate DB from scratch
-- 
-- NEW in V2:
-- - itineraries (Itinerary module)
-- - activities (with Mapbox location support)
-- - activity_participants
-- - activity_expenses (prepared for future)
-- - expense_splits for activities (prepared for future)
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
        email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
    ),
    CONSTRAINT auth_method CHECK (
        google_id IS NOT NULL OR password_hash IS NOT NULL
    )
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_google_id ON users(google_id) WHERE google_id IS NOT NULL;

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

CREATE TABLE comments (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type VARCHAR(20) NOT NULL,
    entity_id BIGINT NOT NULL,
    text TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP,
    
    CONSTRAINT comment_not_empty CHECK (length(trim(text)) > 0),
    CONSTRAINT valid_entity_type CHECK (entity_type IN ('PHOTO'))
);

CREATE INDEX idx_comments_entity ON comments(entity_type, entity_id);
CREATE INDEX idx_comments_user_id ON comments(user_id);
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);

CREATE TABLE itineraries (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    start_date DATE,
    end_date DATE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT fk_itinerary_group 
        FOREIGN KEY (group_id) 
        REFERENCES groups(id) 
        ON DELETE CASCADE,
    CONSTRAINT unique_group_itinerary 
        UNIQUE (group_id),
    CONSTRAINT check_dates 
        CHECK (end_date IS NULL OR end_date >= start_date)
);

CREATE INDEX idx_itineraries_group_id ON itineraries(group_id);
CREATE INDEX idx_itineraries_dates ON itineraries(start_date, end_date);

CREATE TABLE activities (
    id BIGSERIAL PRIMARY KEY,
    itinerary_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    scheduled_date DATE,
    start_time TIME,
    end_time TIME,
    location_name VARCHAR(500),
    location_address VARCHAR(500),
    location_lat DECIMAL(10, 7),
    location_lng DECIMAL(10, 7),
    location_place_id VARCHAR(500),
    location_provider VARCHAR(50) DEFAULT 'mapbox',
    location_metadata JSONB,
    notes TEXT,
    is_completed BOOLEAN DEFAULT FALSE,
    display_order INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by BIGINT,
    
    -- Constraints
    CONSTRAINT fk_activity_itinerary 
        FOREIGN KEY (itinerary_id) 
        REFERENCES itineraries(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_activity_creator 
        FOREIGN KEY (created_by) 
        REFERENCES users(id) 
        ON DELETE SET NULL,
    CONSTRAINT check_activity_times 
        CHECK (end_time IS NULL OR end_time > start_time)
);

CREATE INDEX idx_activities_itinerary_id ON activities(itinerary_id);
CREATE INDEX idx_activities_scheduled_date ON activities(scheduled_date);
CREATE INDEX idx_activities_location ON activities(location_lat, location_lng);
CREATE INDEX idx_activities_display_order ON activities(itinerary_id, display_order);
CREATE INDEX idx_activities_metadata ON activities USING GIN (location_metadata);

CREATE TABLE activity_participants (
    id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL,
    group_member_id BIGINT NOT NULL,
    status VARCHAR(50) DEFAULT 'maybe',
    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT fk_participant_activity 
        FOREIGN KEY (activity_id) 
        REFERENCES activities(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_participant_member 
        FOREIGN KEY (group_member_id) 
        REFERENCES group_members(id) 
        ON DELETE CASCADE,
    CONSTRAINT unique_activity_participant 
        UNIQUE (activity_id, group_member_id),
    CONSTRAINT check_participant_status 
        CHECK (status IN ('confirmed', 'maybe', 'declined'))
);

CREATE INDEX idx_participants_activity ON activity_participants(activity_id);
CREATE INDEX idx_participants_member ON activity_participants(group_member_id);
CREATE INDEX idx_participants_status ON activity_participants(activity_id, status);

CREATE TABLE activity_expenses (
    id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL,
    description VARCHAR(255) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) DEFAULT 'EUR',
    paid_by BIGINT NOT NULL,
    paid_at TIMESTAMP DEFAULT NOW(),
    category VARCHAR(100),
    notes TEXT,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT fk_expense_activity 
        FOREIGN KEY (activity_id) 
        REFERENCES activities(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_expense_payer 
        FOREIGN KEY (paid_by) 
        REFERENCES group_members(id) 
        ON DELETE CASCADE,
    CONSTRAINT check_expense_amount 
        CHECK (amount >= 0)
);

CREATE INDEX idx_activity_expenses_activity ON activity_expenses(activity_id);
CREATE INDEX idx_activity_expenses_payer ON activity_expenses(paid_by);
CREATE INDEX idx_activity_expenses_category ON activity_expenses(category);

CREATE TABLE activity_expense_splits (
    id BIGSERIAL PRIMARY KEY,
    expense_id BIGINT NOT NULL,
    group_member_id BIGINT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    is_settled BOOLEAN DEFAULT FALSE,
    settled_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    -- Constraints
    CONSTRAINT fk_activity_split_expense 
        FOREIGN KEY (expense_id) 
        REFERENCES activity_expenses(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_activity_split_member 
        FOREIGN KEY (group_member_id) 
        REFERENCES group_members(id) 
        ON DELETE CASCADE,
    CONSTRAINT unique_activity_expense_split 
        UNIQUE (expense_id, group_member_id),
    CONSTRAINT check_activity_split_amount 
        CHECK (amount >= 0)
);

CREATE INDEX idx_activity_splits_expense ON activity_expense_splits(expense_id);
CREATE INDEX idx_activity_splits_member ON activity_expense_splits(group_member_id);
CREATE INDEX idx_activity_splits_settled ON activity_expense_splits(is_settled);

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
    COUNT(DISTINCT i.id) as itinerary_count,
    COALESCE(SUM(ex.amount), 0) as total_expenses,
    g.created_at
FROM groups g
JOIN users u ON g.created_by = u.id
LEFT JOIN group_members gm ON g.id = gm.group_id
LEFT JOIN photos p ON g.id = p.group_id
LEFT JOIN itineraries i ON g.id = i.group_id
LEFT JOIN expenses ex ON g.id = ex.group_id
GROUP BY g.id, u.name;

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

CREATE VIEW itinerary_summary AS
SELECT 
    i.id,
    i.group_id,
    i.name,
    i.description,
    i.start_date,
    i.end_date,
    g.name as group_name,
    COUNT(DISTINCT a.id) as activity_count,
    COUNT(DISTINCT a.id) FILTER (WHERE a.is_completed = TRUE) as completed_activities,
    COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'confirmed') as total_confirmations,
    i.created_at
FROM itineraries i
JOIN groups g ON i.group_id = g.id
LEFT JOIN activities a ON i.id = a.itinerary_id
LEFT JOIN activity_participants ap ON a.id = ap.activity_id
GROUP BY i.id, g.name;

CREATE VIEW activity_details AS
SELECT 
    a.id,
    a.itinerary_id,
    a.name,
    a.description,
    a.scheduled_date,
    a.start_time,
    a.end_time,
    a.location_name,
    a.location_address,
    a.location_lat,
    a.location_lng,
    a.location_provider,
    a.is_completed,
    a.display_order,
    u.name as created_by_name,
    COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'confirmed') as confirmed_count,
    COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'maybe') as maybe_count,
    COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'declined') as declined_count,
    a.created_at
FROM activities a
LEFT JOIN users u ON a.created_by = u.id
LEFT JOIN activity_participants ap ON a.id = ap.activity_id
GROUP BY a.id, u.name;

CREATE VIEW activity_calendar AS
SELECT 
    a.id,
    a.itinerary_id,
    i.group_id,
    a.name as title,
    a.description,
    a.scheduled_date as start,
    CASE 
        WHEN a.end_time IS NOT NULL THEN 
            a.scheduled_date + (a.end_time - a.start_time)
        ELSE 
            a.scheduled_date + INTERVAL '1 hour'
    END as end,
    a.start_time,
    a.end_time,
    EXTRACT(DOW FROM a.scheduled_date) as day_of_week,
    DATE(a.scheduled_date) as activity_date,
    a.location_name,
    a.location_lat,
    a.location_lng,
    a.is_completed,
    CASE 
        WHEN a.is_completed THEN 'completed'
        WHEN COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'confirmed') >= COUNT(DISTINCT gm.id) * 0.5 THEN 'confirmed'
        WHEN COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'declined') > COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'confirmed') THEN 'declined'
        ELSE 'pending'
    END as calendar_status,
    COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'confirmed') as confirmed_count,
    COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'maybe') as maybe_count,
    COUNT(DISTINCT ap.id) FILTER (WHERE ap.status = 'declined') as declined_count,
    COUNT(DISTINCT gm.id) as total_members,
    u.name as created_by_name,
    u.avatar_url as created_by_avatar
FROM activities a
JOIN itineraries i ON a.itinerary_id = i.id
LEFT JOIN users u ON a.created_by = u.id
LEFT JOIN activity_participants ap ON a.id = ap.activity_id
LEFT JOIN group_members gm ON i.group_id = gm.group_id
GROUP BY a.id, i.group_id, a.name, a.description, a.scheduled_date, a.start_time, a.end_time, 
         a.location_name, a.location_lat, a.location_lng, a.is_completed, u.name, u.avatar_url;

INSERT INTO users (email, name, bio, password_hash) VALUES
('mario@example.com', 'Mario Rossi', 'Fotografo amatoriale', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u'), -- password: Test123!
('laura@example.com', 'Laura Bianchi', 'Amante della natura', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u'),
('giovanni@example.com', 'Giovanni Verdi', 'Travel blogger', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u'),
('sara@example.com', 'Sara Neri', 'Designer', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYIxvVPaZ8u');

INSERT INTO groups (name, description, vacation_start_date, vacation_end_date, created_by) VALUES
('Sardegna 2026', 'Settimana in Sardegna', '2026-08-01', '2026-08-08', 1),
('Weekend Montagna', 'Weekend sulle Dolomiti', '2026-06-15', '2026-06-17', 2),
('Road Trip Toscana', 'Giro della Toscana', '2026-09-10', '2026-09-17', 3);

INSERT INTO group_members (group_id, user_id, role) VALUES
(1, 1, 'ADMIN'),
(1, 2, 'MEMBER'),
(1, 3, 'MEMBER'),
(1, 4, 'ADMIN'),
(2, 2, 'ADMIN'),
(2, 1, 'MEMBER'),
(2, 3, 'MEMBER'),
(3, 3, 'ADMIN'),
(3, 1, 'MEMBER'),
(3, 2, 'MEMBER');

INSERT INTO itineraries (group_id, name, description, start_date, end_date) VALUES
(1, 'Itinerario Sardegna', 'Tour completo della Sardegna del Sud', '2026-08-01', '2026-08-08'),
(2, 'Escursioni Dolomiti', 'Weekend trekking', '2026-06-15', '2026-06-17');

INSERT INTO activities (itinerary_id, name, description, scheduled_date, start_time, end_time, location_name, location_address, location_lat, location_lng, location_place_id, location_provider, display_order, created_by) VALUES
(1, 'Arrivo Aeroporto Cagliari', 'Check-in e ritiro auto', '2026-08-01', '14:00', '16:00', 'Aeroporto di Cagliari-Elmas', 'Via dei Trasvolatori, 09030 Elmas CA', 39.2515, 9.0543, 'dXJuOm1ieHBvaTpmYmQwNGRiZS0yYzlmLTQ3M2UtODUzZS0xMTEwMTU1NjY5NWY', 'mapbox', 1, 1),
(1, 'Spiaggia di Villasimius', 'Giornata al mare', '2026-08-02', '09:00', '18:00', 'Spiaggia del Riso', 'Villasimius, 09049 Villasimius SU', 39.1373, 9.5242, 'dXJuOm1ieHBvaTpmYmQwNGRiZS0yYzlmLTQ3M2UtODUzZS0xMTEwMTU1NjY5NWY', 'mapbox', 2, 1),
(1, 'Capo Testa', 'Escursione panoramica', '2026-08-03', '08:30', '13:00', 'Capo Testa', 'Santa Teresa Gallura, 07028 Santa Teresa Gallura SS', 41.2414, 9.1403, 'dXJuOm1ieHBvaTpmYmQwNGRiZS0yYzlmLTQ3M2UtODUzZS0xMTEwMTU1NjY5NWY', 'mapbox', 3, 4),
(1, 'Cena Tipica Sarda', 'Ristorante tradizionale', '2026-08-04', '20:00', '23:00', 'Sa Cardiga e Su Schironi', 'Via Armando Diaz, 09123 Cagliari CA', 39.2238, 9.1217, 'dXJuOm1ieHBvaTpmYmQwNGRiZS0yYzlmLTQ3M2UtODUzZS0xMTEwMTU1NjY5NWY', 'mapbox', 4, 2),
(2, 'Partenza da Milano', 'Viaggio in auto', '2026-06-15', '06:00', '10:00', 'Milano Centrale', 'Piazza Duca d''Aosta, 1, 20124 Milano MI', 45.4865, 9.2040, 'dXJuOm1ieHBvaTpmYmQwNGRiZS0yYzlmLTQ3M2UtODUzZS0xMTEwMTU1NjY5NWY', 'mapbox', 1, 2),
(2, 'Tre Cime di Lavaredo', 'Trekking classico', '2026-06-16', '07:00', '16:00', 'Rifugio Auronzo', 'Auronzo di Cadore, 32041 Auronzo di Cadore BL', 46.6185, 12.2958, 'dXJuOm1ieHBvaTpmYmQwNGRiZS0yYzlmLTQ3M2UtODUzZS0xMTEwMTU1NjY5NWY', 'mapbox', 2, 2);

INSERT INTO activity_participants (activity_id, group_member_id, status, notes) VALUES
(1, 1, 'confirmed', 'Porto io l''auto'),
(1, 2, 'confirmed', NULL),
(1, 3, 'confirmed', NULL),
(1, 4, 'confirmed', NULL),
(2, 1, 'confirmed', NULL),
(2, 2, 'confirmed', NULL),
(2, 3, 'maybe', 'Dipende dal meteo'),
(2, 4, 'confirmed', NULL),
(3, 1, 'confirmed', NULL),
(3, 2, 'declined', 'Preferisco rilassarmi'),
(3, 4, 'confirmed', 'Porto scarpe trekking'),
(4, 1, 'confirmed', NULL),
(4, 2, 'confirmed', NULL),
(4, 3, 'confirmed', NULL),
(4, 4, 'confirmed', NULL),
(5, 5, 'confirmed', NULL),
(5, 6, 'confirmed', NULL),
(5, 7, 'confirmed', NULL),
(6, 5, 'confirmed', NULL),
(6, 6, 'confirmed', NULL),
(6, 7, 'confirmed', NULL);

INSERT INTO expenses (group_id, paid_by, description, amount, currency, expense_date, category) VALUES
(1, 1, 'Volo Cagliari (4 persone)', 600.00, 'EUR', '2026-08-01', 'Trasporti'),
(1, 2, 'Supermercato', 80.00, 'EUR', '2026-08-01', 'Cibo'),
(1, 3, 'Hotel prima notte', 200.00, 'EUR', '2026-08-01', 'Alloggio'),
(1, 1, 'Benzina', 90.00, 'EUR', '2026-08-02', 'Trasporti'),
(1, 4, 'Cena ristorante', 120.00, 'EUR', '2026-08-04', 'Cibo'),
(2, 2, 'Hotel Cortina', 300.00, 'EUR', '2026-06-15', 'Alloggio'),
(2, 1, 'Benzina andata', 60.00, 'EUR', '2026-06-15', 'Trasporti');

INSERT INTO expense_splits (expense_id, user_id, share_amount) VALUES
(1, 1, 150.00), (1, 2, 150.00), (1, 3, 150.00), (1, 4, 150.00),
(2, 1, 20.00), (2, 2, 20.00), (2, 3, 20.00), (2, 4, 20.00),
(3, 1, 50.00), (3, 2, 50.00), (3, 3, 50.00), (3, 4, 50.00),
(4, 1, 22.50), (4, 2, 22.50), (4, 3, 22.50), (4, 4, 22.50),
(5, 1, 30.00), (5, 2, 30.00), (5, 3, 30.00), (5, 4, 30.00);

INSERT INTO expense_splits (expense_id, user_id, share_amount) VALUES
(6, 1, 100.00), (6, 2, 100.00), (6, 3, 100.00),
(7, 1, 20.00), (7, 2, 20.00), (7, 3, 20.00);

INSERT INTO photos (user_id, group_id, title, description, file_url, thumbnail_url, file_size, mime_type) VALUES
(1, 1, 'Tramonto a Villasimius', 'Un bellissimo tramonto sulla spiaggia', 'https://storage.example.com/photos/tramonto.jpg', 'https://storage.example.com/thumbs/tramonto.jpg', 2048576, 'image/jpeg'),
(2, 1, 'Capo Testa', 'Vista panoramica', 'https://storage.example.com/photos/capo-testa.jpg', 'https://storage.example.com/thumbs/capo-testa.jpg', 3145728, 'image/jpeg'),
(3, 2, 'Tre Cime di Lavaredo', 'Montagne spettacolari', 'https://storage.example.com/photos/tre-cime.jpg', 'https://storage.example.com/thumbs/tre-cime.jpg', 4194304, 'image/jpeg'),
(4, 1, 'Cena tipica', 'Malloreddus alla campidanese', 'https://storage.example.com/photos/cena.jpg', 'https://storage.example.com/thumbs/cena.jpg', 1048576, 'image/jpeg');

INSERT INTO likes (photo_id, user_id) VALUES
(1, 2), (1, 3), (1, 4),
(2, 1), (2, 3),
(3, 1), (3, 2), (3, 4),
(4, 2), (4, 3);

INSERT INTO comments (user_id, entity_type, entity_id, text) VALUES
(2, 'PHOTO', 1, 'Bellissima foto! 😍'),
(3, 'PHOTO', 1, 'Che colori incredibili!'),
(1, 'PHOTO', 2, 'Complimenti Laura!'),
(4, 'PHOTO', 3, 'Spettacolo puro! 🏔️'),
(2, 'PHOTO', 4, 'Che fame! 🍝');

DO $$
DECLARE
    table_count INTEGER;
    view_count INTEGER;
    user_count INTEGER;
    itinerary_count INTEGER;
    activity_count INTEGER;
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
    
    -- Count itineraries
    SELECT COUNT(*) INTO itinerary_count FROM itineraries;
    
    -- Count activities
    SELECT COUNT(*) INTO activity_count FROM activities;
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '🎉 DATABASE SETUP COMPLETE (V2)!';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE ' Tables created: %', table_count;
    RAISE NOTICE ' Views created: %', view_count;
    RAISE NOTICE ' Sample users: %', user_count;
    RAISE NOTICE ' Sample groups: %', (SELECT COUNT(*) FROM groups);
    RAISE NOTICE ' Sample expenses: %', (SELECT COUNT(*) FROM expenses);
    RAISE NOTICE ' Sample photos: %', (SELECT COUNT(*) FROM photos);
    RAISE NOTICE ' Sample itineraries: %', itinerary_count;
    RAISE NOTICE ' Sample activities: %', activity_count;
END $$;
