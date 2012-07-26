package MediaWords::Model::DBIS;
use Modern::Perl "2012";
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

    # TODO replace this with  MediaWords::DB::connect_to_db();
    $self->{ dbis } = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      or die DBIx::Simple::MediaWords->error;

    $self->{ dbis }->dbh->{ RaiseError } = 1;

    return $self;
}

sub dbis
{

    return $_[ 0 ]->{ dbis };
}

1;
