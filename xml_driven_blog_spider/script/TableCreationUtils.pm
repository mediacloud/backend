package TableCreationUtils;

use base 'Exporter';
our @EXPORT = qw (execute_query);

use strict;
use warnings;


my $_tags_id_black_list;

my @_banned_tags =   (
                      'usd', 
                      'browser software',
                      'web browser',
                      'external internet sites',
                      'external internet',
                      'usd',
                      'reuters',
                      'thomson reuters',
                      'personal finance',
                      'technology news',
                      'javascript',
                     );

sub is_black_listed_tag
{
    (my $tags_id) = @_;

    if (!defined($_tags_id_black_list))
    {
        _define_tags_id_black_list();
    }

    return $_tags_id_black_list->{$tags_id};
}

sub _define_tags_id_black_list
{
   if (!defined($_tags_id_black_list))
   {
       my $dbh = DBIx::Simple::MediaWords->connect(MediaWords::DB::connect_info)
           || die DBIx::Simple::MediaWords->error;
       
       foreach my $black_list_tag_name (@_banned_tags)
       {
           my $black_list_tag_ids = $dbh->query( "select tags_id from tags where tag = ?", $black_list_tag_name)->flat;
           
           die unless defined($black_list_tag_ids);
           
           foreach my $black_list_tag_id (@{$black_list_tag_ids}) 
           {
               $_tags_id_black_list->{$black_list_tag_id} = 1;
           }
       }
   }    
}

sub get_universally_black_listed_tags_ids
{
    if (!defined($_tags_id_black_list))
    {
        _define_tags_id_black_list();
    }    

    return keys %{$_tags_id_black_list};
}

sub get_database_handle
{
    my @connect_info =  (MediaWords::DB::connect_info());
    my $tmp = \@connect_info;
    $tmp->[3]->{RaiseError} = 1;

    my $db = DBIx::Simple::MediaWords->connect( @connect_info ) || die DBIx::Simple::MediaWords->error;
    return $db;
}

sub execute_query
{
    my ($query) = @_;

    my $dbh = get_database_handle();

    print STDERR "Starting to execute query: \"$query\"  -- " . localtime() . "\n";

    $dbh->query($query);

    print STDERR "Finished executing query: \"$query\"  -- " . localtime() . "\n";
}


sub list_contains
{
    ( my $value, my $list ) = @_;

    return any { $_ eq $value } @{$list};
}
