-- =====================================================
-- ALL MIGRATIONS V3 - StoreApp Database
-- Description: Complete database setup WITHOUT Itinerary entity (removed redundancy)
-- Execute this entire file in DBeaver to recreate DB from scratch
-- 
-- NEW in V3:
-- - REMOVED itineraries table (redundant with groups)
-- - activities now link directly to groups (not via itinerary)
-- - Simplified architecture: Group → Activities (no intermediate Itinerary)
-- - Groups now REQUIRE vacation dates (NOT NULL)
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

-- =====================================================
-- V2: Create GROUPS table
-- =====================================================

CREATE TABLE groups (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    vacation_start_date DATE NOT NULL,  -- NOW REQUIRED
    vacation_end_date DATE NOT NULL,    -- NOW REQUIRED
    cover_image_url VARCHAR(500),
    created_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT valid_vacation_dates CHECK (
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

-- =====================================================
-- V3: Create PHOTOS table
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
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type VARCHAR(20) NOT NULL,
    entity_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    -- Constraints
    CONSTRAINT unique_like UNIQUE (user_id, entity_type, entity_id),
    CONSTRAINT valid_entity_type CHECK (entity_type IN ('PHOTO'))
);

CREATE INDEX idx_photos_user_id ON photos(user_id);
CREATE INDEX idx_photos_group_id ON photos(group_id) WHERE group_id IS NOT NULL;
CREATE INDEX idx_photos_uploaded_at ON photos(uploaded_at DESC);
CREATE INDEX idx_likes_entity ON likes(entity_type, entity_id);
CREATE INDEX idx_likes_user_id ON likes(user_id);

-- =====================================================
-- V4: Create COMMENTS table
-- =====================================================

CREATE TABLE comments (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type VARCHAR(20) NOT NULL,
    entity_id BIGINT NOT NULL,
    text TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
    CONSTRAINT comment_not_empty CHECK (length(trim(text)) > 0),
    CONSTRAINT valid_entity_type CHECK (entity_type IN ('PHOTO'))
);

CREATE INDEX idx_comments_entity ON comments(entity_type, entity_id);
CREATE INDEX idx_comments_user_id ON comments(user_id);
CREATE INDEX idx_comments_created_at ON comments(created_at DESC);

-- =====================================================
-- V5: Create ACTIVITIES table (NO MORE ITINERARIES!)
-- Activities are now linked DIRECTLY to groups
-- =====================================================

CREATE TABLE activities (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL,  -- CHANGED: Direct link to group (was itinerary_id)
    name VARCHAR(255) NOT NULL,
    description TEXT,
    scheduled_date DATE,
    start_time TIME,
    end_time TIME,
    
    -- Location fields (provider-agnostic: Mapbox, Google Maps, OSM, etc.)
    location_name VARCHAR(500),
    location_address VARCHAR(500),
    location_lat DECIMAL(10, 7),
    location_lng DECIMAL(10, 7),
    location_place_id VARCHAR(500),
    location_provider VARCHAR(50) NOT NULL DEFAULT 'MAPBOX',
    location_metadata JSONB,
    
    -- Activity status
    is_completed BOOLEAN DEFAULT FALSE,
    display_order INTEGER DEFAULT 0,
    total_cost DECIMAL(10, 2) DEFAULT 0 NOT NULL,
    
    -- Audit fields
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by BIGINT,
    
    -- Constraints
    CONSTRAINT fk_activity_group 
        FOREIGN KEY (group_id) 
        REFERENCES groups(id) 
        ON DELETE CASCADE,
    CONSTRAINT fk_activity_creator 
        FOREIGN KEY (created_by) 
        REFERENCES users(id) 
        ON DELETE SET NULL,
    CONSTRAINT check_activity_times 
        CHECK (end_time IS NULL OR start_time IS NULL OR end_time > start_time),
    CONSTRAINT check_location_provider
        CHECK (location_provider IN ('MAPBOX', 'GOOGLE_MAPS', 'OPENSTREETMAP'))
);

-- Indexes for performance
CREATE INDEX idx_activities_group_id ON activities(group_id);
CREATE INDEX idx_activities_scheduled_date ON activities(scheduled_date);
CREATE INDEX idx_activities_location ON activities(location_lat, location_lng);
CREATE INDEX idx_activities_display_order ON activities(group_id, display_order);
CREATE INDEX idx_activities_completed ON activities(group_id, is_completed);
CREATE INDEX idx_activities_metadata ON activities USING GIN (location_metadata);
CREATE INDEX idx_activities_group_date ON activities(group_id, scheduled_date);  -- For calendar queries

-- =====================================================
-- V6: Create ACTIVITY PARTICIPANTS table
-- =====================================================

CREATE TABLE activity_participants (
    id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL,
    group_member_id BIGINT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'MAYBE',
    balance DECIMAL(10, 2) DEFAULT 0 NOT NULL,
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
        CHECK (status IN ('CONFIRMED', 'MAYBE', 'DECLINED'))
);

COMMENT ON COLUMN activity_participants.balance IS 
    'Balance for this participant: positive = should receive money, negative = owes money, zero = settled. Updated by backend when expenses are added/modified/deleted.';

CREATE INDEX idx_participants_activity ON activity_participants(activity_id);
CREATE INDEX idx_participants_member ON activity_participants(group_member_id);
CREATE INDEX idx_participants_status ON activity_participants(activity_id, status);

-- =====================================================
-- V7: Create ACTIVITY EXPENSES table
-- =====================================================

CREATE TABLE activity_expenses (
    id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL,
    description VARCHAR(255) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'EUR',
    paid_by BIGINT NOT NULL,  -- group_member_id
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
        CHECK (amount > 0)
);

CREATE INDEX idx_activity_expenses_activity ON activity_expenses(activity_id);
CREATE INDEX idx_activity_expenses_payer ON activity_expenses(paid_by);

-- =====================================================
-- V8: Create ACTIVITY EXPENSE SPLITS table
-- =====================================================

CREATE TABLE activity_expense_splits (
    id BIGSERIAL PRIMARY KEY,
    expense_id BIGINT NOT NULL,
    group_member_id BIGINT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    is_paid BOOLEAN DEFAULT FALSE,
    paid_at TIMESTAMP,
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
CREATE INDEX idx_activity_splits_paid ON activity_expense_splits(is_paid);

-- =====================================================
-- VIEWS: Useful views for common queries
-- =====================================================

-- View: Activity Calendar (optimized for frontend calendar display)
CREATE OR REPLACE VIEW activity_calendar AS
SELECT 
    a.id,
    a.group_id,
    a.name AS title,
    a.scheduled_date AS activity_date,
    a.start_time,
    a.end_time,
    TO_CHAR(a.scheduled_date, 'Day') AS day_of_week,
    a.location_name,
    a.location_lat,
    a.location_lng,
    a.is_completed,
    a.description,
    CASE 
        WHEN a.is_completed THEN 'completed'
        WHEN COUNT(CASE WHEN ap.status = 'CONFIRMED' THEN 1 END) > 0 THEN 'confirmed'
        WHEN COUNT(CASE WHEN ap.status = 'DECLINED' THEN 1 END) = COUNT(ap.id) THEN 'declined'
        ELSE 'pending'
    END AS calendar_status,
    COUNT(CASE WHEN ap.status = 'CONFIRMED' THEN 1 END) AS confirmed_count,
    COUNT(CASE WHEN ap.status = 'MAYBE' THEN 1 END) AS maybe_count,
    COUNT(CASE WHEN ap.status = 'DECLINED' THEN 1 END) AS declined_count,
    COUNT(DISTINCT ap.id) AS total_members,
    u.name AS creator_name,
    u.avatar_url AS creator_avatar
FROM activities a
LEFT JOIN activity_participants ap ON a.id = ap.activity_id
LEFT JOIN users u ON a.created_by = u.id
GROUP BY a.id, a.group_id, a.name, a.scheduled_date, a.start_time, a.end_time, 
         a.location_name, a.location_lat, a.location_lng, a.is_completed, 
         a.description, u.name, u.avatar_url;

-- =====================================================
-- SEED DATA (Optional - for development/testing)
-- =====================================================

-- Insert test users
INSERT INTO users (email, name, bio, password_hash) VALUES
('admin@storeapp.com', 'Admin User', 'System administrator', 'hashed_password_1'),
('john@example.com', 'John Doe', 'Travel enthusiast', 'hashed_password_2'),
('jane@example.com', 'Jane Smith', 'Adventure seeker', 'hashed_password_3');

-- Insert test groups (with REQUIRED dates!)
INSERT INTO groups (name, description, vacation_start_date, vacation_end_date, created_by) VALUES
('Vacanza Roma 2024', 'Una settimana nella città eterna', '2024-06-15', '2024-06-22', 1),
('Weekend Firenze', 'Un fine settimana in Toscana', '2024-07-05', '2024-07-07', 2);

-- Insert group members
INSERT INTO group_members (group_id, user_id, role) VALUES
(1, 1, 'ADMIN'),
(1, 2, 'MEMBER'),
(1, 3, 'MEMBER'),
(2, 2, 'ADMIN'),
(2, 3, 'MEMBER');

-- Insert test activities (NO itinerary_id, direct group_id!)
INSERT INTO activities (group_id, name, description, scheduled_date, start_time, end_time, location_name, location_lat, location_lng, is_completed, display_order, created_by) VALUES
(1, 'Visita Colosseo', 'Tour guidato del Colosseo e Foro Romano', '2024-06-16', '09:00', '12:00', 'Colosseo', 41.8902, 12.4922, false, 0, 1),
(1, 'Pranzo a Trastevere', 'Pranzo tipico romano', '2024-06-16', '13:00', '15:00', 'Trastevere', 41.8893, 12.4698, false, 1, 1),
(1, 'Fontana di Trevi', 'Visita alla Fontana di Trevi', '2024-06-17', '10:00', '11:00', 'Fontana di Trevi', 41.9009, 12.4833, false, 2, 1),
(2, 'Uffizi', 'Visita Galleria degli Uffizi', '2024-07-05', '14:00', '17:00', 'Galleria degli Uffizi', 43.7687, 11.2558, false, 0, 2);

-- Insert activity participants
INSERT INTO activity_participants (activity_id, group_member_id, status) VALUES
(1, 1, 'CONFIRMED'),
(1, 2, 'CONFIRMED'),
(1, 3, 'MAYBE'),
(2, 1, 'CONFIRMED'),
(2, 2, 'DECLINED');

-- =====================================================
-- SUMMARY
-- =====================================================
-- ✅ Tables Created:
--    - users
--    - groups (with REQUIRED vacation dates)
--    - group_members
--    - photos
--    - likes
--    - comments
--    - activities (linked to groups, NOT itineraries) + total_cost column
--    - activity_participants
--    - activity_expenses
--    - activity_expense_splits (with is_payer and paid_amount for multiple payers)
--
-- ✅ Views Created:
--    - activity_calendar (optimized calendar view with total costs)
--    - activity_expense_summary (expense details with multiple payers)
--    - activity_debt_summary (who owes whom)
--    - activity_total_costs (aggregate costs per activity)
--
-- ✅ Functions Created:
--    - recalculate_activity_total_cost(activity_id) - recalculate and update total_cost
--
-- ❌ REMOVED from V2:
--    - itineraries table (redundant!)
--
-- ✅ Architecture:
--    Group → Activities (direct link, no intermediate itinerary)
--    Activities → Expenses → Splits (with multiple payers support)
--
-- Ready to use! 🚀
-- =====================================================

-- =====================================================
-- V9: Add support for multiple payers in activity expenses
-- =====================================================

-- Step 1: Add total_cost to activities table (managed by backend)
ALTER TABLE activities 
    ADD COLUMN total_cost DECIMAL(10, 2) DEFAULT 0 NOT NULL;

COMMENT ON COLUMN activities.total_cost IS 
    'Total cost of all expenses for this activity. Updated by backend when expenses are added/modified/deleted.';

-- Step 2: Add balance to activity_participants (managed by backend)
ALTER TABLE activity_participants
    ADD COLUMN balance DECIMAL(10, 2) DEFAULT 0 NOT NULL;

COMMENT ON COLUMN activity_participants.balance IS 
    'Balance for this participant: positive = should receive money, negative = owes money, zero = settled. Updated by backend when expenses are added/modified/deleted.';

-- Step 3: Add columns to support multiple payers in expense splits
ALTER TABLE activity_expense_splits 
    ADD COLUMN is_payer BOOLEAN DEFAULT FALSE,
    ADD COLUMN paid_amount DECIMAL(10, 2) DEFAULT 0;

-- Add check constraint: if is_payer=true, paid_amount must be > 0
ALTER TABLE activity_expense_splits
    ADD CONSTRAINT check_payer_amount 
    CHECK (
        (is_payer = FALSE AND paid_amount = 0) OR
        (is_payer = TRUE AND paid_amount > 0)
    );

-- Add comments for clarity
COMMENT ON COLUMN activity_expense_splits.is_payer IS 
    'TRUE if this member paid for the expense (can have multiple payers per expense)';
COMMENT ON COLUMN activity_expense_splits.paid_amount IS 
    'Amount paid by this member (only if is_payer=true)';
COMMENT ON COLUMN activity_expense_splits.amount IS 
    'Amount this member owes/should receive (calculated by split algorithm)';

-- Add index for efficient payer queries
CREATE INDEX idx_activity_splits_payer ON activity_expense_splits(expense_id, is_payer) 
    WHERE is_payer = TRUE;

-- =====================================================
-- Updated View: Activity Expense Summary with multiple payers
-- =====================================================

CREATE OR REPLACE VIEW activity_expense_summary AS
SELECT 
    ae.id AS expense_id,
    ae.activity_id,
    ae.description,
    ae.currency,
    ae.created_at,
    -- Total amount paid (sum of all payers)
    COALESCE(SUM(aes.paid_amount) FILTER (WHERE aes.is_payer = TRUE), 0) AS total_paid,
    -- Number of payers
    COUNT(DISTINCT aes.group_member_id) FILTER (WHERE aes.is_payer = TRUE) AS payer_count,
    -- Number of participants (including payers who might also owe)
    COUNT(DISTINCT aes.group_member_id) AS participant_count,
    -- Payers list (JSON array)
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'member_id', gm.id,
            'user_name', u.name,
            'paid_amount', aes.paid_amount
        ) ORDER BY aes.paid_amount DESC
    ) FILTER (WHERE aes.is_payer = TRUE) AS payers
