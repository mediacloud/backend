package MediaWords::Util::Config;

# Parse and return data from mediawords.yml config file.

# This code should be used instead of MediaWords->config in general, b/c
# MediaWords::Util::Config::get_config will work both from within and without
# catalyst (for instance in stand alone command line scripts).

# in the catalyst case, the core MediaWords script calls the set_config
# function to set the returned config object to the already generated
# config object for the app.

use strict;

use Config::Any;
use FindBin;

# cache config object so that it remains the same from call to call
my $_config;

sub get_config
{

    if ($_config)
    {
        return $_config;
    }
    else {
        my $config_file = "$FindBin::Bin/../mediawords.yml";
        #print "config:file: $config_file\n";
        $_config = Config::Any->load_files( { files => [ $config_file ], use_ext => 1} )
            ->[0]->{$config_file};
        set_defaults($_config);
    }
        
    return $_config;   
}

# set the cached config
sub set_config
{
    my ($config) = @_;

    if ($_config)
    {
        die("config object already cached");
    }

    $_config = $config;
    
    set_defaults($_config);
}

sub set_defaults 
{    
    my ($config) = @_;

    $config->{mediawords}->{data_dir} ||= "$ENV{HOME}/mediacloud/data";
    $config->{session}->{storage} ||= "$ENV{HOME}/tmp/mediacloud-session";
}

1;
