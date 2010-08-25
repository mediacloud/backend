use inc::Module::Install;

name 'MediaWords';
all_from 'lib/MediaWords.pm';

requires 'Catalyst::Runtime' => '5.7012';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Action::RenderView';
requires 'YAML';    # This should reflect the config file format you've chosen
                    # See Catalyst::Plugin::ConfigLoader for supported formats
catalyst;

install_script glob( 'script/*.pl' );
auto_install;
WriteAll;
