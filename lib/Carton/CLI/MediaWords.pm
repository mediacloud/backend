package Carton::CLI::MediaWords;

use parent( 'Carton::CLI' );

sub cmd_exec {
    my($self, @args) = @_;

    # allows -Ilib
    @args = map { /^(-[I])(.+)/ ? ($1,$2) : $_ } @args;

    #print "cmd_exec override\n";

    my $system; # for unit testing
    my @include;
    $self->parse_options(\@args, 'I=s@', \@include, "system", \$system);

    my $path = $self->carton->{path};
    my $lib  = join ",", @include, "$path/lib/perl5", ".";

    my $carton_extra_perl5opt =  $ENV{CARTON_EXTRA_PERL5OPT} // '';

    #print "Extra $carton_extra_perl5opt\n";

    local $ENV{PERL5OPT} = "-Mlib::core::only -Mlib=$lib $carton_extra_perl5opt";
    local $ENV{PATH} = "$path/bin:$ENV{PATH}";

    $system ? system(@args) : exec(@args);
}

1;
