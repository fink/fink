#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use Fink::Services qw(read_properties);
use Fink::Config;

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::PkgVersion');

my %perlversions = (
             'mp3-info-pm-1.01-1'        => '',         # Type: perl
             'sed-4.0.5-1'               => '',         # no Type
             'xml-parser-pm560-2.31-5'   => '/5.6.0',   # Type: perl 5.6.0
            );


while( my($info, $version) = each %perlversions ) {
    my $pv = (Fink::PkgVersion->pkgversions_from_info_file(
                                "PkgVersion/$info.info"
                               ))[0];

    isa_ok( $pv, "Fink::PkgVersion", $info );

    my($perldir, $perlarch) = $pv->get_perl_dir_arch;
    is( $perldir,  $version, 'perl version' );
    like( $perlarch,   qr{^darwin}, 'perl arch' );
    unlike( $perlarch, qr{[='"]}, 'not picking up extra cruft from -V' );
    unlike( $perlarch, qr/\n/,    'no stray newlines in perlarch' );
}