FROM activity_expenses ae
LEFT JOIN activity_expense_splits aes ON ae.id = aes.expense_id
LEFT JOIN group_members gm ON aes.group_member_id = gm.id
LEFT JOIN users u ON gm.user_id = u.id
GROUP BY ae.id, ae.activity_id, ae.description, ae.currency, ae.created_at;

-- =====================================================
-- Helper View: Who owes whom (debts calculation)
-- =====================================================

CREATE OR REPLACE VIEW activity_debt_summary AS
WITH expense_totals AS (
    SELECT 
        aes.expense_id,
        ae.activity_id,
        SUM(aes.paid_amount) FILTER (WHERE aes.is_payer = TRUE) AS total_paid,
        COUNT(DISTINCT aes.group_member_id) AS participant_count
    FROM activity_expense_splits aes
    JOIN activity_expenses ae ON aes.expense_id = ae.id
    GROUP BY aes.expense_id, ae.activity_id
),
member_balances AS (
    SELECT 
        aes.group_member_id,
        ae.activity_id,
        -- What they paid minus what they owe
        COALESCE(SUM(aes.paid_amount), 0) - COALESCE(SUM(aes.amount), 0) AS balance
    FROM activity_expense_splits aes
    JOIN activity_expenses ae ON aes.expense_id = ae.id
    GROUP BY aes.group_member_id, ae.activity_id
)
SELECT 
    mb.activity_id,
    mb.group_member_id,
    u.name AS member_name,
    mb.balance,
    CASE 
        WHEN mb.balance > 0 THEN 'CREDITOR'
        WHEN mb.balance < 0 THEN 'DEBTOR'
        ELSE 'SETTLED'
    END AS status
