-- =====================================================
-- ALL MIGRATIONS V5 - StoreApp Database
-- Description: Complete database setup WITH Activities SINGLE TABLE Inheritance
-- Execute this entire file in DBeaver to recreate DB from scratch
-- 
-- NEW in V5:
-- - Activities use SINGLE TABLE inheritance (more performant, cleaner queries)
-- - Multi-day activities support (start_date + end_date)
-- - Location provider configured globally (not in DB)
-- - Event for single-location activities (restaurants, museums, hotels)
-- - Trip for travel with origin/destination (flights, trains, car trips)
-- - NO JOINS needed for queries - everything in one table!
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
    vacation_start_date DATE NOT NULL,
    vacation_end_date DATE NOT NULL,
    cover_image_url VARCHAR(500),
    created_by BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
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
    
    CONSTRAINT valid_mime_type CHECK (
        mime_type IN ('image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic')
    ),
    CONSTRAINT valid_file_size CHECK (
        file_size > 0 AND file_size <= 52428800
    )
);

CREATE TABLE likes (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    entity_type VARCHAR(20) NOT NULL,
    entity_id BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    
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
-- V5: ENUM types removed - using VARCHAR for compatibility
-- =====================================================
-- Hibernate @Enumerated(EnumType.STRING) funziona meglio con VARCHAR
-- invece di PostgreSQL native ENUM types

-- =====================================================
-- V6: Create ACTIVITIES table (SINGLE TABLE inheritance)
-- =====================================================

CREATE TABLE activities (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    
    -- Date/time fields with multi-day support (all required)
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    start_time TIME NOT NULL,
    end_time TIME NOT NULL,
    
    -- Discriminator for inheritance (EVENT or TRIP)
    activity_type VARCHAR(50) NOT NULL DEFAULT 'EVENT',
    
    -- Common activity fields
    is_completed BOOLEAN DEFAULT FALSE,
    display_order INTEGER DEFAULT 0,
    total_cost DECIMAL(10, 2) DEFAULT 0,
    
    -- EVENT-specific fields (NULL if activity_type = 'TRIP')
    event_location_name VARCHAR(500),
    event_location_address VARCHAR(500),
    event_location_latitude DECIMAL(10, 7),
    event_location_longitude DECIMAL(10, 7),
    event_location_place_id VARCHAR(500),
    event_location_metadata JSONB,
    event_category VARCHAR(50),
    event_booking_url VARCHAR(1000),
    event_booking_reference VARCHAR(255),
    event_reservation_time TIME,
    
    -- TRIP-specific fields (NULL if activity_type = 'EVENT')
    trip_origin_name VARCHAR(500),
    trip_origin_address VARCHAR(500),
    trip_origin_latitude DECIMAL(10, 7),
    trip_origin_longitude DECIMAL(10, 7),
    trip_origin_place_id VARCHAR(500),
    trip_origin_metadata JSONB,
    trip_destination_name VARCHAR(500),
    trip_destination_address VARCHAR(500),
    trip_destination_latitude DECIMAL(10, 7),
    trip_destination_longitude DECIMAL(10, 7),
    trip_destination_place_id VARCHAR(500),
    trip_destination_metadata JSONB,
    trip_transport_mode VARCHAR(50),
    trip_departure_time TIME,
    trip_arrival_time TIME,
    trip_booking_reference VARCHAR(255),
    
    -- Audit fields
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    created_by BIGINT,
    
    -- Foreign Keys
    CONSTRAINT fk_activity_group FOREIGN KEY (group_id) REFERENCES groups(id) ON DELETE CASCADE,
    CONSTRAINT fk_activity_creator FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL,
    
    -- General constraints
    CONSTRAINT check_activity_times CHECK (end_time IS NULL OR start_time IS NULL OR end_time > start_time),
    CONSTRAINT check_activity_dates CHECK (end_date IS NULL OR end_date >= start_date),
    CONSTRAINT check_activity_type CHECK (activity_type IN ('EVENT', 'TRIP')),
    
    -- EVENT-specific constraints
    CONSTRAINT check_event_coordinates CHECK (
        activity_type != 'EVENT' OR event_location_latitude IS NULL OR 
        (event_location_latitude BETWEEN -90 AND 90 AND event_location_longitude BETWEEN -180 AND 180)
    ),
    
    -- TRIP-specific constraints
    CONSTRAINT check_trip_origin_coords CHECK (
        activity_type != 'TRIP' OR trip_origin_latitude IS NULL OR 
        (trip_origin_latitude BETWEEN -90 AND 90 AND trip_origin_longitude BETWEEN -180 AND 180)
    ),
    CONSTRAINT check_trip_dest_coords CHECK (
        activity_type != 'TRIP' OR trip_destination_latitude IS NULL OR 
        (trip_destination_latitude BETWEEN -90 AND 90 AND trip_destination_longitude BETWEEN -180 AND 180)
    ),
    CONSTRAINT check_trip_times CHECK (
        activity_type != 'TRIP' OR trip_departure_time IS NULL OR trip_arrival_time IS NULL OR 
        trip_arrival_time > trip_departure_time
    )
);

-- Indexes for performance
CREATE INDEX idx_activities_group_id ON activities(group_id);
CREATE INDEX idx_activities_start_date ON activities(start_date);
CREATE INDEX idx_activities_end_date ON activities(end_date);
CREATE INDEX idx_activities_date_range ON activities(group_id, start_date, end_date);
CREATE INDEX idx_activities_type ON activities(activity_type);
CREATE INDEX idx_activities_display_order ON activities(group_id, display_order);
CREATE INDEX idx_activities_completed ON activities(group_id, is_completed);

-- Indexes for EVENT-specific queries
CREATE INDEX idx_activities_event_location ON activities(event_location_latitude, event_location_longitude) 
    WHERE activity_type = 'EVENT';
CREATE INDEX idx_activities_event_category ON activities(event_category) 
    WHERE activity_type = 'EVENT';
CREATE INDEX idx_activities_event_metadata ON activities USING GIN (event_location_metadata) 
    WHERE activity_type = 'EVENT';

-- Indexes for TRIP-specific queries
CREATE INDEX idx_activities_trip_origin ON activities(trip_origin_latitude, trip_origin_longitude) 
    WHERE activity_type = 'TRIP';
CREATE INDEX idx_activities_trip_dest ON activities(trip_destination_latitude, trip_destination_longitude) 
    WHERE activity_type = 'TRIP';
CREATE INDEX idx_activities_trip_transport ON activities(trip_transport_mode) 
    WHERE activity_type = 'TRIP';

-- =====================================================
-- V7: Create ACTIVITY_PARTICIPANTS table
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
    
    CONSTRAINT fk_participant_activity FOREIGN KEY (activity_id) REFERENCES activities(id) ON DELETE CASCADE,
    CONSTRAINT fk_participant_member FOREIGN KEY (group_member_id) REFERENCES group_members(id) ON DELETE CASCADE,
    CONSTRAINT unique_activity_participant UNIQUE (activity_id, group_member_id),
    CONSTRAINT check_participant_status CHECK (status IN ('CONFIRMED', 'MAYBE', 'DECLINED'))
);

