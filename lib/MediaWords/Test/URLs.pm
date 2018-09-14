package MediaWords::Test::URLs;

=head1 NAME

MediaWords::Test::URLs - helper functions for comparing URLs in Perl unit tests

=cut

use strict;
use warnings;

require Test::Builder;

use MediaWords::Util::URL;

# Succeeds if URLs are deemed to be equal
sub is_urls($$;$)
{
    my ( $url1, $url2, $name ) = @_;

    my $tb = Test::Builder->new;

    if ( MediaWords::Util::URL::urls_are_equal( $url1, $url2 ) )
    {
        $tb->ok( 1, $name );
    }
    else
    {
        $tb->ok( 0, $name );
        $tb->diag( "URLs are not equal but are expected to be; URL #1: $url1; URL #2: $url2" );
    }
}

# Succeeds if URLs are deemed to not be equal
sub isnt_urls($$;$)
{
    my ( $url1, $url2, $name ) = @_;

    my $tb = Test::Builder->new;

    unless ( MediaWords::Util::URL::urls_are_equal( $url1, $url2 ) )
    {
        $tb->ok( 1, $name );
    }
    else
    {
        $tb->ok( 0, $name );
        $tb->diag( "URLs are equal but are not expected to be; URL #1: $url1; URL #2: $url2" );
    }
}

1;
