package MediaWords::ImportStories::ArchiveOrgTVCaptions;

=head1 NAME

MediaWords::ImportStories::ArchiveOrgTVCaptions - import stories from Archive.org TV captions

=head2 DESCRIPTION

Import stories from a feedly feed.

In addition to ImportStories options, new accepts the following options:

=over

=item *

directory_glob - path (with wildcard) to the listing of SRT files

=back

=cut

use strict;
use warnings;

use Moose;
with 'MediaWords::ImportStories';

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::ParseJSON;
use MediaWords::Util::SQL;
use MediaWords::Util::Web;

use Data::Dumper;
use File::Basename ();

has 'directory_glob' => ( is => 'rw' );

=head2 get_new_stories( $self )

Get stories from directory with Archive.org's SRT files.

=cut

sub get_new_stories($)
{
    my ( $self ) = @_;

    my $stories = [];

    unless ( $self->directory_glob )
    {
        LOGCONFESS "'directory_glob' is not set.";
    }

    my $srt_files = [ glob $self->directory_glob ];
    if ( scalar( @{ $srt_files } ) == 0 )
    {
        LOGCONFESS 'No SRT files found in "' . $self->directory_glob . '"';
    }

    foreach my $srt_file ( @{ $srt_files } )
    {
        my @exts = qw/.srt/;
        my ( $episode_id, $dir, $ext ) = File::Basename::fileparse( $srt_file, @exts );

        unless ( $episode_id =~ /_tva$/ )
        {
            LOGCONFESS "File '$episode_id' doesn't end with '_tva'";
        }

        $episode_id =~ s/_tva$//;

        # INFO "Processing '$episode_id'...";

        my $archive_metadata_url = "https://archive.org/metadata/$episode_id";

        my $ua  = MediaWords::Util::Web::UserAgent->new();
        my $res = $ua->get( $archive_metadata_url );
        unless ( $res->is_success() )
        {
            LOGCONFESS "Import of '$episode_id' failed: " . Dumper( $res->decoded_content() );
        }

        my $metadata = MediaWords::Util::ParseJSON::decode_json( $res->decoded_content() );
        if ( length( keys( %{ $metadata } ) ) == 0 )
        {
            LOGCONFESS "Metadata for '$episode_id' is empty.";
        }

        my $channel_name     = $metadata->{ metadata }{ contributor };
        my $show_date        = $metadata->{ metadata }->{ start_time };
        my $show_name        = $metadata->{ metadata }->{ title };
        my $show_description = $metadata->{ metadata }->{ description };

        unless ( defined $channel_name and defined $show_date and defined $show_name and defined $show_description )
        {
            LOGCONFESS "Invalid metadata for '$episode_id': " . Dumper( $metadata );
        }

        my $show_captions = $metadata->{ $episode_id }->{ cc };
        unless ( $show_captions )
        {
            LOGCONFESS "Missing captions for '$episode_id': " . Dumper( $metadata );
        }

        # ">>>" at the beginning of text probably means "new subject"
        $show_captions =~ s/^>>>\s/\n\n/gs;
        $show_captions =~ s/^>>\s/\n\n/gs;    # typo by the transcriber?

        # ">>" probably means "new speaker"
        $show_captions =~ s/\s>>\s/\n\n/gs;
        $show_captions =~ s/\s>>>\s/\n\n/gs;    # typo by the transcriber?

        my $story = {
            url  => $archive_metadata_url,
            guid => $archive_metadata_url,

            media_id => $self->media_id,

            publish_date => $show_date,
            title        => $show_name,
            description  => $show_description,
            content      => $show_captions,
        };
        push( @{ $stories }, $story );
    }

    return $stories;
}

1;
