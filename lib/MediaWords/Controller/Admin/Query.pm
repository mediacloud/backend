package MediaWords::Controller::Admin::Query;
use Modern::Perl "2012";
use MediaWords::CommonLibs;

use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller::REST' }

use MediaWords::DBI::StorySubsets;

use strict;
use warnings;
use JSON;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use Moose;
use namespace::autoclean;
use List::Compare;
use Carp;
use MediaWords::Solr;
use Data::Dumper;
use Data::Structure::Util qw( unbless );

__PACKAGE__->config( 'default' => 'application/json' );

use constant ROWS_PER_PAGE => 20;

# list of stories with the given feed id
sub sentences : Local : ActionClass('REST') : PathPrefix( '/api' )
{
}

sub sentences_GET : Local : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    say STDERR "starting stories_query_json";

    my $q = $c->req->parameters->{ 'q' };
    my $fq = $c->req->parameters->{ 'fq' };
    my $start = $c->req->parameters->{ 'start' };
    my $rows = $c->req->parameters->{ 'rows' };   

    $start //= 0;
    $rows //= 1000;

    my $solr_params = {q=>$q,fq=>$fq,start=>$start,rows=>$rows};

    #The following gets the number of stories found.

    #my $numFound = MediaWords::Solr::get_num_found($solr_params);

    #say $numFound;

    #The following gets the array of sentences that match the query

    my $hash = MediaWords::Solr::query($solr_params);
    unbless $hash;
    #say "Dumping Hash!";
    say STDERR Dumper(%$hash);
    my $response = $ { $hash} { response };

    $self->status_ok(
    $c,
    entity => {
    #response => $hash->['response']
    response => $response,
    }
    );

    my $json = encode_json(\%$hash);
    say STDOUT $json;
    
}

sub wc : Local : ActionClass('REST') : PathPrefix( '/api' )
{
}

sub wc_GET : Local : PathPrefix( '/api' )
{
    my ( $self, $c ) = @_;

    say STDERR "starting stories_query_json";
    
    my $q = $c->req->parameters->{ 'q' };
    my $fq = $c->req->parameters->{ 'fq' };

    my $solr_params = {q=>$q,fq=>$fq};

    #The following gets the number of stories found.

    #my $numFound = MediaWords::Solr::get_num_found($solr_params);

    #say $numFound;

    #The following gets the array of sentences that match the query

    my $array = MediaWords::Solr::count_words($solr_params);
    unbless $array;
    #say "Dumping Hash!";
    say STDERR Dumper($array);
    #my $response = $ { $array} { response };

    $self->status_ok(
    $c,
    entity => {
    response => $array,
    #response => $response,
    }
    );

    #my $json = encode_json(\%$hash);
    #say STDOUT $json;

}

sub _add_data_to_stories
{

    my ( $self, $db, $stories, $show_raw_1st_download ) = @_;

    foreach my $story ( @{ $stories } )
    {
        my $story_text = MediaWords::DBI::Stories::get_text_for_word_counts( $db, $story );
        $story->{ story_text } = $story_text;
    }

    foreach my $story ( @{ $stories } )
    {
        my $fully_extracted = MediaWords::DBI::Stories::is_fully_extracted( $db, $story );
        $story->{ fully_extracted } = $fully_extracted;
    }

    if ( $show_raw_1st_download )
    {
        foreach my $story ( @{ $stories } )
        {
            my $content_ref = MediaWords::DBI::Stories::get_content_for_first_download( $db, $story );

            if ( !defined( $content_ref ) )
            {
                $story->{ first_raw_download_file }->{ missing } = 'true';
            }
            else
            {

                #say STDERR "got content_ref $$content_ref";

                $story->{ first_raw_download_file } = $$content_ref;
            }
        }
    }

    foreach my $story ( @{ $stories } )
    {
        my $story_sentences =
          $db->query( "SELECT * from story_sentences where stories_id = ? ORDER by sentence_number", $story->{ stories_id } )
          ->hashes;
        $story->{ story_sentences } = $story_sentences;
    }

    return $stories;
}


1;
