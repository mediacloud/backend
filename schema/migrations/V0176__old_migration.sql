

create table media_stats (
    media_stats_id              serial      primary key,
    media_id                    int         not null references media on delete cascade,
    num_stories                 int         not null,
    num_sentences               int         not null,
    mean_num_sentences          int         not null,
    mean_text_length            int         not null,
    num_stories_with_sentences  int         not null,
    num_stories_with_text       int         not null,
    stat_date                   date        not null
);

create index media_stats_medium on media_stats( media_id );




