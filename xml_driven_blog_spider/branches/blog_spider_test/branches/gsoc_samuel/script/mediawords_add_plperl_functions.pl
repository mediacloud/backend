#!/usr/bin/perl

# add plperl functions to database.

# to add a new function to the db
# * write the function with a new or existing MediaWords::Pg module
# * add the module, function, and number of parameters to $_functions
# * run this script to reload all functions

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
}

use DBIx::Simple::MediaWords;

use MediaWords::DB;

# module name, funciton name, number of parameters, and whether the function is a trigger functions
my $_functions = [
    [ 'MediaWords::Pg::StoryVectors', 'fill_story_sentence_words',      0, 'text' ],
    [ 'MediaWords::Pg::StoryVectors', 'update_story_sentence_words',    1, 'text' ],
    [ 'MediaWords::Pg::StoryVectors', 'update_aggregate_words',         0, 'text' ],
    [ 'MediaWords::Pg::StoryVectors', 'is_stop_stem',                   2, 'boolean' ],
    [ 'MediaWords::Pg::Cleanup',      'remove_duplicate_stories',       2, 'text' ],
];

my $_spi_functions = [
    qw/spi_exec_query spi_query spi_fetchrow spi_prepare spi_exec_prepared
      spi_query_prepared spi_cursor_close spi_freeplan elog/
];
my $_spi_constants = [qw/DEBUG LOG INFO NOTICE WARNING ERROR/];

sub main
{

    my $db = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info);

    for my $function ( @{$_functions} )
    {
        my ( $module, $function_name, $num_parameters, $return_type ) = @{$function};

        my ( $parameters, $args );
        if ($return_type eq 'trigger')
        {
            $parameters  = '';
            $args        = '$_TD';
        }
        else
        {
            $parameters = "TEXT," x $num_parameters;
            chop($parameters);
            $args        = '@_';
        }

        my $spi_functions = join( '', map { "    MediaWords::Pg::set_spi('$_', \\&$_);\n" } @{$_spi_functions} );
        my $spi_constants = join( '', map { "    MediaWords::Pg::set_spi('$_', $_);\n" } @{$_spi_constants} );

        my $sql = <<END
create or replace function $function_name ($parameters) returns $return_type as \$\$
    use lib "$FindBin::Bin/../lib";
    use MediaWords::Pg;
    use $module;
    
$spi_functions
$spi_constants
    
    return ${module}::${function_name}($args);
\$\$ language plperlu;
END
          ;

        print "/* ${module}::${function_name}(${parameters}) */\n$sql\n\n";
        $db->query($sql);

    }
}

main();
