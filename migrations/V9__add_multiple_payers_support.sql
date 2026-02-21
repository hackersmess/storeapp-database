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

-- Add comment for clarity
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
CREATE INDEX idx_activity_expenses_activity_id ON activity_expenses(activity_id);

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
    COALESCE(atc.total_cost, 0) AS total_cost,
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
    a.is_completed, a.description, a.created_at,
    u.name, u.avatar_url,
    atc.total_cost, atc.expense_count, atc.currency;

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
