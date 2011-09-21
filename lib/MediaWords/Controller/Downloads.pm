package MediaWords::Controller::Downloads;

use strict;
use warnings;
use base 'Catalyst::Controller';
use DateTime;

# MODULES

use HTML::Entities;
use IO::Uncompress::Gunzip;

use MediaWords::Crawler::Extractor;
use MediaWords::Crawler::Engine;
use MediaWords::Crawler::Provider;
use MediaWords::Crawler::Handler;
use MediaWords::DBI::Downloads;
use Data::Dumper;
use Perl6::Say;
use Encode;

# CONSTANTS

use constant ROWS_PER_PAGE => 100;

# METHODS

sub list : Local
{
    my ( $self, $c ) = @_;

    my $p        = $c->request->param( 'p' ) || 1;
    my $media_id = $c->request->param( 'm' );
    my $feeds_id = $c->request->param( 'f' );
    my $error    = $c->request->param( 'e' );

    my $query =
      "select d.* from downloads d, feeds f, media m " .
      "where d.feeds_id = f.feeds_id and f.media_id = m.media_id and d.download_time > now() - interval '1 month'";

    if ( $feeds_id )
    {
        $c->stash->{ feed } = $c->dbis->find_by_id( 'feeds', $feeds_id );
        $query .= " and d.feeds_id = " . ( $feeds_id + 0 );
    }
    elsif ( $media_id )
    {
        $c->stash->{ medium } = $c->dbis->find_by_id( 'media', $media_id );
        $query .= " and f.media_id = " . ( $media_id + 0 );
    }
    else
    {
        $query .= " and d.download_time > now() - interval '1 day'";
    }

    if ( $error )
    {
        $query .= " and d.state = 'error'";
    }

    $query .= " order by download_time desc";

    my ( $downloads, $pager ) = $c->dbis->query_paged_hashes( $query, $p, ROWS_PER_PAGE );

    for my $d ( @{ $downloads } )
    {
        $d->{ feed }   = $c->dbis->find_by_id( 'feeds', $d->{ feeds_id } );
        $d->{ medium } = $c->dbis->find_by_id( 'media', $d->{ feed }->{ media_id } );
    }

    $c->stash->{ downloads } = $downloads;
    $c->stash->{ pager }     = $pager;
    $c->stash->{ pager_url } = $c->uri_for( '/downloads/list', { f => $feeds_id, m => $media_id, e => $error } );
    $c->stash->{ template }  = 'downloads/list.tt2';
}

sub view : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    if ( !$downloads_id )
    {
        $c->response->redirect( $c->uri_for( '/downloads/list', { error_msg => 'no download specified' } ) );
        return;
    }

    my $download = $c->dbis->find_by_id( 'downloads', $downloads_id );

    if ( !$download )
    {
        die( "No such download" );
    }

    my $content_ref = MediaWords::DBI::Downloads::fetch_content( $download );

    if ( !$content_ref )
    {
        $content_ref = \"no content available for this download";
    }

    my $encoded_content = Encode::encode( 'utf-8', $$content_ref );
 
    $c->response->content_type( 'text/plain; charset=utf8' );    
    $c->response->content_length( length( $encoded_content ) );
    $c->response->body( $encoded_content );
}

sub view_extracted : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    if ( !$downloads_id )
    {
        $c->response->redirect( $c->uri_for( '/downloads/list', { error_msg => 'no download specified' } ) );
        return;
    }

    my $download_text = $c->dbis->select( 'download_texts', '*', { downloads_id => $downloads_id } )->hash;

    if ( !$download_text )
    {
        die( "No such download" );
    }

    $c->response->content_type( 'text/plain' );
    $c->response->content_length( 2 * length( $download_text->{ download_text } ) );

    #    $c->response->content_length( 10 * length(decode("utf8", $download_text->{download_text}) ));
    $c->response->body( $download_text->{ download_text } );
}

# get random download to extract
sub get_random_download
{
    my ( $self, $c ) = @_;

    my ( $downloads_id ) = $c->dbis->query( "select max(downloads_id) from downloads" )->flat;
    $downloads_id = int( $downloads_id * rand() * .9 );

    my $download;
    while ( !$download )
    {
        $download =
          $c->dbis->query( "select * from downloads where type = 'content' and state = 'success' and downloads_id = ?",
            $downloads_id++ )->hash;
    }

    return $download;
}

sub get_high_priority_download
{
    my ( $self, $c ) = @_;

    return $self->_get_download_from_less_trained_media_source( $c );
}

