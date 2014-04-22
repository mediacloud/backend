#!/usr/bin/env perl

# retrieve and display the content from ten downloads to verify that content fetching is working

use strict;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use MediaWords::CommonLibs;

use MediaWords::Util::Config;
use Hash::Merge;
use Test::Deep::NoTest;

sub main
{
    #MediaWords::Util::Config::_dump_defaults_as_yaml();

    my $config = MediaWords::Util::Config::get_config();

    my $mw_yml = MediaWords::Util::Config::_parse_config_file( MediaWords::Util::Config::base_dir() . '/mediawords.yml' );

    my $defaults = MediaWords::Util::Config::_parse_config_file( MediaWords::Util::Config::base_dir() . '/config/defaults.yml' );

    my $merge = Hash::Merge->new('LEFT_PRECEDENT');

    my $merged = $merge->merge( $mw_yml, $defaults );

    my $mc_config_merged =  MediaWords::Util::Config::_parse_config_file( MediaWords::Util::Config::base_dir() . '/mc_config_merged.yml' );

    die unless eq_deeply( $mc_config_merged, $config );
    
    #YAML::DumpFile( 'mc_config_merged.yml', $config );

    #say Dumper( $merged );
}

main();
