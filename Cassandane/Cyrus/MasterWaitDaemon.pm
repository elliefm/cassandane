#!/usr/bin/perl
#
#  Copyright (c) 2011-2020 FastMail Pty Ltd. All rights reserved.
#
#  Redistribution and use in source and binary forms, with or without
#  modification, are permitted provided that the following conditions
#  are met:
#
#  1. Redistributions of source code must retain the above copyright
#     notice, this list of conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright
#     notice, this list of conditions and the following disclaimer in
#     the documentation and/or other materials provided with the
#     distribution.
#
#  3. The name "Fastmail Pty Ltd" must not be used to
#     endorse or promote products derived from this software without
#     prior written permission. For permission or any legal
#     details, please contact
#      FastMail Pty Ltd
#      PO Box 234
#      Collins St West 8007
#      Victoria
#      Australia
#
#  4. Redistributions of any form whatsoever must retain the following
#     acknowledgment:
#     "This product includes software developed by Fastmail Pty. Ltd."
#
#  FASTMAIL PTY LTD DISCLAIMS ALL WARRANTIES WITH REGARD TO THIS SOFTWARE,
#  INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY  AND FITNESS, IN NO
#  EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE FOR ANY SPECIAL, INDIRECT
#  OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS OF
#  USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
#  TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE
#  OF THIS SOFTWARE.
#

package Cassandane::Cyrus::MasterWaitDaemon;
use strict;
use warnings;
use POSIX qw(getcwd);
use Data::Dumper;
use DateTime;
use Proc::ProcessTable;

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;
use Cassandane::Daemon;

my $waitdaemon = getcwd() . '/utils/waitdaemon.pl';

sub new
{
    my $class = shift;
    my $self = $class->SUPER::new({}, @_);

    return $self;
}

sub set_up
{
    my ($self) = @_;
    die "couldn't find '$waitdaemon'" if not -f $waitdaemon;
    $self->SUPER::set_up();
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

sub get_waitdaemon_procs
{
    my ($self) = @_;

    my $ps = Proc::ProcessTable->new();
    my @procs = grep { $_->cmndline() =~ m/waitdaemon/ } @{ $ps->table() };
    return @procs;
}

sub test_aaasetup
    :NoMailbox :NoStartInstances :min_version_3_3
{
    my ($self) = @_;

    $self->{instance}->start();
}

sub test_startup_order
    :NoMailbox :NoStartInstances :min_version_3_3
{
    my ($self) = @_;

    foreach my $id (1 .. 5) {
        $self->{instance}->add_daemon(
            name => "waitdaemon$id",
            argv => [ $waitdaemon,
                      '--id' => $id,
                      '--ready' => 'ok',
                    ],
            wait => 1,
        );
    }
    $self->{instance}->start();

    my %pids;
    foreach my $wd ($self->get_waitdaemon_procs()) {
        if ($wd->cmndline() =~ m/--id (\d+)\b/) {
            $pids{$1} = 0 + $wd->pid;
        }
        else {
            xlog "WEIRD (not a waitdaemon?): " . $wd->cmndline();
        }
    }

    foreach my $id (2 .. 5) {
        # XXX take into account pid wrapping based on /proc/sys/kernel/pid_max
        $self->assert_num_gt($pids{$id - 1}, $pids{$id});
    }
}

sub test_shutdown_order
    :NoMailbox :NoStartInstances :min_version_3_3
{
    my ($self) = @_;

    my $basedir = $self->{instance}->get_basedir();

    foreach my $id (1 .. 5) {
        $self->{instance}->add_daemon(
            name => "waitdaemon$id",
            argv => [ $waitdaemon,
                      '--id' => $id,
                      '--ready' => 'ok',
                      '--shutdownfile' => "$basedir/waitdaemon$id.shutdown",
                    ],
            wait => 1,
        );
    }

    $self->{instance}->start();

    $self->{instance}->stop();

    my %mtimes;
    foreach my $id (1 .. 5) {
        my @stat = stat("$basedir/waitdaemon$id.shutdown");
        $mtimes{$id} = $stat[9];
    }
    foreach my $id (2 .. 5) {
        $self->assert_num_lt($mtimes{$id - 1}, $mtimes{$id});
    }
}

1;
