

-- keep track of performance of the topic spider
create table topic_spider_metrics (
    topic_spider_metrics_id         serial primary key,
    topics_id                       int references topics on delete cascade,
    iteration                       int not null,
    links_processed                 int not null,
    elapsed_time                    int not null,
    processed_date                  timestamp not null default now()
);

create index topic_spider_metrics_topic on topic_spider_metrics( topics_id );
create index topic_spider_metrics_dat on topic_spider_metrics( processed_date );



