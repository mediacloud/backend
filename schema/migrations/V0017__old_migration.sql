


--
-- Stories from failed Bit.ly RabbitMQ queue
-- (RabbitMQ failed reindexing a huge queue so we had to recover stories in
-- that queue manually. Story IDs from this table are to be gradually moved to
-- Bit.ly processing schedule.)
--
CREATE TABLE IF NOT EXISTS stories_from_failed_bitly_rabbitmq_queue (
    stories_id BIGINT NOT NULL REFERENCES stories (stories_id)
);
CREATE INDEX stories_from_failed_bitly_rabbitmq_queue_stories_id
    ON stories_from_failed_bitly_rabbitmq_queue (stories_id);


