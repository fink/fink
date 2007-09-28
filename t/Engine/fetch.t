#!/usr/bin/perl -w
# -*- mode: Perl; tab-width: 4; -*-

use strict;
use Test::More tests => 23;
use Fink::Config qw($basepath);
use Fink::CLI qw(capture);
require Fink::Package;
require Fink::PkgVersion;

my $config = Fink::Config->new_with_path('basepath/etc/fink.conf');

require_ok('Fink::Engine');

# "sources" is list of all possible complete outputs for the package
my %tests = (
	'p0' => {
		'restrictive' => 0,
		'sources' => [
			""
			]
	},
	'p1' => {
		'restrictive' => 0,
		'sources'     => [
			"p1-1.tar.gz md5=wickawockaA http://foo.bar/p1-1.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\n"
			]
	},
	'p2' => {
		'restrictive' => 0,
		'sources'     => [
			"p2-1-src.tar.gz md5=wickawockaB http://foo.bar/p2-1-src.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\np2-1-doc.tar.gz md5=wickawockaC http://foo.bar/p2-1-doc.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\n",
			"p2-1-doc.tar.gz md5=wickawockacC http://foo.bar/p2-1-doc.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\np2-1-src.tar.gz md5=wickawockaB http://foo.bar/p2-1-src.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\n"
			]
	},
	'p3' => {
		'restrictive' => 0,
		'sources'     => [
			"p3-1.tar.gz md5=wickawockaD http://here/this/p3-1.tar.gz ftp://there/that/p3-1.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\n",
			"p3-1.tar.gz md5=wickawockaD ftp://there/that/p3-1.tar.gz http://here/this/p3-1.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\n"
			]
	},
	'p4' => {
		'restrictive' => 1,
		'sources'     => [
			"p4-1.tar.gz md5=wickawockaE http://foo.bar/p4-1.tar.gz \"fink-core <fink-core\@lists.sourceforge.net>\"\n"
			]
	},
);

Fink::Package->forget_packages();
foreach (sort keys %tests) {
	my @pv = Fink::PkgVersion->pkgversions_from_info_file("Engine/$_.info");
	Fink::Package->insert_pkgversions(@pv);
}

# Can only test the underlying functions, not the 'fink' command
# interface because we don't have a live fink installation to use.
# Be very strict here...must remain compatible with newmirror script.

my(@cmd, @expect, $output, $out_save);

foreach (sort keys %tests) {
	@cmd = ('--dry-run', $_);
	capture sub { $Fink::Mirror::failed_mirrors = {}; Fink::Engine::cmd_fetch(@cmd) }, \$output, \$output;
	@expect = @{$tests{$_}->{sources}};
	ok(
		1 == (grep { $output eq $_ } @expect),
		"fetch @cmd\n\tgave:\n--\n${output}--\n\texpected one of:\n--\n".(join "--\n", @expect)."--\n"
		);
	@cmd = ('--dry-run', '-i', $_);
	capture sub { $Fink::Mirror::failed_mirrors = {}; Fink::Engine::cmd_fetch(@cmd) }, \$output, \$output;
	@expect = ("Ignoring $_ due to License: Restrictive\n") if $tests{$_}->{restrictive};
	ok(
		1 == (grep { $output eq $_ } @expect),
		"fetch @cmd\n\tgave:\n--\n${output}--\n\texpected one of:\n--\n".(join "--\n", @expect)."--\n"
		);
}

@cmd = ('--dry-run');
capture sub { $Fink::Mirror::failed_mirrors = {}; Fink::Engine::cmd_fetch_all(@cmd) }, \$output, \$output;
$out_save = $output;
foreach (sort keys %tests) {
	@expect = @{$tests{$_}->{sources}};
	ok(
		1 == (grep { $output =~ s/$_// } @expect),
		"fetch-all @cmd\n\tgave:\n--\n${out_save}--\n\texpected to contain one of:\n--\n".(join "--\n", @expect)."--\n"
		);
}	
ok(
	0 == length $output,
	"fetch-all @cmd\n\tremnant\n--\n${output}--\n\texpected to be\n--\n--\n"
	);

@cmd = ('--dry-run', '-i');
capture sub { $Fink::Mirror::failed_mirrors = {}; Fink::Engine::cmd_fetch_all(@cmd) }, \$output, \$output;
$out_save = $output;
foreach (sort keys %tests) {
	@expect = @{$tests{$_}->{sources}};
	@expect = ("Ignoring $_ due to License: Restrictive\n") if $tests{$_}->{restrictive};
	ok(
		1 == (grep { $output =~ s/$_// } @expect),
		"fetch-all @cmd\n\tgave:\n--\n${out_save}--\n\texpected to contain one of:\n--\n".(join "--\n", @expect)."--\n"
		);
}	
ok(
	0 == length $output,
	"fetch-all @cmd\n\tremnant\n--\n${output}--\n\texpected to be\n--\n--\n"
	);
