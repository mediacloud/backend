package MediaWords::Test::Data;

# store and fetch testing data

use strict;
use warnings;

BEGIN
{
    use FindBin;
    use lib "$FindBin::Bin/../lib";
    use lib $FindBin::Bin;
}

use File::Basename;
use Data::Dumper;

# get path to where data file(s) should be stored
sub _get_path_to_data_files(;$)
{
    my $subdirectory = shift;

    $subdirectory //= '';

    my $path = "$FindBin::Bin/../t/data/$subdirectory/";

    unless ( -d $path )
    {
        die "Test data file path '$path' is not a directory (or doesn't exist at all).";
    }

    return $path;
}

sub _get_data_file_extension()
{
    return '.pl';
}

# get the file path corresponding to the given basename
sub _get_data_file($;$)
{
    my ( $basename, $subdirectory ) = @_;

    $subdirectory //= '';

    if ( $basename =~ /[^a-z0-9_]/i )
    {
        die "Test data basename can only include /[a-z0-9_]/i";
    }

    return _get_path_to_data_files( $subdirectory ) . "/$basename" . _get_data_file_extension();
}

# write the given data to disk under the given basename
sub store_test_data($$;$)
{
    my ( $basename, $data, $subdirectory ) = @_;

    my $file = _get_data_file( $basename, $subdirectory );

    {
        # Make sure that results can be eval{}-ed
        local $Data::Dumper::Purity = 1;

        # Sort hash keys so that Git commit diffs will look more concise afterwards
        local $Data::Dumper::Sortkeys = 1;

        open( FILE, ">$file" ) or die "Unable to open file $file: $!";

        print FILE "#<<<\n";
        print FILE Dumper( $data );
        print FILE "#>>>\n";

        close( FILE );
    }
}

# Write the given data to disk under the given basename; split the data
# (hashref) into individual files (indexed by hashref's key).
# The subroutine expects hashref instead of arrayref because:
# 1. Indices (e.g. stories_id) should be unique, and the caller should be aware
#    of that.
# 2. Data will be later returned as a set, i.e. the keys (indices) will be
#    unordered; the caller should expect that too.
sub store_test_data_to_individual_files($$)
{
    my ( $basename, $data_hashref ) = @_;

    unless ( ref( $data_hashref ) eq ref( {} ) )
    {
        die "Data for basename $basename is not an hashref.";
    }

    # Remove all files before overwriting them (in case the new unit test
    # contains *less* stories, we don't want old files lying around)
    my $glob_path_to_old_data_files = _get_path_to_data_files( $basename ) . '/*' . _get_data_file_extension();
    my @old_data_files              = glob( $glob_path_to_old_data_files );

    # say STDERR "Will remove old data files at path '$glob_path_to_old_data_files': " . Dumper(\@old_data_files);
    unlink @old_data_files or die "Unable to unlink old data files: $!; files: " . Dumper( \@old_data_files );

    # Write hashref to files
    foreach my $index ( keys %{ $data_hashref } )
    {
        store_test_data( $index, $data_hashref->{ $index }, $basename );
    }
}

# fetch the given data from disk
sub fetch_test_data($;$)
{
    my ( $basename, $subdirectory ) = @_;

    my $file = _get_data_file( $basename, $subdirectory );

    open( FILE, "<$file" ) or die "Unable to open file $file: $!";

    my $data;
    while ( my $line = <FILE> )
    {
        $data .= $line;
    }

    close( FILE );

    my $VAR1;
    eval( $data );
    if ( $@ )
    {
        die( "error restoring data: $@" );
    }

    return $VAR1;
}

# Fetch the given data from disk under the given basename; join the data from
# individual files into a hashref (indexed by each test data file's filename).
# The subroutine returns hashref instead of arrayref because:
# 1. Indices (e.g. stories_id) should be unique, and the caller should be aware
#    of that.
# 2. Data is returned as a set, i.e. the keys (indices) are unordered; the
# caller should expect that too.
sub fetch_test_data_from_individual_files($)
{
    my $basename = shift;

    my $glob_path_to_data_files = _get_path_to_data_files( $basename ) . '/*' . _get_data_file_extension();
    my @data_files              = glob( $glob_path_to_data_files );

    my %data_hash;

    foreach my $data_file ( @data_files )
    {
        my $index = basename( $data_file, _get_data_file_extension() );
        unless ( $index )
        {
            die "Index is null for data file $data_file";
        }

        $data_hash{ $index } = fetch_test_data( $index, $basename );
    }

    return \%data_hash;
}

1;
