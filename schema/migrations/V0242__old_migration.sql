


alter table dashboard_topics alter language drop not null;
alter table story_sentence_words alter language drop not null;
alter table daily_words drop language;
alter table weekly_words drop language;
alter table top_500_weekly_words drop language;
alter table daily_country_counts drop language;
alter table daily_author_words drop language;
alter table weekly_author_words drop language;
alter table top_500_weekly_author_words drop language;

create view controversies_with_search_info as
    select c.*, q.start_date::date, q.end_date::date, qss.pattern, qss.queries_id
        from controversies c
            left join query_story_searches qss on ( c.query_story_searches_id = qss.query_story_searches_id )
            left join queries q on ( qss.queries_id = q.queries_id );
            
create or replace view controversy_links_cross_media as
  select s.stories_id, sm.name as media_name, r.stories_id as ref_stories_id, rm.name as ref_media_name, cl.url as url, cs.controversies_id from media sm, media rm, controversy_links cl, stories s, stories r, controversy_stories cs where cl.ref_stories_id <> cl.stories_id and s.stories_id = cl.stories_id and cl.ref_stories_id = r.stories_id and s.media_id <> r.media_id and sm.media_id = s.media_id and rm.media_id = r.media_id and cs.stories_id = cl.ref_stories_id and cs.controversies_id = cl.controversies_id;

create table controversy_dumps (
    controversy_dumps_id            serial primary key,
    controversies_id                int not null references controversies on delete cascade,
    dump_date                       timestamp not null,
    start_date                      timestamp not null,
    end_date                        timestamp not null,
    note                            text,
    daily_counts_csv                text,
    weekly_counts_csv               text
);

create index controversy_dumps_controversy on controversy_dumps ( controversies_id );

create type cd_period_type AS ENUM ( 'overall', 'weekly', 'monthly', 'custom' );

-- individual time slices within a controversy dump
create table controversy_dump_time_slices (
    controversy_dump_time_slices_id serial primary key,
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    start_date                      timestamp not null,
    end_date                        timestamp not null,
    period                          cd_period_type not null,
    gexf                            text,
    stories_csv                     text,
    story_links_csv                 text,
    media_csv                       text,
    medium_links_csv                text,
    model_r2_mean                   float,
    model_r2_stddev                 float,
    model_num_media                 int
);

alter table controversy_dump_time_slices add constraint cdts_confidence 
    check ( confidence is null or ( confidence >= 0 and confidence <= 100 ) );

create index controversy_dump_time_slices_dump on controversy_dump_time_slices ( controversy_dumps_id );

-- schema to hold all of the controversy dump snapshot tables
create schema cd;

create table cd.stories (
    controversy_dumps_id        int             not null references controversy_dumps on delete cascade,
    stories_id                  int,
    media_id                    int             not null,
    url                         varchar(1024)   not null,
    guid                        varchar(1024)   not null,
    title                       text            not null,
    description                 text            null,
    publish_date                timestamp       not null,
    collect_date                timestamp       not null,
    full_text_rss               boolean         not null default 'f',
    language                    varchar(3)      null   -- 2- or 3-character ISO 690 language code; empty if unknown, NULL if unset
);
create index stories_id on cd.stories ( controversy_dumps_id, stories_id );

create table cd.controversy_stories (
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,    
    controversy_stories_id          int,
    controversies_id                int not null,
    stories_id                      int not null,
    link_mined                      boolean,
    iteration                       int,
    link_weight                     real,
    redirect_url                    text,
    valid_foreign_rss_story         boolean
);
create index controversy_stories_id on cd.controversy_stories ( controversy_dumps_id, stories_id );

create table cd.controversy_links_cross_media (
    controversy_dumps_id        int not null references controversy_dumps on delete cascade,    
    controversy_links_id        int,
    controversies_id            int not null,
    stories_id                  int not null,
    url                         text not null,
    ref_stories_id              int,
    media_name                  text,
    ref_media_name              text    
);
create index controversy_links_story on cd.controversy_links_cross_media ( controversy_dumps_id, stories_id );
create index controversy_links_ref on cd.controversy_links_cross_media ( controversy_dumps_id, ref_stories_id );
 
create table cd.controversy_media_codes (
    controversy_dumps_id    int not null references controversy_dumps on delete cascade,    
    controversies_id        int not null,
    media_id                int not null,
    code_type               text,
    code                    text
);
create index controversy_media_codes_medium on cd.controversy_media_codes ( controversy_dumps_id, media_id );
     
create table cd.media (
    controversy_dumps_id    int not null references controversy_dumps on delete cascade,    
    media_id                int,
    url                     varchar(1024)   not null,
    name                    varchar(128)    not null,
    moderated               boolean         not null,
    feeds_added             boolean         not null,
    moderation_notes        text            null,       
    full_text_rss           boolean,
    extract_author          boolean         default(false),
    sw_data_start_date      date            default(null),
    sw_data_end_date        date            default(null),
    foreign_rss_links       boolean         not null default( false ),
    dup_media_id            int             null,
    is_not_dup              boolean         null,
    use_pager               boolean         null,
    unpaged_stories         int             not null default 0
);
create index media_id on cd.media ( controversy_dumps_id, media_id );

create table cd.media_tags_map (
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,    
    media_tags_map_id       int,
    media_id                int             not null,
    tags_id                 int             not null
);
create index media_tags_map_medium on cd.media_tags_map ( controversy_dumps_id, media_id );
create index media_tags_map_tag on cd.media_tags_map ( controversy_dumps_id, tags_id );
     
