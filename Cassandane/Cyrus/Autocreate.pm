#!/usr/bin/perl
#
#  Copyright (c) 2015 Opera Software Australia Pty. Ltd.  All rights
#  reserved.
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
#  3. The name "Opera Software Australia" must not be used to
#     endorse or promote products derived from this software without
#     prior written permission. For permission or any legal
#     details, please contact
# 	Opera Software Australia Pty. Ltd.
# 	Level 50, 120 Collins St
# 	Melbourne 3000
# 	Victoria
# 	Australia
#
#  4. Redistributions of any form whatsoever must retain the following
#     acknowledgment:
#     "This product includes software developed by Opera Software
#     Australia Pty. Ltd."
#
#  OPERA SOFTWARE AUSTRALIA DISCLAIMS ALL WARRANTIES WITH REGARD TO
#  THIS SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
#  AND FITNESS, IN NO EVENT SHALL OPERA SOFTWARE AUSTRALIA BE LIABLE
#  FOR ANY SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
#  WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN
#  AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
#  OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
#

package Cassandane::Cyrus::Autocreate;
use strict;
use warnings;

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Util::Log;

sub new
{
    my $class = shift;
    my $config = Cassandane::Config->default()->clone();
    $config->set(
        autocreate_post => 'yes',
        autocreate_quota => '500000',
        autocreate_inbox_folders => 'Drafts|Sent|Trash|SPAM',
        autocreate_subscribe_folder => 'Drafts|Sent|Trash|SPAM',
        'xlist-drafts' => 'Drafts',
        'xlist-junk' => 'SPAM',
        'xlist-sent' => 'Sent',
        'xlist-trash' => 'Trash',
    );
    return $class->SUPER::new({
	config => $config,
	adminstore => 1,
	deliver => 1,
    }, @_);
}

sub set_up
{
    my ($self) = @_;
    $self->SUPER::set_up();
    if (not $self->{instance}->{buildinfo}->{component}->{autocreate}) {
        xlog "autocreate not enabled. Skipping tests.";
        return;
    }
    $self->{test_autocreate} = 1;
}

sub tear_down
{
    my ($self) = @_;
    $self->SUPER::tear_down();
}

sub test_autocreate_specialuse
     :min_version_3_0
{
    my ($self) = @_;
    return unless $self->{test_autocreate};

    my $svc = $self->{instance}->get_service('imap');
    my $store = $svc->create_store(username => 'foo');
    my $talk = $store->get_client();
    my $list = $talk->list('', '*', 'return', ['special-use']);

    my %map = (
        drafts => 'Drafts',
        junk => 'SPAM',
        sent => 'Sent',
        trash => 'Trash',
    );
    foreach my $item (@$list) {
        my $key;
        foreach my $flag (@{$item->[0]}) {
            next unless $flag =~ m/\\(.*)/;
            $key = $1;
            last if $map{$key};
        }
        my $name = delete $map{$key};
        next unless $name;
        $self->assert_str_equals("INBOX.$name", $item->[2]);
    }
    $self->assert_num_equals(0, scalar keys %map);
}

sub test_autocreate_delivery_murder
    :Murder
{
    my ($self) = @_;
    return unless $self->{test_autocreate};

    my %msgs;
    $msgs{1} = $self->{gen}->generate(subject => "Message for newuser");
    $msgs{1}->set_attribute(uid => 1);
    $self->{frontend}->deliver($msgs{1}, user => 'autocreated_user');

#    $self->check_messages(\%msgs, check_guid => 0, keyed_on => 'uid');
}

1;
