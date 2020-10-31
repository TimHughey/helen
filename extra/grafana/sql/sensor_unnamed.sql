SELECT
    s.id,
    s.device,
    s.HOST,
    s.dev_latency_us,
    s.last_seen_at,
    s.discovered_at,
    s.inserted_at,
    s.updated_at
FROM
    sensor_device s
WHERE
    s.id NOT IN (
        SELECT
            id
        FROM
            sensor_alias)
    ORDER BY
        s.id ASC
