#!/usr/bin/env perl
#
# Import Archive.org TV captions using a directory with SRT files
#
# Usage:
#
# ./script/run_in_env.sh \
#     ./script/mediawords_import_archive_org_tv_captions.pl \
#     --directory_path=/Users/pypt/Downloads/results/
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Data::Dumper;
use File::Basename ();
use Getopt::Long;
use List::MoreUtils qw/ uniq /;
use Readonly;
use URI::Escape;

use MediaWords::ImportStories::ArchiveOrgTVCaptions;

sub main
{
    my $directory_path;
    Readonly my $usage => "Usage: $0 --directory_path=directory/with/srt/files/";
    Getopt::Long::GetOptions( "directory_path=s" => \$directory_path ) or die $usage;
    unless ( $directory_path )
    {
        die $usage;
    }

    my $db = MediaWords::DB::connect_to_db();

    my $srt_files = [ glob( $directory_path . '/*.srt' ) ];
    if ( scalar( @{ $srt_files } ) == 0 )
    {
        LOGCONFESS "No SRT files found in $directory_path.";
    }

    # Get unique channel names
    my $channel_names = [];

    foreach my $srt_file ( @{ $srt_files } )
    {
        my @exts = qw/.srt/;
        my ( $episode_id, $dir, $ext ) = File::Basename::fileparse( $srt_file, @exts );

        unless ( $episode_id =~ /_tva$/ )
        {
            LOGCONFESS "File '$episode_id' doesn't end with '_tva'";
        }

        $episode_id =~ s/_tva$//;

        my ( $channel_name, $episode_date, $episode_time, $show_name ) =
          $episode_id =~ /^(.+?)_(\d{8})_(\d{6})_([\w_\-\.]+?)$/;
        DEBUG "Processing $channel_name - $show_name - $episode_date - $episode_time...";

        push( @{ $channel_names }, $channel_name );
    }

    $channel_names = [ uniq @{ $channel_names } ];

    INFO "Channel names: " . Dumper( $channel_names );

    # Create media for channels
    my $media_tagset = $db->find_or_create(
        'tag_sets',
        {
            'name'        => 'Archive.org',
            'label'       => 'Archive.org',
            'description' => 'Data from Archive.org',
        }
    );

    my $media_tag = $db->find_or_create(
        'tags',
        {
            'tag_sets_id' => $media_tagset->{ 'tag_sets_id' },
            'tag'         => 'Archive.org TV',
            'label'       => 'Archive.org TV',
            'description' => 'Archive.org TV captions',
        }
    );
    my $media_feeds_tags_id = $media_tag->{ 'tags_id' };

    foreach my $channel_name ( @{ $channel_names } )
    {

        INFO "Processing channel '$channel_name'...";

        my $medium_name = "Archive.org TV captions: $channel_name";
        my $medium_url  = "https://archive.org/details/tv#" . uri_escape( $channel_name );
        my $medium      = $db->find_or_create(
            'media',
            {
                'name'          => $medium_name,
                'url'           => $medium_url,
                'full_text_rss' => 't',
            }
        );
        my $media_id = $medium->{ 'media_id' };

        $db->find_or_create(
            'media_tags_map',
            {
                'media_id' => $media_id,
                'tags_id'  => $media_feeds_tags_id,
            }
        );

        my $directory_glob = $directory_path . '/' . $channel_name . '_*.srt';
        INFO "Importing files '$directory_glob' to channel '$channel_name'...";

        my $import = MediaWords::ImportStories::ArchiveOrgTVCaptions->new(
            db             => $db,
            media_id       => $media_id,
            directory_glob => $directory_glob,
        );

        my $import_stories;
        eval { $import_stories = $import->scrape_stories() };
        die( $@ ) if ( $@ );

        my $num_module_stories = scalar( @{ $import->module_stories } );
        my $num_import_stories = scalar( @{ $import_stories } );

        INFO "Archive.org TV captions import results for channel '$channel_name':";
        INFO "* $num_module_stories feedly stories,";
        INFO "* $num_import_stories stories imported.";
    }
}

main();
