SET intervalstyle = 'postgres';

SET TIMEZONE = 'UTC';

SELECT
    sa.NAME,
    sa.description,
    s.id,
    AVG(sd.temp_f) AS "TempF",
    AVG(sd.temp_c) AS "TempC",
    AVG(sd.relhum) AS "RH",
    s.dev_latency_us,
    EXTRACT(EPOCH FROM DATE_TRUNC('milliseconds', NOW() at TIME ZONE 'UTC')) - EXTRACT(EPOCH FROM DATE_TRUNC('milliseconds', sd.reading_at)) AS "Reading At",
    EXTRACT(EPOCH FROM DATE_TRUNC('milliseconds', NOW() at TIME ZONE 'UTC')) - EXTRACT(EPOCH FROM DATE_TRUNC('milliseconds', s.last_seen_at)) AS "Last Seen At",
    s.device,
    s.inserted_at AS "First Discovered"
FROM
    sensor_device s,
    sensor_alias sa,
    sensor_datapoint sd
WHERE
    sd.device_id = s.id
    AND sa.device_id = s.id
    AND sd.reading_at > (NOW() at TIME ZONE 'UTC' - INTERVAL '2 minutes')
GROUP BY
    sa.NAME,
    s.id,
    sd.reading_at,
    sa.description
ORDER BY
    sa.NAME,
    sd.reading_at DESC
