#!/usr/bin/perl
#
#  Copyright (c) 2017 FastMail Pty Ltd  All rights reserved.
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
#  FASTMAIL PTY LTD DISCLAIMS ALL WARRANTIES WITH REGARD TO
#  THIS SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
#  AND FITNESS, IN NO EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE
#  FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
#  AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
#  OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

package Cassandane::Cyrus::ImapTest;
use strict;
use warnings;
use Cwd qw(abs_path);
use Data::Dumper;
use DateTime;
use Devel::Symdump;
use File::Path qw(mkpath);

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;
use Cassandane::Cassini;

my $basedir;
my $binary;
my $testdir;
my %suppressed;

sub init
{
    my $cassini = Cassandane::Cassini->instance();
    $basedir = $cassini->val('imaptest', 'basedir');
    return unless defined $basedir;
    $basedir = abs_path($basedir);

    my $supp = $cassini->val('imaptest', 'suppress',
                             'listext subscribe');
    map { $suppressed{$_} = 1; } split(/\s+/, $supp);

    $binary = "$basedir/src/imaptest";
    $testdir = "$basedir/src/tests";
}
init;

sub new
{
    my $class = shift;

    my $config = Cassandane::Config->default()->clone();
    $config->set(servername => "127.0.0.1"); # urlauth needs matching servername
    $config->set(virtdomains => 'userid');
    $config->set(unixhierarchysep => 'on');
    $config->set(altnamespace => 'yes');

    return $class->SUPER::new({ config => $config }, @_);

}

sub set_up
{
    my ($self) = @_;
    $self->SUPER::set_up();

    $self->{instance}->create_user('user2');
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

sub list_tests
{
    my $class = ref($_[0]) || $_[0];
    my @tests;

    if (!defined $basedir)
    {
        return ( 'test_warning_imaptest_is_not_installed' );
    }

    # find ImapTest's scripted tests (in its 'src/test' directory)
    opendir TESTS, $testdir
        or die "Cannot open directory $testdir: $!";
    while (my $e = readdir TESTS)
    {
        next if $e =~ m/^\./;
        next if $e =~ m/\.mbox$/;
        next if $suppressed{$e};
        next if ( ! -f "$testdir/$e" );
        push(@tests, "test_$e");
    }
    closedir TESTS;

    # find our own supplementary tests (in this module)
    foreach my $f (Devel::Symdump->functions(__PACKAGE__)) {
        $f = (split '::', $f)[-1];
        next if $f !~ m/^test_/;
        push @tests, $f;
    }

    return @tests;
}

sub run_imaptest
{
    my ($self, @args) = @_;

    my $svc = $self->{instance}->get_service('imap');
    my $params = $svc->store_params();

    my $r = {};

    $r->{logdir} = "$self->{instance}->{basedir}/rawlog/";
    $r->{errfile} = $self->{instance}->{basedir} .  '/imaptest.stderr';
    $r->{outfile} = $self->{instance}->{basedir} .  '/imaptest.stdout';

    mkdir $r->{logdir};
    eval {
        $self->{instance}->run_command({
                redirects => { stderr => $r->{errfile}, stdout => $r->{outfile} },
                workingdir => $r->{logdir},
#            handlers => {
#                exited_normally => sub { $r->{code} = 0; },
#                exited_abnormally => sub { 
#                    my (undef, $code) = @_;
#                    $r->{code} = $code;
#                    die "imaptest exited with return code $code";
#                },
#                signaled => sub {
#                    my (undef, $sig) = @_;
#                    $r->{signal} = $sig;
#                    die "imaptest exited with signal $sig";
#                },
#            },
            },
            $binary,
            "host=" . $params->{host},
            "port=" . $params->{port},
            "user=" . $params->{username},
            "user2=" . "user2",
            "pass=" . $params->{password},
            "mbox=" . abs_path("data/dovecot-crlf"),
            "rawlog",
            @args);
    };
    if ($@) {
        $r->{exception} = $@;
    }

    return $r;
}

sub run_test
{
    my ($self) = @_;

    if (!defined $basedir)
    {
        xlog "ImapTests are not enabled.  To enabled them, please";
        xlog "install ImapTest from http://www.imapwiki.org/ImapTest/";
        xlog "and edit [imaptest]basedir in cassandane.ini";
        xlog "This is not a failure";
        return;
    }

    my $name = $self->name();
    if ($self->can($name)) {
        # if we have a perl test function, call that
        return $self->$name();
    }

    $name =~ s/^test_//;

    my $result = $self->run_imaptest("test=$testdir/$name");

    if (($result->{status} || get_verbose)) {
        if (-f $result->{errfile}) {
            open FH, '<', $result->{errfile}
                or die "Cannot open $result->{errfile} for reading: $!";
            while (readline FH) {
                xlog $_;
            }
            close FH;
        }
        opendir(DH, $result->{logdir})
            or die "Can't open logdir $result->{logdir}";
        while (my $item = readdir(DH)) {
            next unless $item =~ m/^rawlog\./;
            print "============> $item <=============\n";
            open(FH, '<', "$result->{logdir}/$item")
                or die "Can't open $result->{logdir}/$item";
            while (readline FH) {
                print $_;
            }
            close(FH);
        }
    }

    $self->assert_equals(0, $result->{status});
}

sub test_yadda
{
    my ($self) = @_;
    xlog "we're in our custom test!"
}

sub test_wiki_status_checkpoint
{
    my ($self) = @_;

    # run ImapTest in 'checkpoint' mode for a couple of minutes
    my $result = $self->run_imaptest(qw(
        secs=30
        checkpoint=1
    ));

    if (defined $result->{exception} || get_verbose()) {
        # report the actual errors
        if (-f $result->{errfile}) {
            open my $fh, '<', $result->{errfile}
                or die "$result->{errfile}: $!";
            xlog $_ foreach <$fh>;
            close $fh;
        }

        # XXX if very verbose, dump out the stdout (benchmark stats)?
        # XXX if very verbose, dump out the rawlogs
    }

    $self->assert(not defined $result->{exception});
    $self->assert_equals(0, -s $result->{errfile});
    $self->assert_equals(0, $result->{status});
}

1;
