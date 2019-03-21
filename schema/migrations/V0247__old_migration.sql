
-- track self liks and all links for a given domain within a given topic
create table topic_domains (
    topic_domains_id        serial primary key,
    topics_id               int not null,
    domain                  text not null,
    self_links              int not null default 0,
    all_links               int not null default 0
);

create unique index domain_topic_domain on topic_domains (topics_id, md5(domain));




