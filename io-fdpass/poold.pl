#!/usr/bin/env perl

use strict;
use warnings;

use Getopt::Long qw(:config posix_default no_ignore_case no_ignore_case_always permute);
use Pod::Usage;
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

use AnyEvent;
use AnyEvent::Socket;
use IO::FDPass;
use IO::Socket::INET;

my $INTER_SOCK_NAME  = "\0"."poolme"; # abstract namespace

my $Debug = 0;

my %Connection_Pool;

my %Connection_Config = (
    'memd/local' => {
        start_connections => 3,
        addr              => '127.0.0.1:11211/tcp',
    },
);

MAIN: {
    GetOptions(
        'debug|d+' => \$Debug,
        'help|h|?' => sub { pod2usage(-verbose=>1) }) or pod2usage();
    $ENV{LM_DEBUG} = 1 if $Debug;
    debugf("Enable debug mode $$");

    infof("starting $$");

    ### connect and save into connection pool
    while (my($pool_id, $conn_config) = each %Connection_Config) {

        my($addr, $port, $proto) = ($conn_config->{addr} =~ m{^(.+?):([0-9]+)/(.+)$});
        infof("prepare connection for %s:%s/%s (%d)",
               $addr, $port, $proto,
               $conn_config->{start_connections},
           );

        for (1 .. $conn_config->{start_connections}) {
            push @{ $Connection_Pool{$pool_id} }, IO::Socket::INET->new(
                PeerAddr  => $addr,
                PeerPort  => $port,
                Proto     => $proto,
                ReuseAddr => 1,
            );
        }
    }

    ### prepare unix domain socket for inter-process communication
    my $inter_w; $inter_w = tcp_server "unix/", $INTER_SOCK_NAME, sub {
        my($fh) = @_;
        infof(">>inter_sock accept_cb");
        for my $pool_id (sort keys %Connection_Pool) {
            infof("%s=%d", $pool_id, scalar(@{ $Connection_Pool{$pool_id} }));
        }

        my $cw; $cw = AE::io $fh, 0, sub {
            infof(">>AE::io cb");
            my $buf;
            my $len;

            ## read length of following command string
            $buf = '';
            $len = sysread($fh, $buf, 4);
            debugf("len:%d", $len);
            if (defined $len && $len == 0) {
                undef $cw;
                return;
            }
            my $cmdlen = unpack 'N', $buf;
            debugf("cmdlen: %d", $cmdlen);

            ## read command string
            $buf = '';
            $len = sysread($fh, $buf, $cmdlen);
            debugf("len:%d", $len);
            if (defined $len && $len == 0) {
                undef $cw;
                return;
            }
            my $cmd = $buf;
            infof("cmd: %s", $cmd);

            my($op, $pool_id) = split /\s+/, $cmd, 2;

            if ($op eq 'get') {
                if (! exists $Connection_Pool{$pool_id}) {
                    warnf("No such pool_id: %s", $pool_id);
                    return;
                }
                if (scalar(@{ $Connection_Pool{$pool_id} }) <= 0) {
                    warnf("No connection in pool_id: %s", $pool_id);
                    return;
                }

                my $conn = shift @{ $Connection_Pool{$pool_id} };
                IO::FDPass::send($fh->fileno, fileno($conn))
                        or do {
                            warnf("failed to send fd: $!");
                            push @{ $Connection_Pool{$pool_id} }, $conn;
                        };
            } elsif ($op eq 'release') {
                my $fd = IO::FDPass::recv($fh->fileno);
                if ($fd < 0) {
                    warnf("failed to get back fd: $!");
                    return;
                }

                my $conn = IO::Socket->new_from_fd($fd, 'r+');
                push @{ $Connection_Pool{$pool_id} }, $conn;
            } else {
                warnf("unknown op: %s", $op);
            }
        };
    };

    AE::cv->recv;
    exit 0;
}


__END__

=head1 NAME

B<poold.pl> - socket pooling daemon

=head1 SYNOPSIS

B<poold.pl>
[B<-d> | B<--debug>]

B<poold.pl> B<-h> | B<--help> | B<-?>

  $ ./poold.pl -d
  
  $ ./client.pl

=head1 DESCRIPTION

THIS SCRIPT IS ALPHA QUALITY JUST FOR PROOF OF CONCEPT.

poold.pl pools sockets and lease a socket (file descriptor) to client with unix domain socket.

=head1 OPTIONS

=over 4

=item B<-d>, B<--debug>

increase debug level.
-d -d more verbosely.

=back

=head1 PROS AND CONS

=head2 Pros

=over 4

=item * Faster than proxy type connection pooling mechanism

=back

=head2 Cons

=over 4

=item * Hard to use for stateful connections suck like a connection to MySQL

=item * We can exchange a file descriptor not a instance of driver class for some middleware so we need to create a instance from file descriptor.

=back

=head1 SEE ALSO

L<IO::FDPass|IO::FDPass>,
sendmsg(2)

=head1 AUTHOR

HIROSE, Masaaki E<lt>hirose31 _at_ gmail.comE<gt>

=head1 LICENSE

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

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
