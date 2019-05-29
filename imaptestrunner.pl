#!/usr/bin/perl

use warnings;
use strict;

use Cwd qw(abs_path);
use Data::Dumper;
use File::Path qw(mkpath);

use lib '.';
use base qw(Cassandane::Cyrus::TestCase);
use Cassandane::Cassini;
use Cassandane::Util::Log;
use Cassandane::Util::Setup;

set_verbose(1);
become_cyrus();

my $cassini = Cassandane::Cassini->instance();
my $basedir = $cassini->val('imaptest', 'basedir');
die "need imaptest.basedir configuration" if not defined $basedir;
$basedir = abs_path($basedir);

my $binary = "$basedir/src/imaptest";
my $testdir = "$basedir/src/tests";

my $config = Cassandane::Config->default()->clone();
$config->set(servername => "127.0.0.1"); # urlauth needs matching servername
$config->set(virtdomains => 'userid');
$config->set(unixhierarchysep => 'on');
$config->set(altnamespace => 'yes');

my $instance = Cassandane::Instance->new(
    config => $config,
    description => 'cyrus instance for ImapTest',
);
$instance->add_service(name => 'imap');

$instance->start();
$instance->create_user('user2');

my $logdir = $instance->get_basedir() . '/rawlog/';
my $outfile = $instance->get_basedir() . '/stdout';
my $errfile = $instance->get_basedir() . '/stderr';
mkdir($logdir);

my $svc = $instance->get_service('imap');
my $params = $svc->store_params();

my $status = undef;
$instance->run_command({
        redirects => { stdout => $outfile, stderr => $errfile },
        workingdir => $logdir,
        handlers => {
            exited_normally => sub { $status = 1; },
            exited_abnormally => sub { $status = 0; },
        },
    },
    $binary,
    "host=" . $params->{host},
    "port=" . $params->{port},
    "user=" . $params->{username},
    "user2=" . "user2",
    "pass=" . $params->{password},
    "mbox=" . abs_path("data/dovecot-crlf"),
#    "secs=30",
    "checkpoint=1",
    "own_msgs",
    "own_flags",
    "rawlog",
    "test=$testdir",
);

$instance->stop();
$instance->cleanup();

open my $fh, '<', $errfile or die "$errfile: $!";
print <$fh>;
close $fh;

open $fh, '<', $outfile or die "$outfile: $!";
print <$fh>;
close $fh;
