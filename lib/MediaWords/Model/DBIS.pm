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

# hand out a database connection.  reuse the last connection unless the request has changed
# since the last call.
sub dbis
{
    my ( $self, $request ) = @_;

    my $db = $self->{ dbis };

    my $prev_req_id = $self->{ prev_req_id } || '';
    my $req_id = scalar( $request );

    return $db if ( $db && ( $req_id eq $prev_req_id ) );

    $self->{ prev_req_id } = $req_id;

    # we put an eval and print the error here b/c the web auth dies silently on a database error
    eval {
        $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
          || die DBIx::Simple::MediaWords->error;

        $db->dbh->{ RaiseError } = 1;
        $self->{ dbis } = $db;
    };
    if ( $@ )
    {
        print STDERR "db error: $@\n";
        die( $@ );
    }

    return $db;
}

1;
