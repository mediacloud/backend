package MediaWords::Pg::Cleanup;

# various cleanup functions

use strict;

use Time::Local;

use MediaWords::Pg;

# return date in YYY-MM-DD format
sub _get_ymd {
    my ($epoch) = @_;
    
    my ($sec, $min, $hour, $mday, $mon, $year) = localtime($epoch);
    
    return sprintf('%04d-%02d-%02d', $year + 1900, $mon + 1, $mday);
}


# merge stories with the same title from the media source on the same day
sub remove_duplicate_stories {    
    my ($month, $year) = @_;
    
    exec_query("create temporary table duplicate_stories (stories_id int, feeds_id int) on commit drop");
    
    my $date = timelocal(0, 0, 0, 1, $month - 1, $year - 1900);
    
    # iterate through each day, aggregating all stories from the same media source with the same title on the same day.
    for (my $date = timelocal(0, 0, 0, 1, $month - 1, $year - 1900); $date < time; $date += 86400) {
        
        if ($month != (localtime($date))[4] + 1) {
            last;
        }
        my $date_ymd = _get_ymd($date);
        
        my $sth = query("select count(*) as num_stories, max(stories_id) as max_stories_id, title, media_id from stories " . 
                        "where publish_date >= date '$date_ymd' and publish_date < date '$date_ymd' + interval '1 day' " .
                        "group by title, media_id having count(*) > 1");
        my $count = 0;
        while (my $story_group = fetchrow($sth)) {
            pg_log("[$date_ymd] story: " . $count++ . " " . $story_group->{max_stories_id} . " " . $story_group->{num_stories});
            
            exec_prepared("insert into duplicate_stories (stories_id, feeds_id) " . 
                          "  select fsm.stories_id, fsm.feeds_id from feeds_stories_map fsm, stories s " . 
                          "    where s.title = \$1 and s.media_id = \$2 and " .
                          "      s.publish_date >= date '$date_ymd' and s.publish_date < date '$date_ymd' + interval '1 day' and " .
                          "      s.stories_id = fsm.stories_id",
                          [ qw( TEXT INT ) ],
                          [ $story_group->{title}, $story_group->{media_id} ]);
            
            exec_prepared("delete from feeds_stories_map where stories_id in (select stories_id from duplicate_stories)");
            
            exec_prepared("insert into feeds_stories_map (stories_id, feeds_id) select distinct \$1, feeds_id from duplicate_stories",
                          [ qw( INT ) ], [ $story_group->{max_stories_id} ]);
            
            exec_prepared("delete from stories where stories_id in (" . 
                          "  select stories_id from duplicate_stories where stories_id <> \$1)",
                          [ qw( INT ) ], [ $story_group->{max_stories_id} ]);

            exec_prepared("truncate table duplicate_stories");
        }
        
        #exec_query("drop table duplicate_stories");
        
    }
}

# # cleanup stories assocaited with feeds from media different from stories.media_id by creating a copy of each
# # story for each assocaited medium
# sub cleanup_story_media {
#  
#     my $s_sth = query("select s.stories_id, s.media_id, min(fsm.feeds_id) as feeds_id " . 
#                       "  from stories s, feeds_stories_map fsm, feeds f " .
#                       "  where s.feeds_id = fsm.feeds_id and fsm.feeds_id = f.feeds_id and " .
#                       "    f.media_id <> s.media_id group by s.stories_id, f.media_id");
#         
#     while (my $story = fetchrow($s_sth)) {
# 
#         my ($new_story) = execute_prepared("insert into stories (media_id, url, guid, title, " .
#                                            "    description, publish_date, collect_date) " .
#                                            "  select $1, url, uid, title, description, publish_date, collect_date " .
#                                            "    from stories where stories_id = $2 returning stories_id",
#                                            [ qw(INT INT) ], [ $story->{media_id}, $story->{stories_id} ]);
#                                            
#         my $d_sth = query_prepare("select * from downloads where stories_id = $1 order by downloads_id", $story->{stories_id});
#         my $parent_downloads_id;
#         while (my $d = fetchrow($d_sth)) {
#             my $new_download =
#                 query("insert into downloads (feeds_id, stories_id, parent, url, host, download_time, type, state, path, " . 
#                       "    error_message, priority, sequence, extracted) " .
#                       " values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13) return downloads_id",
#                       [ qw(INT INT INT TEXT TEXT TIMESTAMP TEXT TEXT TEXT TEXT INT INT BOOLEAN) ],
#                       [ $story->{feeds_id}, $new_story->{stories_id}, $parent_downloads_id, $d->{url}, $d->{host}, 
#                         $d->{download_time}, $d->{type}, $d->{state}, $d->{path}, $d->{error_message}, $d->{priority}, 
#                         $d->{sequence}, $d->{extracted} ]);
#                         
#             $parent_download_id = $new_download->{downloads_id};
#             
#             
#         }
#     }
# 
# }

1;
