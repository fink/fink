#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use Fink::Services qw(read_properties);
use Fink::Config;

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::PkgVersion');

my $pv = Fink::PkgVersion->new_from_properties(
                        read_properties("PkgVersion/sed-4.0.5-1.info")
                       );

isa_ok( $pv, 'Fink::PkgVersion' );

my($perldir, $perlarch) = $pv->get_perl_dir_arch;
like( $perldir,  qr{^/ 5 \. \d{1,2} \. \d{1,2} $}x );
like( $perlarch,   qr{^darwin} );
unlike( $perlarch, qr{[='"]}, 'not picking up extra cruft from -V' );
unlike( $perlarch, qr/\n/,    'no stray newlines in perlarch' );
