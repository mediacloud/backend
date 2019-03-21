

DROP INDEX media_sets_cluster;

ALTER TABLE media_sets
	DROP CONSTRAINT dashboard_media_sets_type;

ALTER TABLE media_sets
	DROP COLUMN media_clusters_id;

ALTER TABLE dashboard_media_sets
	DROP COLUMN media_cluster_runs_id;


DROP TABLE media_cluster_words;

DROP TABLE media_cluster_zscores;

DROP TABLE media_clusters_media_map;

DROP TABLE media_cluster_map_poles;

DROP TABLE media_cluster_map_pole_similarities;

DROP TABLE media_clusters;

DROP TABLE media_cluster_maps;

DROP TABLE media_cluster_links;

DROP TABLE media_cluster_runs;



ALTER TABLE media_sets
	ADD CONSTRAINT dashboard_media_sets_type check ( ( ( set_type = 'medium' ) and ( media_id is not null ) )
        or
        ( ( set_type = 'collection' ) and ( tags_id is not null ) )
        or
        ( ( set_type = 'cluster' ) ) );

