


ALTER TABLE auth_user_limits
    ALTER COLUMN weekly_requests_limit SET DEFAULT 10000,
    ALTER COLUMN weekly_requested_items_limit SET DEFAULT 100000;


-- Hike up the older limits
UPDATE auth_user_limits
SET weekly_requests_limit = DEFAULT
WHERE weekly_requests_limit < 10000;

UPDATE auth_user_limits
SET weekly_requested_items_limit = DEFAULT
WHERE weekly_requested_items_limit < 100000;



