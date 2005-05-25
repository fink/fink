#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

# Write a config file
my $conffile = "fink.conf";
open CONF, ">$conffile" or die "Can't open: $!";
print CONF <<__HEADER;
Basepath: basepath
Distribution: 10.2-gcc3.3
Trees: who/cares
__HEADER
close CONF;

END { unlink $conffile }


use Fink::Config;
my $config;

$config = Fink::Config->new_with_path($conffile);
isa_ok( $config, 'Fink::Config' );
ok( ! $config->has_flag('foo'), "blank flags are cleared" );

$config->set_flag('foo');
ok( $config->has_flag('foo'), "flags can be set" );

$config->set_flag('bar');
ok( $config->has_flag('bar'), "multiple flags can be set" );

$config->set_flag('foo');
ok( $config->has_flag('foo'), "setting twice is ok" );

$config->clear_flag('foo');
ok( ! $config->has_flag('foo'), "flags can be cleared" );

$config->clear_flag('foo');
ok( ! $config->has_flag('foo'), "clearing twice is ok" );

$config->clear_flag('iggy');
ok( ! $config->has_flag('iggy'), "clearing nonexistent flag is ok" );

$config->set_flag('iggy');
$config->save();
$config = Fink::Config->new_with_path($conffile);
ok( !$config->has_flag('foo') && $config->has_flag('bar')
	&& $config->has_flag('iggy'), "flags can be restored" );
