-- =====================================================
-- Script per aggiornare la view activity_calendar
-- Usa start_time e end_time invece di start e end
-- =====================================================

-- Elimina la view esistente
DROP VIEW IF EXISTS activity_calendar CASCADE;

-- Ricrea la view con i nomi corretti delle colonne
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

-- Verifica che la view sia stata creata correttamente
SELECT 'View activity_calendar ricreata con successo!' AS status;

-- Test: mostra le prime 5 righe
SELECT * FROM activity_calendar LIMIT 5;
