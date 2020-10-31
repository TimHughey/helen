SELECT
    p.id,
    p.device,
    p.HOST,
    p.duty,
    p.duty_max,
    p.duty_min,
    p.dev_latency_us,
    p.last_seen_at,
    p.discovered_at,
    p.last_cmd_at,
    p.inserted_at,
    p.updated_at
FROM
    pwm_device p
WHERE
    p.id NOT IN (
        SELECT
            id
        FROM
            pwm_alias)
    ORDER BY
        p.id ASC
