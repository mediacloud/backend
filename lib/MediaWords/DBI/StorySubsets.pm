package MediaWords::DBI::StorySubsets;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# various helper functions for the download_texts table

use strict;

use Encode;

use Data::Dumper;

use MediaWords::Util::Config;
use MediaWords::Util::HTML;
use MediaWords::DBI::Downloads;
use Carp;

sub process
{
    my ( $db, $st_subset ) = @_;

    croak "story_subset not present " unless defined( $st_subset );

    my $story_subsets_id = $st_subset->{ story_subsets_id };
    croak "story_subsets_id not defined " unless defined( $story_subsets_id );

    #build query

    my $query_map = {
        'start_date'    => 'publish_date >= ?',
        'end_date'      => 'publish_date <= ?',
        'media_id'      => ' media_id = ?',
        'media_sets_id' => ' media_id in ( select media_id from media_sets_media_map where media_sets_id = ? ) ',
    };

    my $defined_clauses = [ grep { defined( $st_subset->{ $_ } ) } ( keys %{ $st_subset } ) ];

    my $non_query_clauses = [ qw ( story_subsets_id ready last_process_stories_id ) ];

    my $lc = List::Compare->new( $non_query_clauses, $defined_clauses );

    my $subset_clauses = [ sort $lc->get_Ronly ];

    my $where_clause .= ' 1 = 1 ';

    my $query_params = [];

    push( @{ $query_params }, $story_subsets_id );
    say STDERR Dumper( $query_params );

    foreach my $clause ( @{ $subset_clauses } )
    {
        $where_clause .= ' and ';
        $where_clause .= $query_map->{ $clause };
        push @{ $query_params }, $st_subset->{ $clause };
    }

    say STDERR Dumper( $query_params );
    my ( $max_processed_stories_id ) = $db->query( " SELECT max( processed_stories_id ) from processed_stories " )->flat;

    say STDERR "max_prcessed_stories_id = $max_processed_stories_id";

    $db->begin_work;

    my $query =
" INSERT INTO story_subsets_processed_stories_map( processed_stories_id , story_subsets_id ) SELECT processed_stories_id, ? from processed_stories natural join stories WHERE $where_clause AND processed_stories_id <= ? ORDER by processed_stories_id ASC";

    push @{ $query_params }, $max_processed_stories_id;

    say STDERR $query;
    say STDERR Dumper( $query_params );

    $db->query( $query, @{ $query_params } );

    $db->query( " UPDATE story_subsets set ready = 'true', last_processed_stories_id = ? where story_subsets_id = ?  ",
        $max_processed_stories_id, $st_subset->{ story_subsets_id } );

    $db->commit;

    return;
}

1;
