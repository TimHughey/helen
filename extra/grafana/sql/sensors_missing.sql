SET intervalstyle = 'postgres';
SET timezone='UTC';
  SELECT s.id,
  s.dev_latency_us,
    s.last_seen_at as "Last Seen At",
    s.device,
    s.inserted_at as "First Discovered",
    s.description
      FROM sensor s
      WHERE s.last_seen_at < (now() at TIME ZONE 'UTC' - interval '17 seconds')
      ORDER BY s.last_seen_at desc
