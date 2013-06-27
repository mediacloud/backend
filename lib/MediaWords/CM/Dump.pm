package MediaWords::CM::Dump;

# code to analyze a controversy and dump the controversy to snapshot tables and a gexf file

use strict;

my $_snapshot_tables =
    [ qw/controversy_stories controversy_links_cross_media controversy_media_codes
         stories media stories_tags_map media_tags_map tags tag_sets/ ]; 
         
sub get_snapshot_tables
{
    return [ @{ $_snapshot_tables } ];
}

1;