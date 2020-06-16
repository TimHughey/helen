SELECT
    sa.NAME AS "Name",
    sc.refid AS "RefID",
    sc.acked AS "Acked?",
    sc.orphan AS "Orphan?",
    sc.rt_latency_us AS "RT Latency",
    sc.sent_at AS "Sent",
    sc.ack_at AS "Acked"
FROM
    switch_command sc,
    switch_device s,
    switch_alias sa
WHERE
    sc.device_id = s.id
    AND s.id = sa.device_id
    AND sc.sent_at >= (NOW() - INTERVAL '1 hour')
