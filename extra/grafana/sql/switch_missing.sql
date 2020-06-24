SELECT
    device AS "Device Actual",
    last_seen_at
FROM
    switch_device
WHERE
    last_seen_at < $ __timeFrom ()
ORDER BY
    device;