#get a download from one of the ten media sources with the fewest downloads already trained
sub _get_download_from_less_trained_media_source
{
    my ( $self, $c ) = @_;

    my $query_get_download_from_media_sources_with_fewest_downloads =
"select * from downloads, (SELECT stories_id, media_id from stories where stories.media_id in (select media_id from media_adjusted_extractor_training_downloads_count order by count limit 10) limit 150) as stories_to_train where downloads.stories_id=stories_to_train.stories_id and state='success' and type='content' limit 100";

    my $downloads = $c->dbis->query( $query_get_download_from_media_sources_with_fewest_downloads )->hashes;

    #evil hack until I can figure out why the above media aren't working
    if ( scalar( @{ $downloads } ) == 0 )
    {
        $downloads = $c->dbis->query(
"SELECT downloads.* from downloads, stories where type='content' and state='success' and stories.stories_id=downloads.stories_id and stories.media_id in (select media_id from (select * from media_adjusted_extractor_training_downloads_count order by count limit 20) as media_20 order by count desc limit 15) limit 100"
        )->hashes;
    }

    #Randomly pick one of the high priority downloads.
    #We use random so that the trainer can skip downloads.
    my $download = $downloads->[ int( rand( scalar( @{ $downloads } - 1 ) ) ) ];

    return $download;
}

# display form to manually extract text from one randomly chosen story
sub mextract_random : Local
{
    my ( $self, $c ) = @_;

    my $downloads_id = $self->get_random_download( $c );

    $c->response->redirect( $c->uri_for( '/downloads/mextract/' . $downloads_id->{ downloads_id } ) );
}

sub redownload : Local
{
    my ( $self, $c, $download_id ) = @_;

    say STDERR "starting redownload";
    my ( $download );

    if ( $download_id )
    {
        my $crawler_engine = MediaWords::Crawler::Engine->new();

        $download = $c->dbis->find_by_id( 'downloads', $download_id );
        my $response = MediaWords::Crawler::Fetcher::do_fetch( $download, $c->dbis );
        my $handler = MediaWords::Crawler::Handler->new( $crawler_engine );

        $handler->handle_response( $download, $response );
    }

    say STDERR "Finished download";

}

# display form to manually extract text from one randomly chosen story
sub mextract : Local
{
    my ( $self, $c, $download_id ) = @_;

    my ( $download, $next_training_download );
    if ( $download_id )
    {
        $download = $c->dbis->find_by_id( 'downloads', $download_id );
        $download->{ extractor_training_lines } =
          $c->dbis->query( "select * from extractor_training_lines where downloads_id = ?", $download_id )->hashes;

        my $current_training_download_id = $download_id;
        if ( !@{ $download->{ extractor_training_lines } } )
        {
            $current_training_download_id = 0;
        }

        $next_training_download = $c->dbis->query(
            'select * from downloads where downloads_id = ' . '(select a.downloads_id from extractor_training_lines a ' .
              'where a.downloads_id > ? ' . 'order by a.downloads_id asc limit 1)',
            $current_training_download_id
        );

    }
    else
    {
        $download = $self->get_high_priority_download( $c );
        $download->{ extractor_training_lines } =
          $c->dbis->query( "select * from extractor_training_lines where downloads_id = ?", $download_id )->hashes;
    }

    $download->{ story }  = $c->dbis->find_by_id( 'stories', $download->{ stories_id } );
    $download->{ medium } = $c->dbis->find_by_id( 'media',   $download->{ story }->{ media_id } );

    my $has_extractor_training_lines_scores = @{ $download->{ extractor_training_lines } } > 0;

    my $story_lines_lookup = {};
    for my $line ( @{ $download->{ extractor_training_lines } } )
    {
        $story_lines_lookup->{ $line->{ line_number } } = $line->{ required } ? 'required' : 'optional';
    }

    my $extract = MediaWords::DBI::Downloads::extractor_results_for_download( $c->dbis, $download );

    my $lines  = $extract->{ download_lines };
    my $scores = $extract->{ scores };

    my $developer_ui_param = $c->request->param( 'developer_ui' );

    if ( defined( $developer_ui_param ) )
    {
        if ( $developer_ui_param )
        {
            print STDERR "Setting flash - 1\n";
            $c->flash->{ developer_ui } = 1;
        }
        else
        {
            $c->flash->{ developer_ui } = 0;
        }
    }

    my $developer_ui = $c->flash->{ developer_ui } || '';

    $self->keepMextractFlashSettings( $c );

    print STDERR ( $c->flash->{ developer_ui } || '' ) . ' ' . $developer_ui . "\n";

    if ( !$developer_ui )
    {
        $c->stash->{ hide_explanation }    = 1;
        $c->stash->{ hide_html_densities } = 1;
        $c->stash->{ hide_html }           = 1;

        #	$c->clear_flash;
    }
    else
    {

        #	print STDERR "Setting flash\n";
        #	 $c->flash->{developer_ui} = 1;
    }

    $c->stash->{ download }                            = $download;
    $c->stash->{ lines }                               = $lines;
    $c->stash->{ next_training_download }              = $next_training_download;
    $c->stash->{ story_lines_lookup }                  = $story_lines_lookup;
    $c->stash->{ has_extractor_training_lines_scores } = $has_extractor_training_lines_scores;
    $c->stash->{ scores }                              = $scores;
    $c->stash->{ template }                            = 'downloads/mextract.tt2';
}

