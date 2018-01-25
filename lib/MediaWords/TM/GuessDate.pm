package MediaWords::TM::GuessDate;

use strict;
use warnings;

use Modern::Perl "2015";
use MediaWords::CommonLibs;

use MediaWords::TM::GuessDate::Result;

{

    package MediaWords::TM::GuessDate::PythonProxy;

    use strict;
    use warnings;

    use Modern::Perl "2015";
    use MediaWords::CommonLibs;    # set PYTHONPATH too

    import_python_module( __PACKAGE__, 'mediawords.tm.guess_date' );

    1;
}

# Guess the date for the story. returns MediaWords::TM::GuessDate::Result object.
sub guess_date($$)
{
    my ( $story_url, $html ) = @_;

    my $python_result;
    eval { $python_result = MediaWords::TM::GuessDate::PythonProxy::guess_date( $story_url, $html ); };
    if ( $@ )
    {
        LOGCONFESS "Date guesser died while guessing date for URL $story_url: $@";
    }

    my $result = MediaWords::TM::GuessDate::Result->new();

    if ( $python_result->{ found } )
    {
        $result->{ result } = $MediaWords::TM::GuessDate::Result::FOUND;
    }
    else
    {
        $result->{ result } = $MediaWords::TM::GuessDate::Result::NOT_FOUND;
    }

    $result->{ guess_method } = $python_result->{ guess_method };
    $result->{ timestamp }    = $python_result->{ timestamp };
    $result->{ date }         = $python_result->{ date };

    return $result;
}

1;