FROM member_balances mb
JOIN group_members gm ON mb.group_member_id = gm.id
JOIN users u ON gm.user_id = u.id
ORDER BY mb.activity_id, mb.balance DESC;

-- =====================================================
-- DEPRECATION: Mark old paid_by column as deprecated
-- =====================================================

COMMENT ON COLUMN activity_expenses.paid_by IS 
    'DEPRECATED: Use activity_expense_splits.is_payer instead. Kept for backward compatibility.';

-- Note: We keep the paid_by column for now to avoid breaking existing code
-- It can be removed in a future migration after updating all application code

-- =====================================================
-- View: Activity Total Costs (aggregate all expenses per activity)
-- =====================================================

CREATE OR REPLACE VIEW activity_total_costs AS
SELECT 
    ae.activity_id,
    -- Total cost of all expenses for this activity
    COALESCE(SUM(aes.paid_amount) FILTER (WHERE aes.is_payer = TRUE), 0) AS total_cost,
    -- Number of expenses
    COUNT(DISTINCT ae.id) AS expense_count,
    -- Currency (assuming all expenses use same currency per activity)
    MAX(ae.currency) AS currency,
    -- Breakdown by expense
    JSON_AGG(
        JSON_BUILD_OBJECT(
            'expense_id', ae.id,
            'description', ae.description,
            'total_paid', COALESCE(SUM(aes.paid_amount) FILTER (WHERE aes.is_payer = TRUE), 0)
        ) ORDER BY ae.created_at
    ) AS expense_breakdown