CREATE INDEX idx_participants_activity ON activity_participants(activity_id);
CREATE INDEX idx_participants_member ON activity_participants(group_member_id);
CREATE INDEX idx_participants_status ON activity_participants(activity_id, status);

-- =====================================================
-- V8: Create ACTIVITY_EXPENSES tables
-- =====================================================

CREATE TABLE activity_expenses (
    id BIGSERIAL PRIMARY KEY,
    activity_id BIGINT NOT NULL,
    description VARCHAR(255) NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    currency VARCHAR(3) NOT NULL DEFAULT 'EUR',
    paid_by BIGINT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT fk_expense_activity FOREIGN KEY (activity_id) REFERENCES activities(id) ON DELETE CASCADE,
    CONSTRAINT fk_expense_payer FOREIGN KEY (paid_by) REFERENCES group_members(id) ON DELETE RESTRICT,
    CONSTRAINT check_expense_amount CHECK (amount > 0)
);

CREATE INDEX idx_expenses_activity ON activity_expenses(activity_id);
CREATE INDEX idx_expenses_payer ON activity_expenses(paid_by);

CREATE TABLE activity_expense_splits (
    id BIGSERIAL PRIMARY KEY,
    expense_id BIGINT NOT NULL,
    group_member_id BIGINT NOT NULL,
    amount DECIMAL(10, 2) NOT NULL,
    is_paid BOOLEAN DEFAULT FALSE NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW(),
    
    CONSTRAINT fk_split_expense FOREIGN KEY (expense_id) REFERENCES activity_expenses(id) ON DELETE CASCADE,
    CONSTRAINT fk_split_member FOREIGN KEY (group_member_id) REFERENCES group_members(id) ON DELETE CASCADE,
    CONSTRAINT unique_expense_member UNIQUE (expense_id, group_member_id),
    CONSTRAINT check_split_amount CHECK (amount >= 0)
);

