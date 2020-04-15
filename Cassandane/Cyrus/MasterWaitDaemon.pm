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

    $self->{_want}->{services} = [];

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

sub add_waitdaemon
{
    my ($self, $instance, $id, $args) = @_;

    $id //= 0;

    $instance->add_daemon(
        name => "waitdaemon$id",
        argv => [ $waitdaemon,
                  '--id' => $id,
                  '--name' => $self->{_name},
                  %{$args},
                ],
        wait => 1,
    );
}

sub get_waitdaemon_procs
{
    my ($self) = @_;

    my $ps = Proc::ProcessTable->new();

    my $pattern = qr{\bwaitdaemon\.pl\b.*?--name[=\s]$self->{_name}\b};

    my @procs = grep { $_->cmndline() =~ $pattern } @{ $ps->table() };

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
        $self->add_waitdaemon($self->{instance}, $id, { '--ready' => 'ok' });
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
        $self->add_waitdaemon($self->{instance}, $id, {
            '--ready' => 'ok',
            '--shutdownfile' => "$basedir/waitdaemon$id.shutdown",
        });
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

sub test_bad_childready
    :NoMailbox :NoStartInstances :min_version_3_3
{
    my ($self) = @_;

    # some good starts
    foreach my $id (1 .. 3) {
        $self->add_waitdaemon($self->{instance}, $id, { '--ready' => 'ok' });
    }
    # some bad bad starts
    foreach my $id (4 .. 5) {
        $self->add_waitdaemon($self->{instance}, $id, { '--ready' => 'bad' });
    }

    # XXX make sure fakesaslauthd is killed off after

    # XXX this doesn't throw an exception if the instance's
    # XXX master process fails to start -- it probably should!
    $self->{instance}->start();

    # XXX instead, start it, wait a bit, then ask it if it's running
    sleep 3;
    $self->assert_num_equals(0, $self->{instance}->is_running());

    my @syslog = $self->{instance}->getsyslog();

    # master should not have logged errors for the good ones
    foreach my $good (1 .. 3) {
        my $pattern = qr{waitdaemon$good/daemon};
        $self->assert_does_not_match($pattern, "@syslog");
    }

    # master should've logged an error when it exited
    $self->assert_matches(qr{waitdaemon waitdaemon4/daemon did not write "ok},
                          "@syslog");

    # master should not have even tried to start the second bad one
    $self->assert_does_not_match(qr{waitdaemon5/daemon}, "@syslog");

    # should not be any waitdaemon processes dangling around
    $self->assert_num_equals(0, scalar $self->get_waitdaemon_procs());
}

sub test_truncated_childready
    :NoMailbox :NoStartInstances :min_version_3_3
{
    my ($self) = @_;

    # some good starts
    foreach my $id (1 .. 3) {
        $self->add_waitdaemon($self->{instance}, $id, { '--ready' => 'ok' });
    }
    # some bad starts
    foreach my $id (4 .. 5) {
        $self->add_waitdaemon($self->{instance}, $id, { '--ready' => 'short' });
    }

    $self->add_waitdaemon($self->{instance}, undef, { '--ready' => 'short' });

    # XXX this doesn't throw an exception if the instance's
    # XXX master process fails to start -- it probably should!
    $self->{instance}->start();

    # XXX instead, start it, wait a bit, then ask it if it's running
    sleep 3;
    $self->assert_num_equals(0, $self->{instance}->is_running());

    my @syslog = $self->{instance}->getsyslog();

    # master should not have logged errors for the good ones
    foreach my $good (1 .. 3) {
        my $pattern = qr{waitdaemon$good/daemon};
        $self->assert_does_not_match($pattern, "@syslog");
    }

    # master should've logged an error when it exited
    $self->assert_matches(qr{waitdaemon waitdaemon4/daemon did not write "ok},
                          "@syslog");

    # master should not have even tried to start the second bad one
    $self->assert_does_not_match(qr{waitdaemon5/daemon}, "@syslog");

    # should not be any waitdaemon processes dangling around
    $self->assert_num_equals(0, scalar $self->get_waitdaemon_procs());
}

sub test_name_conflict
    :NoMailbox :NoStartInstances :min_version_3_3
{
    my ($self) = @_;

    $self->{instance}->add_service(name => 'collision',
                                   argv => [ 'imapd' ]);

    $self->{instance}->add_daemon(name => 'collision',
                                  argv => [ $waitdaemon,
                                            '--ready' => 'ok',
                                          ],
                                  wait => 1);

    eval { $self->{instance}->start() };
    my $e = $@;
    $self->assert_matches(qr{Master no longer running}, $e)
}

1;
