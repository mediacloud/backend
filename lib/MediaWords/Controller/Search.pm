package MediaWords::Controller::Search;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use strict;
use warnings;
use parent 'Catalyst::Controller';

use URI::Escape;
use DBIx::Simple;

#
#  This module is obsolete
#  The download_texts table no longer supports ts indexes
#  Also we are now using word vectors for search.
#

sub index : Path : Args(0)
{

    return basic_search( @_ );
}

# return the top ten tags for the given medium
sub basic_search : Local
{
    my ( $self, $c ) = @_;

    my $use_countries;
    my $tags    = [];
    my $tsquery = $c->request->param( 'tsquery' );

    my @matching_downloads;

    if ( defined( $tsquery ) )
    {

        my $ranked_matches = $c->dbis->query(
"select downloads_id, ts_rank_cd(to_tsvector('english', download_text), plainto_tsquery('english', ?), 4 | 1 | 16 ) AS rank from download_texts where to_tsvector('english', download_text) @@ plainto_tsquery('english', ?) ORDER BY rank ASC",
            $tsquery, $tsquery
        )->hashes;

        my $matches = [];

        my $max_result_list_size = $c->request->param( 'num_results_per_page' );

        $max_result_list_size ||= 10;

        my $num_results = 0;

        my $total_matches = scalar( @{ $ranked_matches } );

        $c->stash->{ total_matches } = $total_matches;

        while ( ( my $ranked_match = pop @{ $ranked_matches } )
            && $num_results < $max_result_list_size )
        {
            my $match_info = {};

            $match_info->{ downloads_id } = $ranked_match->{ downloads_id };

            $match_info->{ rank } = $ranked_match->{ rank };

            my $story = $c->dbis->query(
"select stories.* from stories, downloads where downloads.stories_id=stories.stories_id and downloads.downloads_id = ?",
                $ranked_match->{ downloads_id }
            )->hash();

            my $story_title = $story->{ title };

            my $story_date = $story->{ publish_date };

            $match_info->{ title } = $story_title;

            $match_info->{ date } = $story_date;

            $match_info->{ story_url } = $story->{ url };

            $match_info->{ story_id } = $story->{ stories_id };

            $match_info->{ download_url } =
              $c->dbis->query( "select url from downloads where downloads_id= ? ", $ranked_match->{ downloads_id } )->hash()
              ->{ url };

            print STDERR "story: $story " . $story->{ media_id } . "\n";

            my $media_source =
              $c->dbis->query( "select name from media where media_id = ?", $story->{ media_id } )->hash->{ name };

            print STDERR "media_source: $media_source\n";

            $match_info->{ media_source } = $media_source;

            #            print STDERR "$story_title " . $ranked_match->{downloads_id} . "\n";

            my $head_line;

            $head_line = $self->get_headline( $c, $tsquery, $ranked_match->{ downloads_id } );

            $match_info->{ head_line } = $head_line;

            #            print STDERR "headline: $head_line\n";

            push @{ $matches }, $match_info;

            $num_results++;
        }

        $c->stash->{ displayed_matches } = $num_results;
        $c->stash->{ match_list }        = $matches;

#         my @head_lines = $c->dbis->query(
# "select downloads_id, ts_headline( download_text, plainto_tsquery(?)) from (select download_text, downloads_id, ts_rank_cd(to_tsvector('english', download_text), plainto_tsquery('english', ?)  ) AS rank from download_texts where to_tsvector('english', download_text) @@ plainto_tsquery('english', ?) order by rank) AS foo",
#             $tsquery, $tsquery, $tsquery )->flat;

        #         print STDERR "headlines: " . join " \n ", @head_lines;

    }

    # increase from 1000 to handle all media_tag_counts
    $Template::Directive::WHILE_MAX = 2000;

    $c->stash->{ template } = 'search/search.tt2';

    #    $c->stash->{matching_downloads} = join " , ", @matching_downloads;
}

sub get_headline : Local
{

    my ( $self, $c, $tsquery, $downloads_id ) = @_;

    my $start_tag = "<#@&@#START#@*>&&";
    my $end_tag   = "</@&@#END#@*>&&&";

    my $highlight_text = $c->dbis->query(
        "select ts_headline( download_text, plainto_tsquery(?), ? ) from download_texts where downloads_id = ?",
        $tsquery, "StartSel =$start_tag StopSel =$end_tag",
        $downloads_id
    )->hash->{ ts_headline };

    my $pos = 0;

    #    print STDERR "get_headline: $highlight_text\n";

    #    print STDERR 'CORE::index ($highlight_text, $start_tag) ' . CORE::index( $highlight_text, $start_tag );
    #    print STDERR "\n";

    my $ret = [];

    while ( ( my $highlight_start = ( CORE::index( $highlight_text, $start_tag ) ) ) != -1 )
    {

        #        print STDERR "while: $highlight_text \n";
        my $non_highlighted = substr( $highlight_text, 0, $highlight_start );

        push @{ $ret }, { high_lighted => 0, text => $non_highlighted };

        substr( $highlight_text, 0, $highlight_start, '' );

        substr( $highlight_text, 0, length( $start_tag ), '' );

        my $highlight_end = CORE::index( $highlight_text, $end_tag );

        my $highlighted = substr( $highlight_text, 0, $highlight_end );

        push @{ $ret }, { high_lighted => 1, text => $highlighted };

        substr( $highlight_text, 0, $highlight_end,     "" );
        substr( $highlight_text, 0, length( $end_tag ), "" );

        #        print STDERR "Non highlighted: $non_highlighted\n";
        #        print STDERR "highlighted: $highlighted\n";
    }

    push @{ $ret }, { high_lighted => 0, text => $highlight_text };
    return $ret;
}

=head1 AUTHOR

,,,

=head1 LICENSE

This library is free software, you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
