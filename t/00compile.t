#!/usr/bin/perl -w

use strict;

BEGIN {
    eval qq{ require Test::More };
    $@ && print STDERR "\n\n$@\nDo you need to install the test-simple-pm package or perl >= v5.8.0?\n\n";
}

use Test::More 'no_plan';

use File::Find;

my @modules = ();
find(sub { push @modules, $File::Find::name if /\.pm$/ }, '../perlmod');

my @original_symbols = keys %Foo::;
foreach my $file (sort { $a cmp $b } @modules) {
    my $warnings = '';
    local $SIG{__WARN__} = sub { $warnings .= join '', @_ };

    (my $module = $file) =~ s{.*perlmod/}{};
    $module =~ s{/}{::}g;
    $module =~ s/\.pm//;
    eval qq{ package Foo; require $module };
    is( $@, '', "require $module" );
    is_deeply( [sort @original_symbols], [sort keys %Foo::], 
               '  namespace not polluted' );

    is( $warnings, '', '  no warnings' );
}

