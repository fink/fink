#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use File::Copy;

# We're going to make changes to this config, so use a scratch copy.
my $Config_File = 'basepath/etc/fink.conf.copy';
copy('basepath/etc/fink.conf', $Config_File);
END { unlink $Config_File }


use Fink::Config;

my $config = Fink::Config->new_with_path($Config_File);
isa_ok( $config, 'Fink::Config' );


# has_param()
ok( !$config->has_param('does_not_exist'), 'has_param() false' );


# param_boolean()
ok( !$config->param_boolean('does_not_exist'), 'param_boolean() non-exist' );
ok( $config->param_boolean('selfupdatenocvs'), '  true' );
ok( !$config->param_boolean('verbose'),        '  "0"' );


# param_default()
ok( !$config->param_default("verbose", 1),   'param_default, param exists' );
is( $config->param_default("foofer", 42), 42,'               doesnt exist' );


