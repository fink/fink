#!/usr/bin/perl -w

use strict;
use Test::More 'no_plan';
use Fink::Command qw(cat touch mkdir_p);
use File::Basename;

use Fink::Config;
Fink::Config->new_with_path('basepath/etc/fink.conf');

BEGIN { use_ok 'Fink::FinkVersion', ':ALL'; }

{
    my $fink_version = cat '../VERSION';
    chomp $fink_version;
    is( fink_version, , $fink_version, 'fink_version matches VERSION' );
}


{
    is( distribution_version, 'unknown', 
                                'distribution_version with no files' );

    for my $distfile (qw(fink/VERSION etc/fink-release)) {
        _write("basepath/$distfile");
        is( distribution_version, '1.2.3',   "  from $distfile" );
        unlink("basepath/$distfile");
    }
}


{
    is( pkginfo_version, distribution_version, 
                   'pkginfo_version == distribution_version with no clues' );

    for my $stamp (qw(stamp-rsync stamp-cvs)) {
        my($version) = $stamp =~ /stamp-(.*)/;
        touch("basepath/fink/$stamp");
        is( pkginfo_version, $version,      "  from $stamp" );
        unlink("basepath/fink/$stamp");
    }

    my @Stamp_Versions = qw(1.2 3.4 3.49);
    touch("basepath/fink/stamp-rel-$_") foreach @Stamp_Versions;
    is( pkginfo_version, 3.49,      '  highest from multiple stamp-rels' );
    unlink("basepath/fink/stamp-rel-$_") foreach @Stamp_Versions;
}

sub _write {
    my($file) = @_;
    mkdir_p(dirname($file));
    open(FILE, ">$file") or die "Can't open $file: $!";
    print FILE "1.2.3\n";
    close FILE;
}
