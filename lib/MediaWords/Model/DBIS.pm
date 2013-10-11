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

    return $self;
}

sub dbis
{

    # TODO replace this with  MediaWords::DB::connect_to_db();
    my $db = DBIx::Simple::MediaWords->connect( MediaWords::DB::connect_info )
      or die DBIx::Simple::MediaWords->error;

    $db->dbh->{ RaiseError } = 1;

    ## UNCOMMENT to enable database profiling
    ## Eventually we may wish to make this a config option in mediawords.yml
    # $db->dbh->{ Profile }    = 2;

    return $db;
}

1;
