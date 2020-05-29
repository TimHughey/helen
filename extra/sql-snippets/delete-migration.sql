DELETE
  FROM schema_migrations
    WHERE version =
      (SELECT
        version
       FROM
        schema_migrations
       ORDER BY
        version DESC
       LIMIT 1); 
