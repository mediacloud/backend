package MediaWords::Util::GuessDate;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::Util::GuessDate::Result;

{

    package MediaWords::Util::GuessDate::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.util.guess_date' );

    1;
}

# Guess the date for the story. returns MediaWords::Util::GuessDate::Result object.
sub guess_date($$)
{
    my ( $story_url, $html ) = @_;

    my $python_result;
    eval { $python_result = MediaWords::Util::GuessDate::PythonProxy::guess_date( $story_url, $html ); };
    if ( $@ )
    {
        LOGCONFESS "Date guesser died while guessing date for URL $story_url: $@";
    }

    my $result = MediaWords::Util::GuessDate::Result->new();

    if ( $python_result->{ found } )
    {
        $result->{ result } = $MediaWords::Util::GuessDate::Result::FOUND;
    }
    else
    {
        $result->{ result } = $MediaWords::Util::GuessDate::Result::NOT_FOUND;
    }

    $result->{ guess_method } = $python_result->{ guess_method };
    $result->{ timestamp }    = $python_result->{ timestamp };
    $result->{ date }         = $python_result->{ date };

    return $result;
}

1;
