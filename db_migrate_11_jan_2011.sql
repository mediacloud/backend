create table queries (
    queries_id              serial              primary key,
    start_date              date                not null,
    end_date                date                not null,
    generate_page           boolean             not null default false,
    creation_date           timestamp           not null default now(),
    description             text                null
);

create index queries_creation_date on queries (creation_date);
create unique index queries_hash on queries ( md5( description ) );

delete from daily_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from total_daily_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from weekly_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from top_500_weekly_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from total_top_500_weekly_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );

delete from daily_author_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from total_daily_author_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from weekly_author_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from top_500_weekly_author_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );
delete from total_top_500_weekly_author_words where media_sets_id in ( select media_sets_id from media_sets where media_clusters_id is not null );

delete from media_cluster_runs;

ALTER TABLE media_cluster_runs drop column start_date;
ALTER TABLE media_cluster_runs drop column end_date;
ALTER TABLE media_cluster_runs drop column media_sets_id;
ALTER TABLE media_cluster_runs drop column state;
ALTER TABLE media_cluster_runs drop column description;

ALTER TABLE media_cluster_runs add  column queries_id              int             not null references queries;

ALTER TABLE media_cluster_runs add  column state                   varchar(32)     not null default 'pending';


create table media_cluster_maps (
      media_cluster_maps_id       serial          primary key,
      map_type                    varchar(32)     not null default 'cluster',
      name                        text            not null,
      json                        text            not null,
      nodes_total                 int             not null,
      nodes_rendered              int             not null,
      links_rendered              int             not null,
      media_cluster_runs_id       int             not null references media_cluster_runs on delete cascade
 );
 	  	 
alter table media_cluster_maps add constraint media_cluster_maps_type check( map_type in ('cluster', 'polar' ));
 	  	 
create index media_cluster_maps_run on media_cluster_maps( media_cluster_runs_id );
 	  	 
create table media_cluster_map_poles (
     media_cluster_map_poles_id      serial      primary key,
     name                            text        not null,
     media_cluster_maps_id           int         not null references media_cluster_maps on delete cascade,
     pole_number                     int         not null,
     queries_id                      int         not null references queries on delete cascade
);
 	  	 
create index media_cluster_map_poles_map on media_cluster_map_poles( media_cluster_maps_id );

delete from daily_country_counts where media_sets_id not in ( select media_sets_id from media_sets );

ALTER TABLE daily_country_counts DROP CONSTRAINT daily_country_counts_media_sets_id_fkey;
ALTER TABLE daily_country_counts ADD CONSTRAINT daily_country_counts_media_sets_id_fkey FOREIGN KEY (media_sets_id) references media_sets;

create table queries_media_sets_map (
     queries_id              int                 not null references queries on delete cascade,
     media_sets_id           int                 not null references media_sets on delete cascade
);
 
create index queries_media_sets_map_query on queries_media_sets_map ( queries_id );
create index queries_media_sets_map_media_set on queries_media_sets_map ( media_sets_id );
 
create table queries_dashboard_topics_map (
     queries_id              int                 not null references queries on delete cascade,
     dashboard_topics_id     int                 not null references dashboard_topics on delete cascade
 );
 
create index queries_dashboard_topics_map_query on queries_dashboard_topics_map ( queries_id );
create index queries_dashboard_topics_map_dashboard_topic on queries_dashboard_topics_map ( dashboard_topics_id );
