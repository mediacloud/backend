package MediaWords::MyFCgiManager;
use Moose;
use namespace::autoclean;
use FCGI::ProcManager;

has '_fcgi_procmanager' => (
    is => 'ro',
    isa => 'FCGI::ProcManager',
    handles => qr/.*/,
);

around BUILDARGS => sub {
    my $orig = shift;
    my $class = shift;
    my $ret = $class->$orig(_fcgi_procmanager => FCGI::ProcManager->new(@_));

    $ret->{die_timeout} = 2;

    return $ret;
};

no Moose;
__PACKAGE__->meta->make_immutable;
