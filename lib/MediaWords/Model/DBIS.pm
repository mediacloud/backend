package MediaWords::Model::DBIS;
use Modern::Perl "2013";
use MediaWords::CommonLibs;

# custom DBIx::Simple::MediaWords based model for mediawords

use strict;

use DBIx::Simple::MediaWords;

use MediaWords::DB;

use base qw(Catalyst::Model);

sub new
{
    my $self = shift->SUPER::new( @_ );

    my @info = @{ $self->{ connect_info } || [] };

    return $self;
}

sub dbis
{
    my ( $self ) = @_;

    my $db = $self->{ dbis };

    # we put an eval and print the error here b/c the web auth dies silently on a database error
    eval {
        if ( !$db || $db->dbh->state )
        {
            # TODO replace this with  MediaWords::DB::connect_to_db();
            $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
              || die DBIx::Simple::MediaWords->error;

            $db->dbh->{ RaiseError } = 1;

            ## UNCOMMENT to enable database profiling
            ## Eventually we may wish to make this a config option in mediawords.yml
            # $db->dbh->{ Profile }    = 2;

            $self->{ dbis } = $db;
        }
    };

    if ( $@ )
    {
        print STDERR "db error: $@\n";
        die( $@ );
    }

    return $db;
}

1;
