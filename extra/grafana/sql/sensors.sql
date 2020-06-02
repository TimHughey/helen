SET intervalstyle = 'postgres';
SET timezone='UTC';
  SELECT DISTINCT ON (sa.name) sa.name, s.id,
  AVG(sd.temp_f) as "TempF", AVG(sd.relhum) as "RH",
  s.dev_latency_us,
  EXTRACT(EPOCH from DATE_TRUNC('milliseconds', now() at TIME ZONE 'UTC')) - EXTRACT(EPOCH FROM  DATE_TRUNC('milliseconds', sd.reading_at)) as "Reading At",
    EXTRACT(EPOCH from DATE_TRUNC('milliseconds', now() at TIME ZONE 'UTC')) - EXTRACT(EPOCH FROM  DATE_TRUNC('milliseconds', s.last_seen_at)) as "Last Seen At",
    s.device,
    s.inserted_at as "First Discovered",
    sa.description
      from sensor_device s, sensor_alias sa, sensor_datapoint sd
      WHERE sd.device_id = s.id AND sa.device_id = s.id AND sd.reading_at > (now() at TIME ZONE 'UTC' - interval '2 minutes')
      GROUP BY sa.name, s.id, sd.reading_at, sa.description
      ORDER BY sa.name, sd.reading_at desc
