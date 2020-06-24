SELECT
    sa.NAME AS "Name",
    sc.acked AS "Acked?",
    sc.orphan AS "Orphan?",
    sc.rt_latency_us AS "RT Latency",
    sc.sent_at AS "Sent",
    sc.ack_at AS "Acked"
FROM
    pwm_cmd sc,
    pwm_alias sa
WHERE
    sc.sent_at >= (NOW() - INTERVAL '3 hour')
    AND sc.alias_id = sa.id
ORDER BY
    sc.sent_at
