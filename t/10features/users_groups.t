#!/usr/bin/perl -w

use strict;
use Test::More tests => 4;

foreach (qw/ root nobody /) {
	ok( defined getpwnam($_), "User \"$_\" exists");
}
foreach (qw/ admin nobody /) {
	ok( defined getgrnam($_), "Group \"$_\" exists");
}
