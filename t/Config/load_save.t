#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use File::Copy;

# We're going to make changes to this config, so use a scratch copy.
my $Config_File = 'basepath/etc/fink.conf.copy';
copy('basepath/etc/fink.conf', $Config_File);
END { unlink $Config_File }


use Fink::Config;

my $config = Fink::Config->new_with_path($Config_File, 
                                         { Basepath => "TheDefault",
                                           Something => "A Default",
                                         });
isa_ok( $config, 'Fink::Config' );

is( $config->{Basepath}, undef, 'defaults lowercased' );
isnt( $config->param('Basepath'), 'TheDefault' );
is( $config->param('Something'), 'A Default' );


sub ck_config {
    my $config = shift;

    is( $config->get_path,      $Config_File, 'get_path' );
    is_deeply( [$config->get_treelist], 
               [qw(local/main stable/main stable/crypto local/bootstrap)],
               'get_treelist'
             );

    open CONFIG, $Config_File;
    my %Expected_Params = map { /^([^:]+):\s*(.*)$/; ($1 => $2) }
                            grep !/^#/, grep /\S/, <CONFIG>;
    close CONFIG;

    while ( my($key, $val) = each %Expected_Params ) {
        ok( $config->has_param($key),   "has_param($key)" );
        is( $config->param($key), $val, "param($key)" );
        is( $config->param(uc $key), $val, "param(uc $key)" );
        is( $config->param(lc $key), $val, "param(lc $key)" );
    }
}


ck_config($config);

# set_param()
$config->set_param('wiffle', 42);
is( $config->param('wiffle'), 42 );

$config->set_param('wiffle', '');
ok( !$config->has_param('wiffle') );

$config->set_param('wiffle', 0);
is( $config->param('wiffle'), 0 );
ok( $config->has_param('wiffle') );


$config->save;
cmp_ok( -M $Config_File, '<=', 0, 'save() touched config file' );

$config = Fink::Config->new_with_path($Config_File);
ck_config($config);
ok( $config->has_param('wiffle') );
is( $config->param('wiffle'), 0 );