FROM activity_expenses ae
LEFT JOIN activity_expense_splits aes ON ae.id = aes.expense_id
GROUP BY ae.activity_id;

-- Add index for fast lookup
CREATE INDEX IF NOT EXISTS idx_activity_expenses_activity_id ON activity_expenses(activity_id);

-- =====================================================
-- Enhanced View: Activity Calendar WITH total costs
-- =====================================================

DROP VIEW IF EXISTS activity_calendar;

CREATE OR REPLACE VIEW activity_calendar AS
SELECT 
    a.id,
    a.group_id,
    a.name AS title,
    a.scheduled_date AS activity_date,
    a.start_time,
    a.end_time,
    TO_CHAR(a.scheduled_date, 'Day') AS day_of_week,
    a.location_name,
    a.location_address,
    a.location_lat,
    a.location_lng,
    a.is_completed,
    a.description,
    -- Participant status
    CASE 
        WHEN a.is_completed THEN 'completed'
        WHEN COUNT(CASE WHEN ap.status = 'CONFIRMED' THEN 1 END) > 0 THEN 'confirmed'
        WHEN COUNT(CASE WHEN ap.status = 'DECLINED' THEN 1 END) = COUNT(ap.id) THEN 'declined'
        ELSE 'pending'
    END AS calendar_status,
    COUNT(CASE WHEN ap.status = 'CONFIRMED' THEN 1 END) AS confirmed_count,
    COUNT(CASE WHEN ap.status = 'MAYBE' THEN 1 END) AS maybe_count,
    COUNT(CASE WHEN ap.status = 'DECLINED' THEN 1 END) AS declined_count,
    COUNT(DISTINCT ap.id) AS total_participants,
    -- Cost information (NEW!)
    a.total_cost,
    COALESCE(atc.expense_count, 0) AS expense_count,
    COALESCE(atc.currency, 'EUR') AS currency,
    -- Creator info
    u.name AS creator_name,
    u.avatar_url AS creator_avatar,
    a.created_at
