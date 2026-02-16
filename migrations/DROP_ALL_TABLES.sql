-- =====================================================
-- DROP ALL TABLES - StoreApp Database
-- Description: Removes all existing database objects
-- Execute this file BEFORE running ALL_MIGRATIONS_v2.sql
-- 
-- WARNING: This will DELETE ALL DATA permanently!
-- =====================================================

-- Method 1: Drop and recreate the entire public schema (FASTEST)
DROP SCHEMA IF EXISTS public CASCADE;
CREATE SCHEMA public;

-- Grant default permissions
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;

-- Verify cleanup
DO $$
DECLARE
    table_count INTEGER;
    view_count INTEGER;
    function_count INTEGER;
BEGIN
    -- Count remaining tables
    SELECT COUNT(*) INTO table_count
    FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE';
    
    -- Count remaining views
    SELECT COUNT(*) INTO view_count
    FROM information_schema.views 
    WHERE table_schema = 'public';
    
    -- Count remaining functions
    SELECT COUNT(*) INTO function_count
    FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public';
    
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
    RAISE NOTICE '  DATABASE CLEANUP COMPLETE';
    RAISE NOTICE '========================================';
    RAISE NOTICE '';
    RAISE NOTICE ' Remaining tables: %', table_count;
    RAISE NOTICE ' Remaining views: %', view_count;
    RAISE NOTICE ' Remaining functions: %', function_count;
    RAISE NOTICE '';
    RAISE NOTICE ' Next step: Execute ALL_MIGRATIONS_v2.sql';
    RAISE NOTICE '';
    RAISE NOTICE '========================================';
END $$;
