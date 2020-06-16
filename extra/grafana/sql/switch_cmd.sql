SELECT sa.name as "Name",
    sc.refid as "RefID",
    sc.acked as "Acked?", sc.orphan as "Orphan?",
    sc.rt_latency_us as "RT Latency",
    sc.sent_at as "Sent", sc.ack_at as "Acked"

  FROM switch_command sc, switch_device s, switch_alias sa
  WHERE sc.device_id = s.id AND s.id = sa.device_id AND
        sc.sent_at >= (now() - interval '1 hour')
