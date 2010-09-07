ALTER TABLE media_clusters add column centroid_media_id             int              references media (media_id) on delete cascade;

create table media_cluster_links (
  media_cluster_links_id serial primary key, 
	media_cluster_runs_id	 int	  not null     references media_cluster_runs on delete cascade,
  source_media_id        int    not null     references media              on delete cascade,
  target_media_id        int    not null     references media              on delete cascade,
  weight                 float  not null
);

/****************************************************** 
 * A table to store the internal/external zscores for
 *   every source analyzed by Cluto
 *   (the external/internal similarity scores for
 *     clusters will be stored in media_clusters, if at all)
 ******************************************************/

create table media_cluster_zscores (
  media_cluster_zscores_id  serial primary key,
	media_cluster_runs_id	    int 	 not null     references media_cluster_runs on delete cascade,
	media_clusters_id         int    not null     references media_clusters     on delete cascade,
  media_id                  int    not null     references media              on delete cascade,
  internal_zscore           float  not null, 
  internal_similarity       float  not null,
  external_zscore           float  not null,
  external_similarity       float  not null     
);