FROM activities a
LEFT JOIN activity_participants ap ON a.id = ap.activity_id
LEFT JOIN activity_total_costs atc ON a.id = atc.activity_id
LEFT JOIN users u ON a.created_by = u.id
GROUP BY 
    a.id, a.group_id, a.name, a.scheduled_date, a.start_time, a.end_time, 
    a.location_name, a.location_address, a.location_lat, a.location_lng, 
    a.is_completed, a.description, a.created_at, a.total_cost,
    u.name, u.avatar_url,
    atc.expense_count, atc.currency;

COMMENT ON VIEW activity_calendar IS 
    'Optimized view for calendar display with participant counts and total costs per activity';

-- =====================================================
-- Helper Function: Recalculate activity total_cost
-- =====================================================

CREATE OR REPLACE FUNCTION recalculate_activity_total_cost(p_activity_id BIGINT)
RETURNS DECIMAL(10, 2)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total DECIMAL(10, 2);
BEGIN
    -- Calculate total from all expense splits where is_payer = TRUE
    SELECT COALESCE(SUM(aes.paid_amount), 0)
    INTO v_total
    FROM activity_expenses ae
    JOIN activity_expense_splits aes ON ae.id = aes.expense_id
    WHERE ae.activity_id = p_activity_id
      AND aes.is_payer = TRUE;
    
    -- Update the activities table
    UPDATE activities
    SET total_cost = v_total,
        updated_at = NOW()
    WHERE id = p_activity_id;
    
    RETURN v_total;
