#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
$Data::Dumper::Indent   = 1;
$Data::Dumper::Deepcopy = 1;
$Data::Dumper::Sortkeys = 1;
$Data::Dumper::Terse    = 1;
sub p(@) {
    my $d =  Dumper(\@_);
    $d    =~ s/\\x{([0-9a-z]+)}/chr(hex($1))/ge;
    warn $d;
}

use Log::Minimal;
use Carp;

my $INTER_SOCK_NAME  = "\0"."poolme"; # abstract namespace

my $Max_Loop_Count = 2;

sub step() {
    print "type any key to proceed: ";
    <STDIN>;
}

MAIN: {
    infof("starting $$");

    my $pool = ConnectionPool::Helper->new(
        sock_name => $INTER_SOCK_NAME,
    );

    for my $count (1 .. $Max_Loop_Count) {
        my $pool_id = 'memd/local';

        infof("get connection of $pool_id");
        my $conn = $pool->get(
            id => $pool_id,
        );

        infof("send 'get' command to memcached");
        $conn->print("get foo\r\n");
        $conn->flush;
        while (defined($_ = $conn->getline)) {
            infof($_);
            last if /END/;
        }
        step;

        infof("release connection of $pool_id");
        $pool->release(
            id         => $pool_id,
            connection => $conn,
        );
        step;
    }

    exit;
}

package
    ConnectionPool::Helper;

use strict;
use warnings;

use Log::Minimal;
use Carp;

use IO::FDPass;
use IO::Socket::UNIX;
use Smart::Args;

sub new {
    args(
        my $class,
        my $sock_name => { isa => 'Str' },
    );

    ### prepare unix domain socket for inter-process communication
    my $sock = IO::Socket::UNIX->new(
        Type   => SOCK_STREAM,
        Peer   => $sock_name,
    )
        or die "failed to create inter sock: $!";

    my $self = bless {
        sock_name => $sock_name,
        sock      => $sock,
        lent      => {},
    }, $class;

    return $self;
}

sub get {
    args(
        my $self,
        my $id => { isa => 'Str' },
    );

    my $cmd = "get $id";
    $self->_send_cmd(cmd => $cmd);

    my $fd = IO::FDPass::recv($self->{sock}->fileno);
    $fd >= 0 or croak "failed to recv fd: $!";

    my $conn = IO::Socket->new_from_fd($fd, 'r+');

    $self->{lent}{$id}{scalar($conn)} = $conn;

    return $conn;
}

sub release {
    args(
        my $self,
        my $id         => { isa => 'Str' },
        my $connection => { isa => 'IO::Socket' },
    );

    my $cmd = "release $id";
    $self->_send_cmd(cmd => $cmd);

    IO::FDPass::send($self->{sock}->fileno, fileno($connection))
            or croak "failed to send fd: $!";

    if ($self->{lent}{$id}{scalar($connection)}) {
        delete $self->{lent}{$id}{scalar($connection)};
    }

    return;
}

sub _send_cmd {
    args(
        my $self,
        my $cmd => { isa => 'Str' },
    );

    my $msg = pack('N', length($cmd)).$cmd;
    $self->{sock}->send($msg) or croak "failed to send command: $!";
}

sub DESTROY {
    args(
        my $self,
    );

    for my $id (keys %{ $self->{lent}}) {
        for my $conn (values %{ $self->{lent}{$id} }) {
            debugf("release in DESTROY: %s %s", $id, scalar($conn));
            $self->release(id => $id, connection => $conn);
        }
    }
}


__END__

# for Emacsen
# Local Variables:
# mode: cperl
# cperl-indent-level: 4
# cperl-close-paren-offset: -4
# cperl-indent-parens-as-block: t
# indent-tabs-mode: nil
# coding: utf-8
# End:

# vi: set ts=4 sw=4 sts=0 et ft=perl fenc=utf-8 :
