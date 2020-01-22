use strict;
use warnings;
use utf8;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use Test::More;

use MediaWords::Util::Facebook;

# test _process_facebook_error
sub test_process_facebook_error()
{
    my $r = MediaWords::Util::Facebook::_process_facebook_error( undef, undef );
    is( $r->{ zero }, 1 );

    $r = MediaWords::Util::Facebook::_process_facebook_error( 'something went wrong', undef );
    is( $r->{ zero }, 1 );

    $r = eval { MediaWords::Util::Facebook::_process_facebook_error( 'non json content', undef ); };
    ok( $@ ); 

    $r = eval { MediaWords::Util::Facebook::_process_facebook_error( 'foo bar', { foo => 'bar' } ); };
    ok( $@ ); 

    MediaWords::Util::Facebook::_reset_consecutive_errors();

    MediaWords::Util::Facebook::_process_facebook_error( undef, undef );
    MediaWords::Util::Facebook::_process_facebook_error( undef, undef );
    MediaWords::Util::Facebook::_process_facebook_error( undef, undef );
    eval { MediaWords::Util::Facebook::_process_facebook_error( undef, undef ); };
    ok( $@ );
}

sub main()
{
    test_process_facebook_error();

    done_testing();
}

main();
