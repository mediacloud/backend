#!/usr/bin/perl

# test MediaWords::Crawler::Extractor against manually extracted downloads

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::Crawler::Extractor;
use Getopt::Long;
use HTML::Strip;
use DBIx::Simple::MediaWords;
use MediaWords::DB;
use Readonly;
use List::Util qw(first max maxstr min minstr reduce shuffle sum);
use List::MoreUtils qw(first_index);
use List::Compare::Functional qw (get_unique get_complement get_union_ref );
use AI::NeuralNet::Simple;
use Readonly;

#results arrays
Readonly my $required => [ 1, 0, 0 ];
Readonly my $optional => [ 0, 1, 0 ];
Readonly my $excluded => [ 0, 0, 1 ];

Readonly my $input_array_indexes => {
    html_density            => 0,
    discounted_html_density => 1,
    line_number             => 2,
    media_id                => 3,
};

my $_net = AI::NeuralNet::Simple->new( 4, 20, 3 );

my $_re_generate_cache = 0;

# sub get_lines_that_should_be_in_story
# {
#     ( my $download, my $dbs ) = @_;

#     my @story_lines = $dbs->query(
#         "select * from extractor_training_lines where extractor_training_lines.downloads_id = ? order by line_number ",
#         $download->{downloads_id} )->hashes;

#     my $line_should_be_in_story = {};

#     for my $story_line (@story_lines)
#     {
#         $line_should_be_in_story->{ $story_line->{line_number} } = $story_line->{required} ? 'required' : 'optional';
#     }

#     return $line_should_be_in_story;
# }

sub get_cached_extractor_line_scores
{
    ( my $download, my $dbs ) = @_;

    return $dbs->query( " SELECT  * from extractor_results_cache where downloads_id = ? order by line_number asc ",
        $download->{ downloads_id } )->hashes;
}

sub store_extractor_line_scores
{
    ( my $scores, my $lines, my $download, my $dbs ) = @_;

    $dbs->begin_work;

    $dbs->query( 'DELETE FROM extractor_results_cache where downloads_id = ?', $download->{ downloads_id } );

    my $line_number = 0;
    for my $score ( @{ $scores } )
    {

        #print (keys %{$score}) . "\n";
        $dbs->insert(
            'extractor_results_cache',
            {
                is_story                => $score->{ is_story },
                explanation             => $score->{ explanation },
                discounted_html_density => $score->{ discounted_html_density },
                html_density            => $score->{ html_density },
                downloads_id            => $download->{ downloads_id },
                line_number             => $line_number,
            }
        );

        $line_number++;
    }

    $dbs->commit;
}

sub get_extractor_scores_for_lines
{
    ( my $story_title, my $story_description, my $download, my $dbs ) = @_;

    my $ret;

    if ( !$_re_generate_cache )
    {
        $ret = get_cached_extractor_line_scores( $download, $dbs );
    }

    if ( !defined( $ret ) || !@{ $ret } )
    {
        my $lines = get_preprocessed_content_lines_for_download( $download );
        $ret = MediaWords::Crawler::Extractor::score_lines( $lines, $story_title, $story_description, );
        store_extractor_line_scores( $ret, $lines, $download, $dbs );
    }
    return $ret;
}

sub get_input_array
{
    my ( $download, $line_score ) = @_;

    my $input = [];

    $input->[ $input_array_indexes->{ html_density } ]            = $line_score->{ html_density };
    $input->[ $input_array_indexes->{ discounted_html_density } ] = $line_score->{ discounted_html_density };
    $input->[ $input_array_indexes->{ line_number } ] = 0;    #$line_score->{line_number};
    $input->[ $input_array_indexes->{ media_id } ]    = 0;    #$download->{media_id};

    return $input;
}

sub get_result_array
{
    my ( $download, $line_score ) = @_;

    my $result;

    if ( !( $line_score->{ is_story } ) )
    {
        $result = $excluded;
    }
    elsif ( ( $line_score->{ explanation } ) =~ /title match discount/i )
    {
        $result = $optional;
    }
    else
    {
        $result = $required;
    }

    return $result;

}

sub train_with_download
{
    ( my $download, my $dbs ) = @_;

    my $scores = [];

    my $story_title =
      $dbs->query( "SELECT title FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];
    my $story_description =
      $dbs->query( "SELECT description FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];

    $scores = get_extractor_scores_for_lines( $story_title, $story_description, $download, $dbs );

    foreach my $line_score ( @$scores )
    {
        my $result = get_result_array( $download, $line_score );

        my $input = get_input_array( $download, $line_score );

        $_net->train( $input, $result );
    }

    return;
}

sub train_with_downloads
{

    my $downloads = shift;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db();

    for my $download ( @downloads )
    {
        print "Training with Download: $download->{downloads_id} \n";
        train_with_download( $download, $dbs );
    }

}

sub test_with_download
{
    ( my $download, my $dbs ) = @_;

    my $scores = [];

    my $story_title =
      $dbs->query( "SELECT title FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];
    my $story_description =
      $dbs->query( "SELECT description FROM stories where stories.stories_id=? ", $download->{ stories_id } )->flat->[ 0 ];

    $scores = get_extractor_scores_for_lines( $story_title, $story_description, $download, $dbs );

    foreach my $line_score ( @$scores )
    {
        my $result = get_result_array( $download, $line_score );

        my $input = get_input_array( $download, $line_score );

        my $winner_index = $_net->winner( $input );

        die unless defined( $result );
        if ( $result->[ $winner_index ] )
        {
            print "Neural net correctly predicted winner $winner_index\n";
        }
        else
        {
            print "Incorrectly predicted $winner_index instead of " . ( first_index { $_ } @{ $result } ) . "\n";
        }
    }

    return;
}

sub test_with_downloads
{
    my $downloads = shift;

    my @downloads = @{ $downloads };

    @downloads = sort { $a->{ downloads_id } <=> $b->{ downloads_id } } @downloads;

    my $download_results = [];

    my $dbs = MediaWords::DB::connect_to_db();

    for my $download ( @downloads )
    {

        print "Download: $download->{downloads_id} \n";
        test_with_download( $download, $dbs );
    }

}

# do a test run of the text extractor
sub main
{

    my $db = MediaWords::DB->authenticate();

    my $dbs = MediaWords::DB::connect_to_db();

    my $file;
    my @download_ids;

    GetOptions(
        'file|f=s'                  => \$file,
        'downloads|d=s'             => \@download_ids,
        'regenerate_database_cache' => \$_re_generate_cache,
    ) or die;

    my $downloads;

    if ( @download_ids )
    {
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    elsif ( $file )
    {
        open( DOWNLOAD_ID_FILE, $file ) || die( "Could not open file: $file" );
        @download_ids = <DOWNLOAD_ID_FILE>;
        $downloads = $dbs->query( "SELECT * from downloads where downloads_id in (??)", @download_ids )->hashes;
    }
    else
    {
        $downloads = $dbs->query(
"SELECT * from downloads where downloads_id in (select distinct downloads_id from extractor_training_lines order by downloads_id)"
        )->hashes;
    }

    train_with_downloads( $downloads );
    test_with_downloads( $downloads );
}

main();
