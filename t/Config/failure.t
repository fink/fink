#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

require_ok 'Fink::Config';

eval { Fink::Config->new(); };
is( $@, "Basepath not set, no config file!\n" );

open BADCONFIG, ">bad.config";
print BADCONFIG "Foo: Bar\n";
close BADCONFIG;
END { unlink "bad.config" }

eval { Fink::Config->new_with_path('bad.config') };
is( $@, qq{Basepath not set in config file "bad.config"!\n} );