create table cd.stories_tags_map
(
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,    
    stories_tags_map_id     int,
    stories_id              int,
    tags_id                 int
);
create index stories_tags_map_story on cd.stories_tags_map ( controversy_dumps_id, stories_id );
create index stories_tags_map_tag on cd.stories_tags_map ( controversy_dumps_id, tags_id );
 
create table cd.tags (
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,    
    tags_id                 int,
    tag_sets_id             int,
    tag                     varchar(512)
);
create index tags_id on cd.tags ( controversy_dumps_id, tags_id );
 
create table cd.tag_sets (
    controversy_dumps_id    int not null    references controversy_dumps on delete cascade,    
    tag_sets_id             int,
    name                    varchar(512)    
);
create index tag_sets_id on cd.tag_sets ( controversy_dumps_id, tag_sets_id );

-- story -> story links within a cdts
create table cd.story_links (
    controversy_dump_time_slices_id         int not null
                                            references controversy_dump_time_slices on delete cascade,
    source_stories_id                       int not null,
    ref_stories_id                          int not null
);

-- TODO: add complex foreign key to check that *_stories_id exist for the controversy_dump stories snapshot    
create index story_links_source on cd.story_links( controversy_dump_time_slices_id, source_stories_id );
create index story_links_ref on cd.story_links( controversy_dump_time_slices_id, ref_stories_id );

-- link counts for stories within a cdts
create table cd.story_link_counts (
    controversy_dump_time_slices_id         int not null 
                                            references controversy_dump_time_slices on delete cascade,
    stories_id                              int not null,
    inlink_count                            int not null,
    outlink_count                           int not null
);

-- TODO: add complex foreign key to check that stories_id exists for the controversy_dump stories snapshot
create index story_link_counts_story on cd.story_link_counts ( controversy_dump_time_slices_id, stories_id );

-- links counts for media within a cdts
create table cd.medium_link_counts (
    controversy_dump_time_slices_id int not null
                                    references controversy_dump_time_slices on delete cascade,
    media_id                        int not null,
    inlink_count                    int not null,
    outlink_count                   int not null,
    story_count                     int not null
);

-- TODO: add complex foreign key to check that media_id exists for the controversy_dump media snapshot
create index medium_link_counts_medium on cd.medium_link_counts ( controversy_dump_time_slices_id, media_id );

create table cd.medium_links (
    controversy_dump_time_slices_id int not null
                                    references controversy_dump_time_slices on delete cascade,
    source_media_id                 int not null,
    ref_media_id                    int not null,
    link_count                      int not null
);

-- TODO: add complex foreign key to check that *_media_id exist for the controversy_dump media snapshot
create index medium_links_source on cd.medium_links( controversy_dump_time_slices_id, source_media_id );
create index medium_links_ref on cd.medium_links( controversy_dump_time_slices_id, ref_media_id );

create table cd.daily_date_counts (
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    publish_date                    date not null,
    story_count                     int not null,
    tags_id                         int
);

create index daily_date_counts_date on cd.daily_date_counts( controversy_dumps_id, publish_date );
create index daily_date_counts_tag on cd.daily_date_counts( controversy_dumps_id, tags_id );

create table cd.weekly_date_counts (
    controversy_dumps_id            int not null references controversy_dumps on delete cascade,
    publish_date                    date not null,
    story_count                     int not null,
    tags_id                         int
);

create index weekly_date_counts_date on cd.weekly_date_counts( controversy_dumps_id, publish_date );
create index weekly_date_counts_tag on cd.weekly_date_counts( controversy_dumps_id, tags_id );
                                        

alter table media_edits alter reason drop not null;
alter table media_edits drop constraint reason_not_empty;

alter table story_edits alter reason drop not null;
alter table story_edits drop constraint reason_not_empty;

CREATE OR REPLACE FUNCTION is_stop_stem(p_size TEXT, p_stem TEXT, p_language TEXT)
    RETURNS BOOLEAN AS \$\$
DECLARE
    result BOOLEAN;
BEGIN

    -- Tiny
    IF p_size = 'tiny' THEN
        IF p_language IS NULL THEN
            SELECT 't' INTO result FROM stopword_stems_tiny
                WHERE stopword_stem = p_stem;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        ELSE
            SELECT 't' INTO result FROM stopword_stems_tiny
                WHERE stopword_stem = p_stem AND language = p_language;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        END IF;

    -- Short
    ELSIF p_size = 'short' THEN
        IF p_language IS NULL THEN
            SELECT 't' INTO result FROM stopword_stems_short
                WHERE stopword_stem = p_stem;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        ELSE
            SELECT 't' INTO result FROM stopword_stems_short
                WHERE stopword_stem = p_stem AND language = p_language;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        END IF;

    -- Long
    ELSIF p_size = 'long' THEN
        IF p_language IS NULL THEN
            SELECT 't' INTO result FROM stopword_stems_long
                WHERE stopword_stem = p_stem;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        ELSE
            SELECT 't' INTO result FROM stopword_stems_long
                WHERE stopword_stem = p_stem AND language = p_language;
            IF NOT FOUND THEN
                result := 'f';
            END IF;
        END IF;

    -- unknown size
    ELSE
        RAISE EXCEPTION 'Unknown stopword stem size: "%" (expected "tiny", "short" or "long")', p_size;
        result := 'f';
    END IF;

    RETURN result;
END;
\$\$ LANGUAGE plpgsql;

