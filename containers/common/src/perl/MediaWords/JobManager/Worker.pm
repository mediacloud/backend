package MediaWords::JobManager::Worker;

#
# Worker helpers
#

use strict;
use warnings;
use Modern::Perl "2015";

use MediaWords::JobManager;

use Log::Log4perl qw(:easy);
Log::Log4perl->easy_init( { level => $DEBUG, utf8 => 1, layout => "%d{ISO8601} [%P]: %m%n" } );

# Import function Perl module by path or name
sub import_function($)
{
    my ( $path_or_name ) = shift;

    eval {
        if ( $path_or_name =~ /\.pm$/ )
        {
            # /somewhere/Foo/Bar.pm

            # Expect the package to return its name so that we'll know how to call it:
            # http://stackoverflow.com/a/9850017/200603
            $path_or_name = require $path_or_name;
            if ( $path_or_name . '' eq '1' )
            {
                LOGDIE( "The function package should return __PACKAGE__ at the end of the file instead of just 1." );
            }
            $path_or_name->import();
            1;
        }
        else
        {
            # Foo::Bar
            ( my $file = $path_or_name ) =~ s|::|/|g;
            require $file . '.pm';
            $path_or_name->import();
            1;
        }
    } or do
    {
        LOGDIE( "Unable to find function in '$path_or_name': $@" );
    };

    return $path_or_name;
}

# Run worker
sub start_worker($)
{
    my ( $function_name_or_path ) = @_;

    my $function_name = import_function( $function_name_or_path );
    my $broker = MediaWords::AbstractJob::broker();

    INFO( "Starting function '$function_name' from '$function_name_or_path'." );

    $broker->start_worker( $function_name );

    INFO( "Done." );
}

1;
