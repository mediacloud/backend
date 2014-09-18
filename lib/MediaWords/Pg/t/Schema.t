use strict;
use warnings;

use utf8;
use Test::NoWarnings;
use Test::More tests => 34;

use Readonly;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";

    use_ok( 'MediaWords::Pg::Schema' );
}

sub test_postgresql_response_line_is_expected()
{
    # Expected PostgreSQL response lines
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'NOTICE: foo bar baz' ),                1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'CREATE TABLE' ),                       1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'ALTER TABLE' ),                        1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( "SET TIME ZONE 'Europe/Vilnius'" ),     1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( "COMMENT ON foo IS 'Bar'" ),            1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'INSERT INTO foo (...) VAlUES (...)' ), 1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( ' enum_add.foo' ),                      1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( '---------- Comment' ),                 1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( '    ' ),                               1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( '(123 rows)' ),                         1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( '(1 row)' ),                            1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( '' ),                                   1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'Time: 123 ms' ),                       1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'DROP LANGUAGE' ),                      1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'DROP VIEW' ),                          1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'DROP TABLE' ),                         1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'drop cascades to view "foo"' ),        1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'UPDATE 123' ),                         1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'DROP TRIGGER' ),                       1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'Timing is on.' ),                      1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'DROP INDEX' ),                         1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'psql-123: NOTICE: bar' ),              1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'DELETE' ),                             1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'SELECT 0' ),                           1 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'DROP FUNCTION' ),                      1 );

    # Unexpected PostgreSQL response lines
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'SELECT' ),                        0 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'UPDATE foo' ),                    0 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'BEGIN' ),                         0 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'COMMIT' ),                        0 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'Here goes some unknown notice' ), 0 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( 'enum_add.foo' ),                  0 );
    is( MediaWords::Pg::Schema::postgresql_response_line_is_expected( '-- Comment' ),                    0 );
}

sub main()
{
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    test_postgresql_response_line_is_expected();
}

main();
