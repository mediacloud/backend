


create table media_stats_weekly (
    media_id        int not null references media on delete cascade,
    stories_rank    int not null,
    num_stories     numeric not null,
    sentences_rank  int not null,
    num_sentences   numeric not null,
    stat_week       date not null
);

create index media_stats_weekly_medium on media_stats_weekly ( media_id );

create table media_expected_volume (
    media_id            int not null references media on delete cascade,
    start_date          date not null,
    end_date            date not null,
    expected_stories    numeric not null,
    expected_sentences  numeric not null
);

create index media_expected_volume_medium on media_expected_volume ( media_id );

create table media_coverage_gaps (
    media_id                int not null references media on delete cascade,
    stat_week               date not null,
    num_stories             numeric not null,
    expected_stories        numeric not null,
    num_sentences           numeric not null,
    expected_sentences      numeric not null
);

create index media_coverage_gaps_medium on media_coverage_gaps ( media_id );

create table media_health (
    media_id            int not null references media on delete cascade,
    num_stories         numeric not null,
    num_stories_y       numeric not null,
    num_stories_w       numeric not null,
    num_stories_90      numeric not null,
    num_sentences       numeric not null,
    num_sentences_y     numeric not null,
    num_sentences_w     numeric not null,
    num_sentences_90    numeric not null,
    is_healthy          boolean not null default false,
    has_active_feed     boolean not null default true,
    start_date          date not null,
    end_date            date not null,
    expected_sentences  numeric not null,
    expected_stories    numeric not null,
    coverage_gaps       int not null
);

create index media_health_medium on media_health ( media_id );



