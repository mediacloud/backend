DROP TABLE IF EXISTS gearman_job_queue;
DROP FUNCTION IF EXISTS gearman_job_queue_sync_lastmod();

COMMENT ON COLUMN controversies.process_with_bitly
  IS 'Enable processing controversy''s stories with Bit.ly; add all new controversy stories to Bit.ly processing queue';



