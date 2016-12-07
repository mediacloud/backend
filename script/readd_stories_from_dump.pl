#!/usr/bin/env perl
#

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Job::ExtractAndVector;
use MediaCloud::JobManager::Job;
use MediaWords::Util::JSON;

use Sys::RunAlone;

use Readonly;

sub main
{
    binmode( STDOUT, 'utf8' );
    binmode( STDERR, 'utf8' );

    unless ( $ARGV[ 0 ] )
    {
        die "Usage: $0 dump_dir/\n";
    }

    my $dump_dir = $ARGV[ 0 ];
    unless ( -d $dump_dir )
    {
        die "'$dump_dir' is not a directory.\n";
    }

    INFO "Dump directory: $dump_dir";
    foreach my $dump_file ( glob( "$dump_dir/*.txt" ) )
    {
        INFO "Dump file: $dump_file";
        open( my $fh, '<:encoding(UTF-8)', $dump_file ) or die "Could not open file '$dump_file': $!\n";
        while ( my $row = <$fh> )
        {
            chomp $row;
            if ( $row =~ /MediaWords::Job::ExtractAndVector/ )
            {
                my @columns = split( /\|/, $row );
                my $payload = $columns[ 4 ];
                chomp $payload;
                unless ( $payload =~ /errbacks/ )
                {
                    die "Payload looks incorrect: $payload\n";
                }

                my $payload_json = MediaWords::Util::JSON::decode_json( $payload );
                my $kwargs       = $payload_json->{ 'kwargs' };

                my $stories_id = $kwargs->{ 'stories_id' };
                unless ( $stories_id )
                {
                    die "Payload does not have 'stories_id': $payload\n";
                }

                my $skip_bitly_processing   = $kwargs->{ 'skip_bitly_processing' }   // 0;
                my $skip_corenlp_annotation = $kwargs->{ 'skip_corenlp_annotation' } // 0;

                INFO
"Readding story $stories_id with 'skip_bitly_processing': $skip_bitly_processing, 'skip_corenlp_annotation': $skip_corenlp_annotation...";

                my $args = { 'stories_id' => $stories_id + 0 };
                my $priority = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_NORMAL;
                if ( $skip_bitly_processing or $skip_corenlp_annotation )
                {
                    $args->{ 'skip_bitly_processing' }   = $skip_bitly_processing + 0;
                    $args->{ 'skip_corenlp_annotation' } = $skip_corenlp_annotation + 0;
                    $priority                            = $MediaCloud::JobManager::Job::MJM_JOB_PRIORITY_LOW;
                }

                MediaWords::Job::ExtractAndVector->add_to_queue( $args, $priority );
            }
        }
    }
}

main();

# Required by Sys::RunAlone
__END__
