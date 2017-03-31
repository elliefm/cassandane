#!/usr/bin/perl
#
#  Copyright (c) 2017 FastMail Pty. Ltd.  All rights reserved.
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
#  3. The name "FastMail" must not be used to
#     endorse or promote products derived from this software without
#     prior written permission. For permission or any legal
#     details, please contact
#         FastMail Pty. Ltd.
#         Level 1, 91 William St
#         Melbourne 3000
#         Victoria
#         Australia
#
#  4. Redistributions of any form whatsoever must retain the following
#     acknowledgment:
#     "This product includes software developed by FastMail Pty. Ltd."
#
#  FASTMAIL PTY LTD DISCLAIMS ALL WARRANTIES WITH REGARD TO
#  THIS SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
#  AND FITNESS, IN NO EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE
#  FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
#  AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
#  OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

package Cassandane::Cyrus::SNMP;
use strict;
use warnings;
use Data::Dumper;
use Errno qw(ENOENT);
use JSON;
use Net::SNMP;

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;
use Cassandane::Instance;

$Data::Dumper::Sortkeys = 1;

my $have_snmp;

sub init
{
    my $cassini = Cassandane::Cassini->instance();
    my $agentxsocket = $cassini->val('snmp', 'agentxsocket');
    my $destdir = $cassini->val('cyrus default', 'destdir', '');
    my $prefix = $cassini->val('cyrus default', 'prefix', '');

    return if not $agentxsocket;
    if (-S $agentxsocket) {
	return if not -r $agentxsocket;
	return if not -w $agentxsocket;
    }

    my $cyr_buildinfo;
    my $base = $destdir . $prefix;
    die "cannot find base directory" if not $base;
    foreach (qw( bin sbin libexec libexec/cyrus-imapd lib cyrus/bin )) {
	my $dir = "$base/$_";
	if (opendir my $dh, $dir)
	{
	    if (grep { $_ eq 'cyr_buildinfo' } readdir $dh) {
		$cyr_buildinfo = "$dir/cyr_buildinfo";
	    }
	    closedir $dh;
	}
	else
	{
	    xlog "Couldn't opendir $dir: $!" if $! != ENOENT;
	    next;
	}
    }

    return if not $cyr_buildinfo;

    local $/;
    open my $fh, '-|', $cyr_buildinfo or die "cannot exec $cyr_buildinfo: $!";
    my $buildinfo = JSON::decode_json(<$fh>);
    close $fh;

    return if not $buildinfo->{component}->{snmp};

    $have_snmp = 1;
}
init;

sub new
{
    my $class = shift;
    return $class->SUPER::new({}, @_);
}

sub list_tests
{
    my $class = shift;

    return ('snmp_is_not_available') if not $have_snmp;

    return $class->SUPER::list_tests();
}

sub set_up
{
    my ($self) = @_;
    $self->SUPER::set_up();
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

sub snmp_is_not_available { }  # nothing to do

sub test_aaasetup
{
    my ($self) = @_;

    # make sure everything sets up, tears down, and finds the right version

    my ($session, $error) = Net::SNMP->session(
	-hostname => 'localhost',
	-port => '161',
    );
    $self->assert_equals("", $error);

    my $result = $session->get_request(
	-varbindlist => ['.1.3.6.1.4.1.3.6.1.1.2.0'],
    );
    $self->assert_equals("", $session->error());

    my $version = Cassandane::Instance->get_version($self->{instance}->{installation});
    $self->assert($version);
    $self->assert_equals($version, $result->{'.1.3.6.1.4.1.3.6.1.1.2.0'});
}

sub test_aabexperiment
{
    my ($self) = @_;

    my ($session, $error) = Net::SNMP->session(
	-hostname => 'localhost',
	-port => '161',
    );

    xlog "session: " . Dumper $session;
    xlog "error: " . Dumper $error;

    my $foo = $session->get_table(
	-baseoid => ".1.3.6.1.4.1.3.6.1",
    );

    $self->assert_equals("", $session->error());

    xlog "foo: " . Dumper $foo;

    my $bar = $session->get_request(
	-varbindlist => ['.1.3.6.1.4.1.3.6.1.1.2.0'],
    );

    $self->assert_equals("", $session->error());
    xlog "bar: " . Dumper $bar;

    my $vs = Cassandane::Instance->get_version($self->{instance}->{installation});
    xlog "vs: " . Dumper $vs;
}

1;
