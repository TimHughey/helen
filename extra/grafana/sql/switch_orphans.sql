SELECT
    sa.NAME AS "Name",
    sc.sent_at AS "Sent"
FROM
    switch_command sc,
    switch_alias sa
WHERE
    sc.orphan = TRUE
    AND sc.alias_id = sa.id
    AND sc.sent_at >= (NOW() - INTERVAL '12 hours')
ORDER BY
    sc.sent_at
