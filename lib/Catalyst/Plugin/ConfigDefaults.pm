package Catalyst::Plugin::ConfigDefaults;

# local plugin to set default config values.

# this has to be done as a plugin to be run after the ConfigLoader plugin setup but before the other plugins
# (Session, for instance)

use strict;
use warnings;

use MRO::Compat;

sub setup
{
    my $c = shift;

    MediaWords::Util::Config::set_config( $c->config );

    $c->maybe::next::method();
}

1;