CREATE INDEX idx_splits_expense ON activity_expense_splits(expense_id);
CREATE INDEX idx_splits_member ON activity_expense_splits(group_member_id);

-- =====================================================
-- V9: Create VIEWS for easier querying
-- =====================================================

-- View for activity calendar - SUPER SIMPLE now with SINGLE TABLE!
CREATE OR REPLACE VIEW activity_calendar AS
SELECT 
    a.id,
    a.group_id,
    a.name as title,
    a.description,
    a.start_time,
    a.end_time,
    EXTRACT(ISODOW FROM a.start_date) as day_of_week,
    a.start_date as activity_date,
    CASE 
        WHEN a.activity_type = 'EVENT' THEN a.event_location_name
        WHEN a.activity_type = 'TRIP' THEN a.trip_origin_name || ' → ' || a.trip_destination_name
    END as location_name,
    CASE 
        WHEN a.activity_type = 'EVENT' THEN a.event_location_latitude
        WHEN a.activity_type = 'TRIP' THEN a.trip_origin_latitude
    END as location_lat,
    CASE 
        WHEN a.activity_type = 'EVENT' THEN a.event_location_longitude
        WHEN a.activity_type = 'TRIP' THEN a.trip_origin_longitude
    END as location_lng,
    a.is_completed,
    CASE 
        WHEN a.is_completed THEN 'completed'
        WHEN COUNT(CASE WHEN ap.status = 'CONFIRMED' THEN 1 END) > 0 THEN 'confirmed'
        WHEN COUNT(CASE WHEN ap.status = 'DECLINED' THEN 1 END) = COUNT(ap.id) AND COUNT(ap.id) > 0 THEN 'declined'
        ELSE 'pending'
    END as calendar_status,
    COALESCE(COUNT(CASE WHEN ap.status = 'CONFIRMED' THEN 1 END), 0) as confirmed_count,
    COALESCE(COUNT(CASE WHEN ap.status = 'MAYBE' THEN 1 END), 0) as maybe_count,
    COALESCE(COUNT(CASE WHEN ap.status = 'DECLINED' THEN 1 END), 0) as declined_count,
    COALESCE(COUNT(ap.id), 0) as total_members,
    u.name as creator_name,
    u.avatar_url as creator_avatar
FROM activities a
LEFT JOIN activity_participants ap ON a.id = ap.activity_id
LEFT JOIN users u ON a.created_by = u.id
GROUP BY a.id, a.group_id, a.name, a.description, a.start_time, a.end_time, 
         a.start_date, a.is_completed, a.activity_type,
         a.event_location_name, a.event_location_latitude, a.event_location_longitude,
         a.trip_origin_name, a.trip_destination_name, a.trip_origin_latitude, a.trip_origin_longitude,
         u.name, u.avatar_url;

-- =====================================================
-- DATABASE SETUP COMPLETE
-- =====================================================
