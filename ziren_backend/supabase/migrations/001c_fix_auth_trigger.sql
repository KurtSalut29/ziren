-- ============================================================
-- Migration 001c: Fix handle_new_auth_user trigger
--
-- v1: Fixed 'citizen' → 'resident' default role
-- v2: Added agency_id and badge_id from metadata (required for
--     Responder registration — badge_id NOT NULL constraint)
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
    v_role            TEXT;
    v_approval_status TEXT;
BEGIN
    v_role := COALESCE(NULLIF(NEW.raw_user_meta_data->>'role', ''), 'resident');

    v_approval_status := CASE
        WHEN v_role = 'responder' THEN 'pending'
        ELSE 'not_required'
    END;

    INSERT INTO public.users (
        id, email, full_name, role, approval_status, agency_id, badge_id
    )
    VALUES (
        NEW.id,
        NEW.email,
        COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
        v_role,
        v_approval_status,
        CASE
            WHEN NEW.raw_user_meta_data->>'agency_id' IS NOT NULL
             AND NEW.raw_user_meta_data->>'agency_id' != 'null'
             AND NEW.raw_user_meta_data->>'agency_id' != ''
            THEN (NEW.raw_user_meta_data->>'agency_id')::UUID
            ELSE NULL
        END,
        NULLIF(NEW.raw_user_meta_data->>'badge_id', '')
    )
    ON CONFLICT (id) DO NOTHING;
    RETURN NEW;
END;
$$;
