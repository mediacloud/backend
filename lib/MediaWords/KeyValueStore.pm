package MediaWords::KeyValueStore;

# abstract class for storing / loading objects (raw downloads, CoreNLP annotator results, ...) to / from various storage locations

use strict;
use warnings;

use Moose::Role;

use Modern::Perl "2013";
use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use MediaWords::Util::Compress;

#
# Required methods
#

# Moose constructor; reads generic connection properties (e.g. host, username,
# password) from Media Cloud configuration itself, but expects to be provided
# with a *specific* destination to write to (e.g. database name, table name,
# S3 bucket and path prefix) as an argument
requires 'BUILD';

# Fetch content; returns reference to content on success; returns empty string
# and dies on error
requires 'fetch_content';

# Store content; returns path to content on success; returns empty string and
# dies on error
requires 'store_content';

# Remove content; returns true if removal was successful, dies on error (e.g.
# when the content doesn't exist)
requires 'remove_content';

# Checks if content exists under a certain key; returns true if it does, false
# if it doesn't, dies on error
requires 'content_exists';

# Helper to encode and gzip content
#
# Parameters: content ref; content's identifier, e.g. download ID (optional)
# Returns: gzipped content on success, dies on error
sub encode_and_gzip($$;$)
{
    my ( $self, $content_ref, $content_id ) = @_;

    my $encoded_and_gzipped_content;
    eval { $encoded_and_gzipped_content = MediaWords::Util::Compress::encode_and_gzip( $$content_ref ); };
    if ( $@ or ( !defined $encoded_and_gzipped_content ) )
    {
        if ( $content_id )
        {
            die "Unable to gzip content for identifier '$content_id': $@";
        }
        else
        {
            die "Unable to gzip content: $@";
        }

    }

    return $encoded_and_gzipped_content;
}

# Helper to gunzip and decode content
#
# Parameters: gzipped content; content's identifier, e.g. download ID (optional)
# Returns: gunzipped content on success, dies on error
sub gunzip_and_decode($$;$)
{
    my ( $self, $content_ref, $content_id ) = @_;

    my $gunzipped_and_decoded_content;
    eval { $gunzipped_and_decoded_content = MediaWords::Util::Compress::gunzip_and_decode( $$content_ref ); };
    if ( $@ or ( !defined $gunzipped_and_decoded_content ) )
    {
        if ( $content_id )
        {
            die "Unable to gunzip content for identifier '$content_id': $@";
        }
        else
        {
            die "Unable to gunzip content: $@";
        }
    }

    return $gunzipped_and_decoded_content;
}

no Moose;    # gets rid of scaffolding

1;
