#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
BEGIN {
    sub p($) {
        local $Data::Dumper::Indent    = 1;
        local $Data::Dumper::Deepcopy  = 1;
        local $Data::Dumper::Sortkeys  = 1;
        local $Data::Dumper::Terse     = 1;
        local $Data::Dumper::Useqq     = 1;
        local $Data::Dumper::Quotekeys = 0;
        my $d =  Dumper($_[0]);
        $d    =~ s/\\x{([0-9a-z]+)}/chr(hex($1))/ge;
        print STDERR $d;
    }
}

use Log::Minimal;
use Carp;

use AnyEvent;
use AnyEvent::FDpasser;
use IO::Socket::UNIX;

my $s2c_path  = "/tmp/pool.s2c";
my $c2s_path  = "/tmp/pool.c2s";

my $s2c_fh = AnyEvent::FDpasser::fdpasser_server($s2c_path);
my $c2s_fh = AnyEvent::FDpasser::fdpasser_server($c2s_path);

infof("[$$] Server start");

my @fh;
my $n = 3;
while ($n-- > 0) {
    open my $fh, '>', "/tmp/fdp.$n" or die $!;
    push @fh, $fh;
}

my $w_s2c; $w_s2c = AE::io $s2c_fh, 0, sub {
    my $passer_fh = AnyEvent::FDpasser::fdpasser_accept($s2c_fh)
        or die "couldn't accept: $!";
    my $passer = AnyEvent::FDpasser->new( fh => $passer_fh, );

    infof("[$$] #fh in pool: %d", scalar(@fh));
    my $fh = shift @fh or die "no fh"; # fixme
    $passer->push_send_fh(
        $fh,
        sub {
            infof("push_send_fh cb");
        });
};

my $w_c2s; $w_c2s = AE::io $c2s_fh, 0, sub {
    my $passer_fh = AnyEvent::FDpasser::fdpasser_accept($c2s_fh)
        or die "couldn't accept: $!";
    my $passer = AnyEvent::FDpasser->new( fh => $passer_fh, );

    $passer->push_recv_fh(
        sub {
            my($fh) = @_;
            infof("push_recv_fh cb");
            push @fh, $fh;
        });
};

AE->cv->recv;

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