END;
$$;

COMMENT ON FUNCTION recalculate_activity_total_cost IS 
    'Recalculates and updates the total_cost for an activity. Called by backend after expense changes.';

-- =====================================================
-- Helper Function: Recalculate participant balances
-- =====================================================

CREATE OR REPLACE FUNCTION recalculate_participant_balances(p_activity_id BIGINT)
RETURNS TABLE(group_member_id BIGINT, balance DECIMAL(10, 2))
LANGUAGE plpgsql
AS $$
BEGIN
    -- Calculate balances for all participants in this activity
    -- Balance = What they paid - What they owe
    RETURN QUERY
    WITH participant_balances AS (
        SELECT 
            ap.group_member_id,
            COALESCE(SUM(aes.paid_amount) FILTER (WHERE aes.is_payer = TRUE), 0) 
            - COALESCE(SUM(aes.amount), 0) AS calc_balance
        FROM activity_participants ap
        LEFT JOIN activity_expense_splits aes ON ap.group_member_id = aes.group_member_id
        LEFT JOIN activity_expenses ae ON aes.expense_id = ae.id AND ae.activity_id = ap.activity_id
        WHERE ap.activity_id = p_activity_id
        GROUP BY ap.group_member_id
    )
    UPDATE activity_participants ap
    SET balance = pb.calc_balance,
        updated_at = NOW()
    FROM participant_balances pb
    WHERE ap.group_member_id = pb.group_member_id
      AND ap.activity_id = p_activity_id
    RETURNING ap.group_member_id, ap.balance;
END;
$$;

COMMENT ON FUNCTION recalculate_participant_balances IS 
    'Recalculates and updates the balance for all participants in an activity. Called by backend after expense changes. Returns the updated balances.';
