#!/usr/bin/perl -w

use Test::More 'no_plan';

use Fink::Config qw(get_option set_options);

# get/set_option(s) seem largely unused and out of place
is( get_option('dont_exist', 23), 23 );
set_options( { foofer => "yes", yarblockos => "and then some" } );
is( get_option('foofer',     'no'), 'yes' );
is( get_option('yarblockos'),       'and then some' );