# store the results of the manual extraction and forward to another extraction form
sub mextract_do : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    if ( !$downloads_id )
    {
        die( "no downloads_id" );
    }

    my @required_line_numbers = $c->request->param( 'required_line_numbers' );
    my @optional_line_numbers = $c->request->param( 'optional_line_numbers' );

    my $submitter_name = $c->request->param( 'submitter_name' );

    if ( defined( $submitter_name ) )
    {

        #TODO modularize parameter sanitation into a utility class or find a module
        $submitter_name = lc( $submitter_name );
        my $allowed_characters = '\w_ ';
        $submitter_name =~ s/[^$allowed_characters]/_/g;

        $c->flash->{ submitter_name } = $submitter_name;
        $c->keep_flash( ( 'submitter_name' ) );
    }

    $c->keep_flash( ( 'submitter_name' ) );

    $c->keep_flash( ( 'developer_ui' ) );

    print STDERR "submitter_name = $submitter_name\n";

    $c->dbis->query( "delete from extractor_training_lines where downloads_id = ?", $downloads_id );

    my $submitter_string = $c->flash->{ submitter_name } || $c->req->address;

    for my $line_number ( @required_line_numbers )
    {
        $c->dbis->create(
            'extractor_training_lines',
            {
                downloads_id => $downloads_id,
                required     => 't',
                time         => DateTime->now,
                submitter    => $submitter_string,
                line_number  => $line_number
            }
        );
    }
    for my $line_number ( @optional_line_numbers )
    {
        $c->dbis->create(
            'extractor_training_lines',
            {
                downloads_id => $downloads_id,
                required     => 'f',
                time         => DateTime->now,
                submitter    => $submitter_string,
                line_number  => $line_number
            }
        );
    }

    $c->stash->{ status_msg } = 'Thanks. And again!';
    $c->response->redirect( $c->uri_for( '/downloads/mextract/' . $downloads_id, { status_msg => 'Done.' } ) );
}

sub keepMextractFlashSettings
{
    my ( $self, $c ) = @_;

    $c->keep_flash( ( 'developer_ui' ) );
    $c->keep_flash( ( 'submitter_name' ) );
    $c->keep_flash( ( 'translation' ) );
    $c->keep_flash( ( 'no_autoexclude' ) );

    return;
}

sub changeMextractSetting
{
    my ( $self, $c, $downloads_id, $setting, $value, $message ) = @_;

    $c->stash->{ status_msg } = $message;
    $c->flash->{ $setting } = $value;

    $self->keepMextractFlashSettings( $c );

    $c->response->redirect( $c->uri_for( '/downloads/mextract/' . $downloads_id ) );
}

# store the results of the manual extraction and forward to another extraction form
sub useTrainerUI : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    $self->changeMextractSetting( $c, $downloads_id, 'developer_ui', 0, 'Enabling trainer UI!' );
}

# store the results of the manual extraction and forward to another extraction form
sub useDeveloperUI : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    $self->changeMextractSetting( $c, $downloads_id, 'developer_ui', 1, 'Enabling developer UI!' );
}

sub disable_translation : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    $self->changeMextractSetting( $c, $downloads_id, 'translation', 0, 'Disabling translation!' );
}

sub enable_translation : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    $self->changeMextractSetting( $c, $downloads_id, 'translation', 1, 'Enabling translation!' );
}

sub enable_autoexclude : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    $self->changeMextractSetting( $c, $downloads_id, 'no_autoexclude', 0, 'Enabling autoexclude!' );
}

sub disable_autoexclude : Local
{
    my ( $self, $c, $downloads_id ) = @_;

    $self->changeMextractSetting( $c, $downloads_id, 'no_autoexclude', 1, 'Disabling autoexclude!' );
}

1;
