SELECT
    sa.NAME AS "Name",
    sc.sent_at AS "Sent"
FROM
    switch_command sc,
    switch_device s,
    switch_alias sa
WHERE
    sc.orphan = TRUE
    AND sc.device_id = s.id
    AND s.id = sa.device_id
    AND sc.sent_at >= (NOW() - INTERVAL '12 hours')
ORDER BY
    sc.sent_at ASC
