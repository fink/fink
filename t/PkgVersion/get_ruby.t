#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use Fink::Services qw(read_properties);
use Fink::Config;

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::PkgVersion');

my %rubyversions = (
             'sed-4.0.5-1'              => '',         # no Type
             'opengl-rb18'   		=> '/1.8',     # Type: ruby 1.8
            );


while( my($info, $version) = each %rubyversions ) {
    my $pv = (Fink::PkgVersion->pkgversions_from_info_file(
                                "PkgVersion/$info.info"
                               ))[0];

    isa_ok( $pv, "Fink::PkgVersion", $info );

    my($rubydir, $rubyarch) = $pv->get_ruby_dir_arch;
    is( $rubydir,  $version, 'ruby version' );
    like( $rubyarch,   qr{^powerpc-darwin}, 'ruby arch' );
    unlike( $rubyarch, qr{[='"]}, 'not picking up extra cruft from -V' );
    unlike( $rubyarch, qr/\n/,    'no stray newlines in rubyarch' );
}
