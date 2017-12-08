#!/usr/bin/env perl
#
# Import Archive.org TV captions using a directory with SRT files
#
# Usage:
#
#     ./script/run_in_env.sh \
#         ./script/mediawords_import_archive_org_tv_captions.pl \
#         --directory_path=/Users/pypt/Downloads/results/ \
#         --media_id=1
#

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Getopt::Long;
use Readonly;

use MediaWords::ImportStories::ArchiveOrgTVCaptions;

sub main
{
    my ( $directory_path, $media_id );
    Readonly my $usage => <<EOF;
Usage: $0 --directory_path=directory/with/srt/files/ --media_id=archive_org_media_id
EOF
    Getopt::Long::GetOptions(
        "directory_path=s" => \$directory_path,    #
        "media_id=s"       => \$media_id,          #
    ) or die $usage;
    unless ( $directory_path and $media_id )
    {
        die $usage;
    }

    my $db = MediaWords::DB::connect_to_db();

    my $import = MediaWords::ImportStories::ArchiveOrgTVCaptions->new(
        db             => $db,
        media_id       => $media_id,
        directory_path => $directory_path,
    );

    my $import_stories;
    eval { $import_stories = $import->scrape_stories() };
    die( $@ ) if ( $@ );

    my $num_module_stories = scalar( @{ $import->module_stories } );
    my $num_import_stories = scalar( @{ $import_stories } );

    INFO "Archive.org TV captions import results:";
    INFO "* $num_module_stories feedly stories,";
    INFO "* $num_import_stories stories imported.";
}

main();
