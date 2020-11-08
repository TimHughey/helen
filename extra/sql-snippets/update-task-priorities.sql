UPDATE
    remote_profile
SET
    (i2c_discover_priority,
        i2c_report_priority,
        i2c_command_priority) = (4,
        5,
        12);

UPDATE
    remote_profile
SET
    (pwm_report_priority,
        pwm_command_priority) = (5,
        14);

UPDATE
    remote_profile
SET
    (dalsemi_discover_priority,
        dalsemi_convert_priority,
        dalsemi_report_priority,
        dalsemi_command_priority) = (4,
        5,
        5,
        12);
