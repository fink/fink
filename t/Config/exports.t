#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';

use Fink::Config;
my $config_obj = Fink::Config->new_with_path('basepath/etc/fink.conf');


{
    package Check::Export;
    Fink::Config->import;
    ::is_deeply( \%Check::Export::, {}, 'exports nothing by default' );
}

# Test exported globals
{
    package Check::ExportOK;
    our @optional_exports;
    BEGIN {
        @optional_exports = qw($config $basepath $libpath
                               $distribution $buildpath
                               get_option set_options
                              );
    }
    use Fink::Config @optional_exports;
    ::can_ok( __PACKAGE__, grep !/^\$/, @optional_exports );
    ::is_deeply( $config, $config_obj );
    ::is( $basepath, $config->param('basepath') );

    # need a libpath() method
    ::is( $libpath,  $basepath."/lib/fink" );

    # need a buildpath() method
    ::is( $buildpath, $config->param_default("Buildpath", "$basepath/src/fink.build") );
          
    ::is( $distribution, $config->param('Distribution') );
}
