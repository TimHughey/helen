SET intervalstyle = 'postgres';
SET timezone='UTC';
  SELECT s.id, sa.name,
  AVG(sd.relhum) as "RH%",
  s.dev_latency_us,
  EXTRACT(EPOCH from DATE_TRUNC('milliseconds', now() at TIME ZONE 'UTC')) - EXTRACT(EPOCH FROM  DATE_TRUNC('milliseconds', sd.reading_at)) as "Reading At",
    EXTRACT(EPOCH from DATE_TRUNC('milliseconds', now() at TIME ZONE 'UTC')) - EXTRACT(EPOCH FROM  DATE_TRUNC('milliseconds', s.last_seen_at)) as "Last Seen At",
    s.device,
    s.inserted_at as "First Discovered",
    sa.description
      from sensor_device s, sensor_datapoint sd, sensor_alias sa
      WHERE s.id = sd.device_id AND s.id = sa.device_id AND sd.relhum IS NOT NULL AND sd.reading_at > now() - interval '20 seconds'
      GROUP BY s.id, sa.name, sd.reading_at, sa.description
      ORDER BY sd.reading_at desc
