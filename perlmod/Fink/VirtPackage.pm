# -*- mode: Perl; tab-width: 4; -*-'
#
# Fink::VirtPackage class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2011 The Fink Package Manager Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

=head1 NAME

Fink::VirtPackage - Provide "virtual" packages for Fink and related tools

=head1 SYNOPSIS

Fink::VirtPackage is generally not used directly, but is instead used by
the fink-virtual-pkgs tool.

=head1 DESCRIPTION

Fink::VirtPackage is used to inject "fake" package data into the fink
database, as well as to generate a list of dpkg- and apt-get-compatible
packages to satisfy dependencies outside of Fink.

=cut

package Fink::VirtPackage;

our $VERSION = 1.00;

# Programmers' note: Please be *very* careful if you alter this file.
# It is used by dpkg via popen(), so (among other things) that means
# you must not print to STDOUT.

use Fink::Config qw($config $basepath $distribution);
use POSIX qw(uname tmpnam);
use Fink::Status;
use File::Basename;
use Fink::FinkVersion;

use constant STATUS_PRESENT => "install ok installed";
use constant STATUS_ABSENT  => "purge ok not-installed";

use vars qw(
	%options
);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw();	# eg: qw($Var1 %Hashit &func3);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

my $pkgconfig_virtual_prefix = 'system-pkgconfig-';
my @xservers                 = ('XDarwin', 'Xquartz', 'XDarwinQuartz');
my $the_instance             = undef;

END { }				# module clean-up code here (global destructor)


### constructor

sub new {
	my $proto   = shift;
	my $class   = ref($proto) || $proto;

	my $self = {};
	bless($self, $class);

	$self->initialize();

	$the_instance = $self;
	return $self;
}

=head1 TESTS

=over

=cut

### self-initialization

sub initialize {
	my $self    = shift;

	my ($hash);
	my ($cctools_version, $cctools_single_module, $growl_version);

=item "kernel"

This test checks for the kernel name and version by running the system
uname(1) call.  This should *always* exist.

=cut

	# create dummy object for kernel version
	$hash = {};
	$hash->{package} = lc((uname())[0]);
	$hash->{provides} = "kernel";
	$hash->{status} = STATUS_PRESENT;
	$hash->{version} = Fink::Services::get_kernel_vers_long() . "-1";
	$hash->{description} = "[virtual package representing the kernel]";
	$hash->{descdetail} = <<END;
This package represents the kernel (XNU (Darwin) on Mac OS X),
which is a core part of the operating system.
END
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{compilescript} = &gen_compile_script($hash);
	$self->{$hash->{package}} = $hash;
	
=item "macosx"

This test checks for the Mac OS X version by running the sw_vers(1)
command and parsing the output.  It should exist on all Mac OS X
installations (but not pure Darwin systems).

=cut

	# create dummy object for system version, if this is OS X at all
	print STDERR "- checking OSX version... " if ($options{debug});

	$hash = {};
	$hash->{package} = "macosx";
	$hash->{description} = "[virtual package representing the system]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	if (Fink::Services::get_osx_vers_long() ne 0) {
		$hash->{status} = STATUS_PRESENT;
		$hash->{version} = Fink::Services::get_osx_vers_long()."-1";
		print STDERR $hash->{version}, "\n" if ($options{debug});
	} else {
		$hash->{status} = STATUS_ABSENT;
		$hash->{version} = '0-0';
		print STDERR "unknown\n" if ($options{debug});
	}
	$hash->{descdetail} = <<END;
This package represents the Mac OS X software release.
It will not show as installed on pure Darwin systems.
END
	$hash->{compilescript} = &gen_compile_script($hash);
	$self->{$hash->{package}} = $hash;

=item "64bit-cpu"

The package is present when the CPU is 64bit-capable.

=cut

print STDERR "- checking for 64bit-cpu... " if ($options{debug});

# different sysctl variables for intel and ppc
	my @keys64 = ('hw.optional.x86_64', 'hw.optional.64bitops', 'hw.cpu64bit_capable');

	$hash = {};
	$hash->{package} = "64bit-cpu";

	my $is64bit = 0;
	if (open(SYSCTL, "sysctl " . join(' ', @keys64) . " 2>/dev/null |")) {
		my ($key, $value);
		while (<SYSCTL>) {
			($key, $value) = $_ =~ /^(\S+)\s*\:\s*(.*?)\s*$/;
			next unless (defined $key and defined $value);
			if (grep(/^$key$/, @keys64) and $value eq "1") {
				$is64bit = 1;
				last;
			}
		}
		close(SYSCTL);
	}
	if ($is64bit) {
		print STDERR "64 bit capable\n" if ($options{debug});
		$hash->{status} = STATUS_PRESENT;
	} else {
		print STDERR "not 64 bit capable\n" if ($options{debug});
		$hash->{status} = STATUS_ABSENT;
	}
	$hash->{description} = "[virtual package representing the 64bit capability of the CPU]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
The presence of the 64bit-cpu package indicates that the CPU on which we 
are running is 64bit capable.
END
	$hash->{compilescript} = &gen_compile_script($hash);
	$hash->{version} = '0-1';
	$self->{$hash->{package}} = $hash;

=item "cups-dev"

This package represents and existing installation of the CUPS
headers in /usr/include/cups.

It is called "cups-dev" instead of "system-cups-dev" for the
purposes of versioned cups-dev dependencies.

=cut

	print STDERR "- checking for cups headers... " if ($options{debug});

	$hash = {};
	$hash->{package} = "cups-dev";
	$hash->{version} = '0-0';
	$hash->{status} = STATUS_ABSENT;
	$hash->{description} = "[virtual package representing CUPS headers]";
	$hash->{provides} = "system-cups-dev";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
This package represents the version of CUPS headers installed
in /usr/include/cups.
END
	$hash->{compilescript} = &gen_compile_script($hash);

	if (open(FILEIN, '/usr/include/cups/cups.h')) {
		while (<FILEIN>) {
			if (/\#\s*define\s+CUPS_VERSION\s+(.*?)\s*$/) {
				$hash->{version} = $1 . '-1';
				last;
			}
		}
		close(FILEIN);
		$hash->{status} = STATUS_PRESENT;
		print STDERR $hash->{version}, "\n" if ($options{debug});
	} else {
		print STDERR "no\n" if ($options{debug});
	}
	$self->{$hash->{package}} = $hash;

=item "system-perl"

This package represents the version of the perl in /usr/bin.  It
is determined by parsing the $^V variable in a perl script.  It
also provides the perlI<XXX>-core package that corresponds with it's
version.

=cut

	# create dummy object for system perl
	print STDERR "- checking system perl version... " if ($options{debug});

	$hash = {};
	$hash->{package} = "system-perl";
	$hash->{description} = "[virtual package representing perl]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
This package represents the version of perl installed on the
system in /usr/bin/perl.
END
	$hash->{compilescript} = &gen_compile_script($hash);

	if ((defined Fink::Services::get_system_perl_version()) and (!(Fink::FinkVersion::get_arch() eq "x86_64") or !($distribution eq "10.5"))) {
		$hash->{version} = Fink::Services::get_system_perl_version()."-1";
		$hash->{status} = STATUS_PRESENT;
		print STDERR Fink::Services::get_system_perl_version(), "\n" if ($options{debug});
		my $perlver = my $shortver = Fink::Services::get_system_perl_version();
		$perlver = sprintf "%d.%03d%03d", split( /\./, $perlver );
		$shortver =~ s/\.//g;
		my $perlprovides = 'perl' . $shortver . '-core, system-perl' . $shortver;
		my @modules;
		if ($perlver >= 5.008001) {
			push(@modules,
				'attribute-handlers',
				'cgi',
				'data-dumper',
				'db',
				'devel-dprof',
				'devel-peek',
				'digest',
				'digest-md5',
				'extutils-makemaker',
				'file-find',
				'file-path',
				'file-spec',
				'file-temp',
				'filter-simple',
				'getopt-long',
				'i18n-langtags',
				'libnet',
				'list-util',
				'locale-maketext',
				'math-bigint',
				'memoize',
				'mime-base64',
				'podparser',
				'pod-parser',
				'switch',
				'sys-syslog',
				'term-readline',
				'test-harness',
				'test-simple',
				'text-tabs',
				'text-wrap',
				'time-hires',
				'unicode-normalize',
			);
		}
		if ($perlver >= 5.008006) {
			push(@modules,
				'apache',
				'compress-zlib',
				'convert-tnef',
				'html-parser',
				'perlobjcbridge',
				'scalar-list-utils',
				'uri',
			);
		}
		if ($perlver >= 5.008008) {
			push(@modules,
				'algorithm-diff',
				'carp',
				'class-autouse',
				'class-isa',
				'corefoundation',
				'data-hierarchy',
				'date-parse',
				'freezethaw',
				'io-pager',
				'ipc-run3',
				'locale-maketext-lexicon',
				'perlio-eol',
				'pod-simple',
				'svn',
				'svk',
				'timedate',
				'vcp',
				'yaml',
			);
		}
		if ($perlver >= 5.010000) {
			push(@modules,
				 'archive-tar',
				 'cpanplus',
				 'cpanplus-dist-build',
				 'compress-raw-zlib',
				 'digest-sha',
				 'extutils-cbuilder',
				 'extutils-parsexs',
				 'io-zlib',
				 'locale-maketext-simple',
				 'module-build',
				 'module-corelist',
				 'module-load',
				 'module-load-conditional',
				 'module-pluggable',
				 'package-constants',
				 'params-check',
				 'pod-escapes',
				);
		}
		$perlprovides .= ', ' . join(', ', map { $_ . '-pm' . $shortver } sort @modules);
		$hash->{provides} = $perlprovides;
	} else {
		$hash->{version} = '0-0';
		$hash->{status} = STATUS_ABSENT;
		print STDERR "unknown\n" if ($options{debug});
	}
	$self->{$hash->{package}} = $hash;

=item "system-javaI<XX>"

This package represents an installed version of Apple's Java.
It is considered present if the
/System/Library/Frameworks/JavaVM.framework/Versions/[VERSION]/Commands
directory exists.

=cut

	# create dummy object for java
	print STDERR "- checking Java versions:\n" if ($options{debug});
	my $javadir = '/System/Library/Frameworks/JavaVM.framework/Versions';
	my ($latest_java, $latest_javadev);
	if (opendir(DIR, $javadir)) {
		chomp(my @dirs = grep(!/^\.\.?$/, readdir(DIR)));
		for my $dir (reverse(sort(@dirs, '1.3', '1.4', '1.5'))) {
			my $ver = $dir;
			# chop the version down to major/minor without dots
			$ver =~ s/[^\d]+//g;
			$ver =~ s/^(..).*$/$1/;
			next if ($ver eq "");
			print STDERR "  - $dir... " if ($options{debug});

			$hash = {};
			$hash->{package}     = "system-java${ver}";
			$hash->{version}     = $dir . "-1";
			$hash->{description} = "[virtual package representing Java $dir]";
			$hash->{homepage}    = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
			$hash->{provides}    = 'system-java';
			if ($ver >= 14) {
				$hash->{provides} .= ', jdbc, jdbc2, jdbc3, jdbc-optional';
			}
			$hash->{descdetail}  = <<END;
This package represents the currently installed version
of Java $dir.
END
			$hash->{compilescript} = &gen_compile_script($hash);

			if ($dir =~ /^\d[\d\.]*$/ and -d $javadir . '/' . $dir . '/Commands') {
				print STDERR "$dir/Commands " if ($options{debug});
				$hash->{status}      = STATUS_PRESENT;
				$self->{$hash->{package}} = $hash unless (exists $self->{$hash->{package}});
				$latest_java = $dir unless (defined $latest_java);

=item "system-javaI<XX>-dev"

This package represents an installed version of Apple's Java SDK.
It is considered present if the
/System/Library/Frameworks/JavaVM.framework/Versions/[VERSION]/Headers
directory exists.

=cut

				$hash = {};
				$hash->{package}     = "system-java${ver}-dev";
				$hash->{status}      = STATUS_PRESENT;
				$hash->{version}     = $dir . "-1";
				$hash->{description} = "[virtual package representing Java $dir development headers]";
				$hash->{homepage}    = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
				$hash->{descdetail}  = <<END;
This package represents the development headers for
Java $dir.  If this package shows as not being installed,
you must download the Java SDK from Apple at:

  http://connect.apple.com/

(free registration required)
END
				$hash->{compilescript} = &gen_compile_script($hash);

				if (-r $javadir . '/' . $dir . '/Headers/jni.h') {
					print STDERR "$dir/Headers/jni.h " if ($options{debug});
					$latest_javadev = $dir unless (defined $latest_javadev);
				} elsif ($distribution ge "10.5" && $ver >= 14 && -r $javadir . '/Current/Headers/jni.h') {
					print STDERR "Current/Headers/jni.h " if ($options{debug});
					$latest_javadev = $dir unless (defined $latest_javadev);
				} else {
					print STDERR "$javadir/$dir/Headers/jni.h missing " if ($options{debug});
					$hash->{status} = STATUS_ABSENT;
				}
				$self->{$hash->{package}} = $hash unless (exists $self->{$hash->{package}});
				print STDERR "\n" if ($options{debug});
			} else {
				$hash->{status} = STATUS_ABSENT;
				$self->{$hash->{package}} = $hash unless (exists $self->{$hash->{package}});
				print STDERR "nothing\n" if ($options{debug});
			}
		}
		closedir(DIR);
	}

=item "system-java"

This is a convenience package that represents the latest Java version
that is considered installed, based on the previous tests.

=cut

	if (defined $latest_java) {
		$hash = {};
		$hash->{package}     = "system-java";
		$hash->{status}      = "install ok installed";
		$hash->{version}     = $latest_java . "-1";
		$hash->{description} = "[virtual package representing Java $latest_java]";
		$self->{$hash->{package}} = $hash;
	}

=item "system-java-dev"

This is a convenience package that represents the latest Java SDK
version that is considered installed, based on the previous tests.

=cut

	if (defined $latest_javadev) {
		$hash = {};
		$hash->{package}     = "system-java-dev";
		$hash->{status}      = "install ok installed";
		$hash->{version}     = $latest_javadev . "-1";
		$hash->{description} = "[virtual package representing Java SDK $latest_java]";
		$self->{$hash->{package}} = $hash;
	}

=item "system-java3d"

This package represents the Java3D APIs available as a separate download
from Apple.  It is considered present if the j3dcore.jar file exists in
the system Java extensions directory.

=cut

	# create dummy object for Java3D
	$hash = {};
	$hash->{package}     = "system-java3d";
	$hash->{status}      = STATUS_PRESENT;
	$hash->{version}     = "0-1";
	$hash->{description} = "[virtual package representing Java3D]";
	$hash->{homepage}    = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail}  = <<END;
This package represents the Java3D API.  If it does not show
as installed, you can download it from Apple at:

  http://www.apple.com/downloads/macosx/apple/java3dandjavaadvancedimagingupdate.html
END
	$hash->{compilescript} = &gen_compile_script($hash);

	print STDERR "- searching for java3d... " if ($options{debug});
	if (-f '/System/Library/Java/Extensions/j3dcore.jar') {
		print STDERR "found /System/Library/Java/Extensions/j3dcore.jar\n" if ($options{debug});
		if (open(FILEIN, '/Library/Receipts/Java3D.pkg/Contents/Info.plist')) {
			local $/ = undef;
			if (<FILEIN> =~ /<key>CFBundleShortVersionString<\/key>[\r\n\s]*<string>([\d\.]+)<\/string>/) {
				$hash->{version} = $1 . '-1';
			}
			close(FILEIN);
		}
	} else {
		$hash->{status} = STATUS_ABSENT;
		$hash->{version} = '0-0';
		print STDERR "missing /System/Library/Java/Extensions/j3dcore.jar\n" if ($options{debug});
	}
	$self->{$hash->{package}} = $hash;

=item "system-javaai"

This package represents the JavaAdvancedImaging APIs available as a
separate download from Apple.  It is considered present if the jai_core.jar
file exists in the system Java extensions directory.

=cut

	# create dummy object for JavaAdvancedImaging
	$hash = {};
	$hash->{package}     = "system-javaai";
	$hash->{status}      = STATUS_PRESENT;
	$hash->{version}     = "0-1";
	$hash->{description} = "[virtual package representing Java Advanced Imaging]";
	$hash->{homepage}    = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail}  = <<END;
This package represents the Java Advanced Imaging API.  If it
does not show as installed, you can download it from Apple at:

  http://www.apple.com/downloads/macosx/apple/java3dandjavaadvancedimagingupdate.html
END
	$hash->{compilescript} = &gen_compile_script($hash);

	print STDERR "- searching for javaai... " if ($options{debug});
	if (-f '/System/Library/Java/Extensions/jai_core.jar') {
		print STDERR "found /System/Library/Java/Extensions/jai_core.jar\n" if ($options{debug});
		if (open(FILEIN, '/Library/Receipts/JavaAdvancedImaging.pkg/Contents/Info.plist')) {
			local $/ = undef;
			if (<FILEIN> =~ /<key>CFBundleShortVersionString<\/key>[\r\n\s]*<string>([\d\.]+)<\/string>/) {
				$hash->{version} = $1 . '-1';
			}
			close(FILEIN);
		}
	} else {
		$hash->{status} = STATUS_ABSENT;
		$hash->{version} = '0-0';
		print STDERR "missing /System/Library/Java/Extensions/jai_core.jar\n" if ($options{debug});
	}
	$self->{$hash->{package}} = $hash;

=item "system-sdk-*"

These packages represent the SDKs available in /Developer/SDKs, available
as part of the XCode tools.

=cut

	my @SDKDIRS = qw(
		MacOSX10.0.0.sdk
		MacOSX10.1.0.sdk
		MacOSX10.2.0.sdk
		MacOSX10.3.0.sdk
		MacOSX10.3.9.sdk
		MacOSX10.4.0.sdk
		MacOSX10.4u.sdk
	);

	if (opendir(DIR, '/Developer/SDKs')) {
		push(@SDKDIRS, grep(/MacOSX.*.sdk/, readdir(DIR)));
		closedir DIR;
	}
	for my $dir (sort @SDKDIRS) {
		my $isuniversal = 0;
		if ($dir =~ /MacOSX([\d\.]+)(u?)\.sdk/) {
			my $version = $1;
			$isuniversal = 1 if ($2 eq "u");
			my ($shortversion) = $version =~ /^(\d+\.\d+)/;

			my $versiontext = "$shortversion";

			$hash = {};
			$hash->{version} = $version . '-1';
			if ($isuniversal) {
				$hash->{package} = "system-sdk-${shortversion}-universal";
				$versiontext = "$shortversion Universal";
				$hash->{provides} = "system-sdk-${shortversion}";
			} else {
				$hash->{package} = "system-sdk-${shortversion}";
			}
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "[virtual package representing the Mac OS X $versiontext SDK]";
			$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
			$hash->{builddependsonly} = "true";
			$hash->{descdetail} = <<END;
This package represents the Mac OS X $versiontext SDK
provided by Apple, as part of XCode.  If it does not show as
installed, you can download XCode from Apple at:

  http://connect.apple.com/

(free registration required)
END
			$hash->{compilescript} = &gen_compile_script($hash);
			if (-d '/Developer/SDKs/' . $dir) {
				$hash->{status} = STATUS_PRESENT;
				$self->{$hash->{package}} = $hash;
			} else {
				$self->{$hash->{package}} = $hash
					unless (exists $self->{$hash->{package}}->{status} and $self->{$hash->{package}}->{status} eq STATUS_PRESENT);
			}
		}
	}

=item "xcode"

This package represents your XCode version.

=cut

	print STDERR "- checking for xcode version... " if ($options{debug});

	$hash = {};
	$hash->{package} = "xcode";
	$hash->{version} = '0-0';
	$hash->{status} = STATUS_ABSENT;
	$hash->{description} = "[virtual package representing the developer tools]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
This package represents the C/C++/ObjC developer tools
provided by Apple.  If it does not show as installed,
you can download it from Apple at:

  http://connect.apple.com/

(free registration required)
END
	$hash->{compilescript} = &gen_compile_script($hash);

	my $result = `defaults read /Developer/Applications/Xcode.app/Contents/version CFBundleShortVersionString 2>&1`;
	if (not $?) {
		# didn't fail
		chomp $result;
		$hash->{version} = $result . '-1';
		print STDERR $hash->{version}, "\n" if $options{debug};
		$hash->{status} = STATUS_PRESENT;
	} elsif ($options{debug}) {
		# failed, so display whatever error message or diagnostics we can find
		if ($!) {
			
			print STDERR "unknown ($!)\n";      # have ERRNO string, so use that
		} else {
			print STDERR "unknown:\n$result\n";	# dump command's own diagnostics
		}
	}

	$self->{$hash->{package}} = $hash;

=item "cctools-I<XXX>"

This package represents the compiler tools provided by Apple.  It is
considered present if either I</usr/bin/what /usr/bin/ld> or
I</usr/bin/ld -v> contain a valid cctools-I<XXX> string.

=cut

	# create dummy object for cctools version, if version was found in Config.pm
	print STDERR "- checking for cctools version... " if ($options{debug});

	if (-x "/usr/bin/as" and -x "/usr/bin/what") {
		my $LD_OUTPUT = '';
		if (my $tempfile = tmpnam()) {
			$LD_OUTPUT = `/usr/bin/as -v 2>&1 </dev/null -o $tempfile`;
			unlink $tempfile;
		} else {
			print STDERR "unable to get temporary file: $!" if ($options{debug});
		};
		if ($LD_OUTPUT =~ /^.*version cctools-(\d+).*?$/) {
			$cctools_version = $1;
		} elsif (-x "/usr/bin/ld" and `/usr/bin/what /usr/bin/ld` =~ /^.*PROJECT:\s*cctools-(\d+).*?$/) {
			$cctools_version = $1;
		}
	} else {
		print STDERR "/usr/bin/ld or /usr/bin/what not executable... " if ($options{debug});
	}

	$hash = {};
	$hash->{package} = "cctools";
	$hash->{status} = STATUS_PRESENT;
	$hash->{description} = "[virtual package representing the developer tools]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{builddependsonly} = "true";
	$hash->{descdetail} = <<END;
This package represents the C/C++/ObjC developer tools
provided by Apple.  If it does not show as installed,
you can download it from Apple at:

  http://connect.apple.com/

(free registration required)
END
	$hash->{compilescript} = &gen_compile_script($hash);

	if (defined ($cctools_version)) {
		$hash->{version} = $cctools_version."-1";
		print STDERR $hash->{version}, "\n" if ($options{debug});
	} else {
		print STDERR "unknown\n" if ($options{debug});
		$hash->{version} = '0-0';
		$hash->{status} = STATUS_ABSENT;
	}
	$self->{$hash->{package}} = $hash;

=item "cctools-single-module"

This package represents whether the cctools linker is capable
of using the -single_module flag.  It is considered present
if a dummy file can be linked using the -single_module flag.

=cut

	# create dummy object for cctools-single-module, if supported
	print STDERR "- checking for cctools -single_module support... " if ($options{debug});

if ($cctools_version) {
	if ($cctools_version >= 446) {
		$cctools_single_module = $cctools_version;
		print STDERR "yes, $cctools_version has it\n" if ($options{debug});
	} else {
		print STDERR "nope.  oh well.\n" if ($options{debug});
	}
} else {
	print STDERR "nope. oh well.\n" if ($options{debug});
}

	$hash = {};
	$hash->{package} = "cctools-single-module";
	$hash->{description} = "[virtual package, your dev tools support -single_module]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{builddependsonly} = "true";
	$hash->{descdetail} = <<END;
This package represents support for the -single_module
flag in the development tools provided by Apple.  If it
does not show as installed, you can download the latest
developer tools (called XCode for Mac OS X 10.3 and
above) from Apple at:

  http://connect.apple.com/

(free registration required)
END
	$hash->{compilescript} = &gen_compile_script($hash);

	if ($cctools_single_module) {
		$hash->{status} = STATUS_PRESENT;
		$hash->{version} = $cctools_single_module."-1";
	} else {
		$hash->{status} = STATUS_ABSENT;
		if ($cctools_version) {
			$hash->{version} = $cctools_version;
		} else {
			$hash->{version} = '0-0';
		}
	}
	$self->{$hash->{package}} = $hash;

=item "gcc-*"

The GCC virtual packages exist based on gcc* commands
in /usr/bin.  They are considered present based on
the successful execution of "gcc --version".

=cut

	print STDERR "- checking for various GCC versions:\n" if ($options{debug});
	if (opendir(DIR, "/usr/bin")) {
		for my $gcc (grep(/^gcc(-[\d\.]+)?$/, readdir(DIR))) {
			next if (-l "/usr/bin/$gcc");
			if (open(GCC, '/usr/bin/' . $gcc . ' -### -v -x c /dev/null 2>&1 |')) {
				my ($versionoutput, $version, $build);
				{ local $/ = undef; $versionoutput = <GCC> }
				close(GCC);
				next unless (defined $versionoutput);
				if ($versionoutput =~ /version gcc-(\d+), based on gcc version ([\d\.\-]+)/s) {
					($build, $version) = ($1, $2);
				} elsif ($versionoutput =~ /version (\d+), based on gcc version ([\d\.\-]+)/s) {
					($build, $version) = ($1, $2);
				} elsif ($versionoutput =~ /version ([\d\.\-]+) .*? build (\d+)/s) {
					($version, $build) = ($1, $2);
				} else {
					print STDERR "  - warning, unable to determine the version for $gcc\n" if ($options{debug});
					next;
				}

				$version =~ s/[\.\-]*$//;
				my ($shortversion) = $version =~ /^(\d+\.\d+)/;
				$shortversion = 2 if ($version eq "2.95.2");
				my $pkgname = "gcc$shortversion";

				# Don't interfere with real packages
				if (Fink::Status->query_package($pkgname)) {
					print STDERR "  - skipping $pkgname, there's a real package\n" if ($options{debug});
					next;
				}

				my $status = STATUS_PRESENT;

				if (my ($match) = $versionoutput =~ /^\s*\"?(\S*cc1(obj)?)\"?\s/s) {
					if (not -x $match or $match !~ m,^/,) {
						$status = STATUS_ABSENT;
						print STDERR "  - $gcc is looking for $1 to build on this arch, but it's not there\n" if ($options{debug});
					}
				}

				$hash = &gen_gcc_hash($pkgname, $version, $build, 0, $status);
				$self->{$hash->{package}} = $hash;
				print STDERR "  - found $version\n" if ($options{debug});
			}
		}
		closedir(DIR);
	} else {
		print STDERR "  - couldn't get the contents of /usr/bin: $!\n" if ($options{debug});
	}
	{
		# force presence of structs for some expected compilers
		# list each as %n=>%v
		my %expected_gcc = (
			'gcc2'    => '2.95.2',
			'gcc2.95' => '2.95.2',
			'gcc3.1'  => '3.1',
			'gcc3.3'  => '3.3',
			'gcc4.0'  => '4.0',
		);
		foreach my $key (sort keys %expected_gcc) {
			if (not exists $self->{$key} && not Fink::Status->query_package($key)) {
				$hash = &gen_gcc_hash($key, $expected_gcc{$key}, 0, 0, STATUS_ABSENT);
				$self->{$hash->{package}} = $hash;
				print STDERR "  - missing $expected_gcc{$key}\n" if ($options{debug});
			}
		}
	}

=item "broken-gcc"

This package represents broken versions of the GCC compiler
as shipped by Apple.  Currently it checks for the XCode 1.5
cc1plus.

=cut

	my @badbuilds = qw(1666);

	print STDERR "- checking for broken GCCs:\n" if ($options{debug});
	$hash = {};
	$hash->{package} = "broken-gcc";
	$hash->{status} = STATUS_ABSENT;
	$hash->{version} = "3.3-1";
	$hash->{description} = "[virtual package representing a broken gcc compiler]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{builddependsonly} = "true";
	$hash->{descdetail} = <<END;
This package represents broken versions of the GCC compiler
as shipped by Apple.  If this package shows as installed,
you should see if there is a newer version of the developer
tools at:

  http://connect.apple.com/

(free registration required)
END
	$hash->{compilescript} = &gen_compile_script($hash);

	for my $key (keys %$self) {
		if ($key =~ /^gcc/) {
			my ($buildnum) = $self->{$key}->{version} =~ /^.*\-(\d+)$/;
			print STDERR "  - $key build number is $buildnum" if ($options{debug});
			if (grep /^${buildnum}$/, @badbuilds) {
				print STDERR " (bad)\n" if ($options{debug});
				$hash->{status} = STATUS_PRESENT;
				$hash->{version} = $self->{$key}->{version};
			} else {
				print STDERR " (not broken)\n" if ($options{debug});
			}
		}
	}

	$self->{$hash->{package}} = $hash;

=item "dev-tools"

This package represents a developer suite of command-line compilers
and related programs, for example, Apple's DevTools (OS X <= 10.2) or
XCode (OS X >= 10.3). This package is considered "installed" iff
/usr/bin/gcc and /usr/bin/gcc exist and are executable.

=cut

	# create dummy object for devtools
	$hash = {
		package     => 'dev-tools',
		version     => '0-1',
		status      => STATUS_PRESENT,
		description => '[virtual package representing developer commands]',
		homepage    => 'http://www.finkproject.org/faq/usage-general.php#virtpackage',
		descdetail  => <<END,
This package represents the basic command-line compiler and
related programs.  In order for this package to be "installed",
you must have /usr/bin/gcc and /usr/bin/make available on your
system.  You can obtain them by installing the Apple developer
tools (also known as XCode on Mac OS X 10.3 and above).  The
latest versions of the Apple developer tools are always
available from Apple at:

  http://connect.apple.com/

(free registration required)
END
	};

	print STDERR "- checking for dev-tools commands:\n" if ($options{debug});
	foreach my $file (qw| /usr/bin/gcc /usr/bin/make |) {
		$options{debug} && printf STDERR " - %s... %s\n", $file, -x $file ? "found" : "missing!";
		$hash->{status} = STATUS_ABSENT if not -x $file;
	}

	$hash->{compilescript} = &gen_compile_script($hash);

	$self->{$hash->{package}} = $hash;

=item "gimp-print-shlibs"

This package represents the GIMP printing libraries
provided by Apple on Mac OS X 10.3 and higher.  They
are considered present if libgimpprint.1.dylib exists
in /usr/lib.

=cut

	$hash = {};
	$hash->{package} = "gimp-print-shlibs";
	$hash->{version} = "4.2.5-1";
	$hash->{description} = "[virtual package representing Apple's install of Gimp Print]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
This package represents the version of Gimp-Print that
comes with Mac OS X 10.3 and above.  If it shows as not
installed, you must install the GimpPrintPrinterDrivers
package that came with your Mac OS X CDs.
END
	$hash->{compilescript} = &gen_compile_script($hash);

	if ( has_lib('libgimpprint.1.dylib') ) {
		print STDERR "- found gimp-print-shlibs 4.2.5-1\n" if ($options{debug});
		$hash->{status} = STATUS_PRESENT;
	} else {
		$hash->{status} = STATUS_ABSENT;
	}
	$self->{$hash->{package}} = $hash;

=item "gimp-print7-shlibs"

This package represents the GIMP printing libraries
provided by Apple on Mac OS X 10.4 and higher.  They
are considered present if libgimpprint.7.dylib exists
in /usr/lib.

=cut

	$hash = {};
	$hash->{package} = "gimp-print7-shlibs";
	$hash->{version} = "5.0.0-beta2-1";
	$hash->{description} = "[virtual package representing Apple's install of Gimp Print]";
	$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
	$hash->{descdetail} = <<END;
This package represents the version of Gimp-Print that
comes with Mac OS X 10.4 and above.  If it shows as not
installed, you must install the GimpPrintPrinterDrivers
package that came with your Mac OS X DVD.
END
	$hash->{compilescript} = &gen_compile_script($hash);

	if ( has_lib('libgimpprint.7.dylib') ) {
		print STDERR "- found gimp-print7-shlibs 5.0.0-beta2-1\n" if ($options{debug});
		$hash->{status} = STATUS_PRESENT;
	} else {
		$hash->{status} = STATUS_ABSENT;
	}
	$self->{$hash->{package}} = $hash;

=item [pkgconfig packages]

Fink will scan for .pc files in common places, and create
virtual packages. (See &package_from_pkgconfig).

=cut

	for my $dir ('/usr/X11/lib/pkgconfig', '/usr/X11R6/lib/pkgconfig', '/usr/lib/pkgconfig') {
		next unless (-d $dir);
		if (opendir(PKGCONFIG_DIR, $dir)) {
			while (my $file = readdir(PKGCONFIG_DIR)) {
				next unless ($file =~ /\.pc$/);
				next unless my $hash = package_from_pkgconfig($dir . '/' . $file);
				$self->{$hash->{package}} = $hash;
			}
		} else {
			print STDERR "WARNING: unable to read from $dir: $!\n";
		}
	}

	if ( has_lib('libX11.6.dylib') )
	{
		# check the status of xfree86 packages
		my $packagecount = 0;
		for my $packagename ('system-xfree86', 'xfree86-base', 'xfree86-rootless',
			'xfree86-base-threaded', 'system-xfree86-43', 'system-xfree86-42',
			'xfree86-base-shlibs', 'xfree86', 'system-xtools',
			'xfree86-base-threaded-shlibs', 'xfree86-rootless-shlibs',
			'xfree86-rootless-threaded-shlibs', 'xorg', 'xorg-shlibs')
		{
			
			if (Fink::Status->query_package($packagename)) {
				print STDERR "- $packagename is installed\n" if ($options{debug});
				$packagecount++;
			}
		}

		# if no xfree86 packages are installed, put in our own placeholder
		if ($packagecount == 0) {

			my $descdetail = <<END;
This package represents a pre-existing installation
of X11 on your system that is not installed through
Fink.

If it shows as not installed, you likely need to
install the X11User and/or X11SDK packages from
Apple, or a similarly-compatible version.  For more
information, please see the FAQ entry on X11
installation at:

  http://www.finkproject.org/faq/usage-packages.php#apple-x11-wants-xfree86

END

			$hash = {};
			$hash->{package} = "system-xfree86-shlibs";
			$hash->{version} = "0-0";
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "[virtual package representing Apple's install of X11]";
			$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
			$hash->{descdetail} = $descdetail;
			$hash->{compilescript} =  &gen_compile_script($hash);
			$hash->{provides} = 'x11-shlibs, libgl-shlibs, xft1-shlibs, xft2-shlibs, fontconfig1-shlibs, xfree86-base-threaded-shlibs';
			$self->{$hash->{package}} = $hash;

			$hash = {};
			$hash->{package} = "system-xfree86";
			$hash->{version} = "0-0";
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "[virtual package representing Apple's install of X11]";
			$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
			$hash->{descdetail} = $descdetail;
			$hash->{compilescript} =  &gen_compile_script($hash);
			$hash->{provides} = 'x11, xserver, libgl, xft1, xft2, fontconfig1, xfree86-base-threaded';
			$self->{$hash->{package}} = $hash;

			$hash = {};
			$hash->{package} = "system-xfree86-dev";
			$hash->{version} = "0-0";
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "[virtual package representing Apple's install of X11]";
			$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
			$hash->{descdetail} = $descdetail;
			$hash->{compilescript} =  &gen_compile_script($hash);
			$hash->{provides} = 'x11-dev, libgl-dev, xft1-dev, xft2-dev, fontconfig1-dev, xfree86-base-threaded-dev';
			$self->{$hash->{package}} = $hash;

			$hash = {};
			$hash->{package} = "system-xfree86-manual-install";
			$hash->{version} = "0-0";
			$hash->{status} = STATUS_ABSENT;
			$hash->{description} = "Manually installed X11 components";
			$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
			$hash->{descdetail} = <<END;
This package represents the various components of an
X11 on your system that is not installed through Fink.

You can either use a Fink-supplied X11, such as the
xfree86 or xorg sets of packages, or you can use a
manually-installed (non-Fink) X11, such as Apple's
X11User and X11SDK packages. You must not mix X11
suppliers. If you are already using some type of
manually-installed X11, please make sure you have
installed all components of it.

For more information, please see the FAQ entry on X11
installation at:

  http://www.finkproject.org/faq/usage-packages.php#apple-x11-wants-xfree86

END
			$hash->{compilescript} = &gen_compile_script($hash);

			$hash->{provides} = join ',', map $self->{$_}->{provides}, qw/ system-xfree86 system-xfree86-shlibs system-xfree86-dev /;
			$self->{$hash->{package}} = $hash;

			my $found_pc_x11 = 1;
			for my $pkgname ('applewm', 'fontconfig', 'freetype2', 'x11', 'xcb', 'xorg-server') {
				if (not exists $self->{$pkgconfig_virtual_prefix . $pkgname} or $self->{$pkgconfig_virtual_prefix . $pkgname}->{status} ne STATUS_PRESENT) {
					$found_pc_x11 = 0;
					last;
				}
			}
			my $xver = 0;
			if ($found_pc_x11) {
				$xver = '7.2';
			} else {
				($xver) = check_x11_version();
			}

			if (defined $xver) {
				$hash = {};
				my $provides;

				my $found_xserver = 0;
				print STDERR "- checking for X servers... " if ($options{debug});
				XSERVERLOOP: for my $xdir ('/usr/X11R6', '/usr/X11') {
					for my $xserver (@xservers) {
						if (-x $xdir . '/bin/' . $xserver) {
							print STDERR "$xdir/bin/$xserver\n" if ($options{debug});
							$found_xserver++;
							last XSERVERLOOP;
						}
					}
				}
				print STDERR "missing\n" if ($options{debug} and $found_xserver == 0);

=item "system-xfree86-shlibs"

This package represents the shared libraries from an
X11 installation (be it XFree86, X.org, Apple's X11,
or something else).  It is considered present if
libX11.*.dylib exists.

=cut

				# this is always there if we got this far
				print STDERR "  - system-xfree86-shlibs provides x11-shlibs\n" if ($options{debug});
				push(@{$provides->{'system-xfree86-shlibs'}}, 'x11-shlibs');

=item "system-xfree86"

This package represents an X11 implementation up to
and including the X server.  It is considered present
if an X server is found.

=cut

				if ( $found_xserver ) {
					print STDERR "  - found an X server, system-xfree86 provides xserver and x11\n" if ($options{debug});
					push(@{$provides->{'system-xfree86'}}, 'xserver', 'x11');
				}

=item "system-xfree86-dev"

This package represents the development headers and
libraries for X11.  It is considered present if the
X11/Xlib.h header is found.

=cut

				# "x11-dev" is for BuildDepends: on x11 packages
				if ( has_header('X11/Xlib.h') ) {
					print STDERR "  - system-xfree86-dev provides x11-dev\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-dev'}}, 'x11-dev');
				}

=item extra X11 provides

Depending on the existence of certain files,
the system-xfree86* packages can B<Provide> a number
of extra virtual packages.

=over

=item "libgl" and "libgl-shlibs"

These packages represent the existence of the OpenGL
libraries.  They are considered present if libGL.1.dylib
is found.

=cut

				# now we do the same for libgl
				if ( has_lib('libGL.1.dylib') ) {
					print STDERR "  - system-xfree86-shlibs provides libgl-shlibs\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-shlibs'}}, 'libgl-shlibs');
					print STDERR "  - system-xfree86 provides libgl\n" if ($options{debug});
					push(@{$provides->{'system-xfree86'}}, 'libgl');
				}

=item "libgl-dev"

This package represents the existence of the OpenGL
development headers and libraries.  It is considered
present if GL/gl.h and libGL.dylib are found.

=cut

				if ( has_header('GL/gl.h') and has_lib('libGL.dylib') ) {
					print STDERR "  - system-xfree86-dev provides libgl-dev\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-dev'}}, 'libgl-dev');
				}

=item "xftI<X>-shlibs"

This package represents the shared libraries for
the modern font API for X.  It currently creates
a B<Provide> for major versions 1 and 2 of the
libXft.[version].dylib library if it is found.

=cut

				for my $ver (1, 2) {
					if ( has_lib("libXft.${ver}.dylib") ) {
						print STDERR "  - system-xfree86-shlibs provides xft${ver}-shlibs\n" if ($options{debug});
						push(@{$provides->{'system-xfree86-shlibs'}}, "xft${ver}-shlibs");
					}
				}

=item "xftI<X>" and "xftI<X>-dev"

These packages represent the development headers and
library for the Xft font API.  It is considered present
if libXft.dylib exists and the version number I<X> is based
on the version the symlink points to.

=cut

				if ( has_lib('libXft.dylib') ) {
					if ( defined readlink('/usr/X11R6/lib/libXft.dylib') ) {
						my $link = readlink('/usr/X11R6/lib/libXft.dylib');
						if ($link =~ /libXft\.(\d)/) {
							my $major_version = $1;
							print STDERR "  - libXft points to Xft${major_version}\n" if ($options{debug});
							print STDERR "    - system-xfree86-dev provides xft${major_version}-dev\n" if ($options{debug});
							push(@{$provides->{'system-xfree86-dev'}}, "xft${major_version}-dev");
							print STDERR "    - system-xfree86 provides xft${major_version}\n" if ($options{debug});
							push(@{$provides->{'system-xfree86'}}, "xft${major_version}");
						}
					}
				}

=item "fontconfigI<X>-shlibs"

This package reprents the font configuration API for
X11.  It is considered present if libfontconfig.*.dylib
is found.

=cut

				if ( has_lib('libfontconfig.1.dylib') ) {
					print STDERR "  - system-xfree86-shlibs provides fontconfig1-shlibs\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-shlibs'}}, 'fontconfig1-shlibs');
				}

=item "fontconfigI<X>" and "fontconfigI<X>-dev"

These packages represent the development headers and
library for the X11 font configuration API.  It is
considered present if libXft.dylib exists.

=cut

				if ( has_lib('libfontconfig.dylib') and
						defined readlink('/usr/X11R6/lib/libfontconfig.dylib') and
						readlink('/usr/X11R6/lib/libfontconfig.dylib') =~ /libfontconfig\.1/ and
						has_header('fontconfig/fontconfig.h') ) {
					print STDERR "  - libfontconfig points to fontconfig1\n" if ($options{debug});
					print STDERR "    - system-xfree86-dev provides fontconfig1-dev\n" if ($options{debug});
					push(@{$provides->{'system-xfree86-dev'}}, 'fontconfig1-dev');
					print STDERR "    - system-xfree86 provides fontconfig1\n" if ($options{debug});
					push(@{$provides->{'system-xfree86'}}, 'fontconfig1');
				}

=item "rman"

This package represents the X11-based man-page reader.
It is considered present if /usr/X11R6/bin/rman exists.

=cut

				print STDERR "- checking for rman... " if ($options{debug});
				for my $xdir ('/usr/X11R6', '/usr/X11') {
					print STDERR "$xdir... " if ($options{debug});
					if (-x $xdir . '/bin/rman') {
						print STDERR "found, system-xfree86 provides rman\n" if ($options{debug});
						push(@{$provides->{'system-xfree86'}}, 'rman');
					} else {
						print STDERR "missing\n" if ($options{debug});
					}
				}

=item "xfree86-base-threaded" and "xfree86-base-threaded-shlibs"

These packages represent whether libXt has support for threading.
It is considered present if the pthread_mutex_lock symbol exists
in the library.

=back

=cut

				print STDERR "- checking for threaded libXt... " if ($options{debug});
				if (-f '/usr/X11R6/lib/libXt.6.dylib' and -x '/usr/bin/grep') {
					if (system('/usr/bin/grep', '-q', '-a', 'pthread_mutex_lock', '/usr/X11R6/lib/libXt.6.dylib') == 0) {
						print STDERR "threaded\n" if ($options{debug});
						print STDERR "  - system-xfree86-shlibs provides xfree86-base-threaded-shlibs\n" if ($options{debug});
						push(@{$provides->{'system-xfree86-shlibs'}}, 'xfree86-base-threaded-shlibs');
						if (grep(/^x11$/, @{$provides->{'system-xfree86'}})) {
							print STDERR "  - system-xfree86 provides xfree86-base-threaded\n" if ($options{debug});
							push(@{$provides->{'system-xfree86'}}, 'xfree86-base-threaded');
						}
					} else {
						print STDERR "not threaded\n" if ($options{debug});
					}
				} else {
					print STDERR "missing libXt or grep\n" if ($options{debug});
				}

				if (exists $provides->{'system-xfree86-dev'} and defined $provides->{'system-xfree86-dev'} and not grep(/^x11-dev$/, @{$provides->{'system-xfree86-dev'}})) {
					print STDERR "WARNING: you have an incomplete X11 installation.\n  See http://finkproject.org/faq/usage-packages.php#special-x11-debug for details on repairing it.\n";
				}

				for my $pkg ('system-xfree86', 'system-xfree86-shlibs', 'system-xfree86-dev') {
					if (exists $provides->{$pkg}) {
						$self->{$pkg} = {
							'package'     => $pkg,
							'status'      => STATUS_PRESENT,
							'version'     => "2:${xver}-2",
							'description' => "[placeholder for user installed x11]",
							'descdetail'  => $descdetail,
							'homepage'    => "http://www.finkproject.org/faq/usage-general.php#virtpackage",
							'provides'    => join(', ', @{$provides->{$pkg}}),
						};
						$self->{$pkg}->{compilescript} = &gen_compile_script($self->{$pkg});
						if ($pkg eq "system-xfree86-shlibs") {
							$self->{$pkg}->{'description'} = "[placeholder for user installed x11 shared libraries]";
						} elsif ($pkg eq "system-xfree86-dev") {
							$self->{$pkg}->{'description'} = "[placeholder for user installed x11 development tools]";
							$self->{$pkg}->{builddependsonly} = 'true';
						}
					}
				}
			}
			if (exists $self->{'system-xfree86-dev'}
					and exists $self->{'system-xfree86-shlibs'}
					and exists $self->{'system-xfree86-manual-install'}
					and $self->{'system-xfree86-dev'}->{'status'} eq STATUS_PRESENT
					and $self->{'system-xfree86-shlibs'}->{'status'} eq STATUS_PRESENT) {
				$self->{'system-xfree86-manual-install'}->{'status'} = STATUS_PRESENT;
			 	$self->{'system-xfree86-manual-install'}->{'version'} = $self->{'system-xfree86-dev'}->{'version'};
			}
		} else {
			print STDERR "- skipping X11 virtuals, existing X11 packages installed\n" if ($options{debug});
		}
	}

=item "growl"

This package represents the Growl notification system.
For more info on this package see http://growl.info/.

=cut

	print STDERR "- checking for Growl... " if ($options{debug});
	if (-x '/Library/PreferencePanes/Growl.prefPane/Contents/Resources/GrowlHelperApp.app/Contents/MacOS/GrowlHelperApp' || -x '/Applications/Growl.app/Contents/MacOS/Growl') {
		print STDERR "found, Growl\n" if ($options{debug});
		print STDERR "- checking for Growl version... " if ($options{debug});
		if (-f "/Library/PreferencePanes/Growl.prefPane/Contents/Info.plist") {
			if (open(FILEIN, '/Library/PreferencePanes/Growl.prefPane/Contents/Info.plist')) {
				local $/ = undef;
				# Growl beta versions contain the letter b
				if (<FILEIN> =~ /<key>CFBundleVersion<\/key>[\r\n\s]*<string>([b\d\.]+)<\/string>/) {
					$growl_version = $1;
				}
				close(FILEIN);
			}
		} elsif (-f "/Applications/Growl.app/Contents/Info.plist") {
			if (open(FILEIN, '/Applications/Growl.app/Contents/Info.plist')) {
				local $/ = undef;
				# Growl beta versions contain the letter b
				if (<FILEIN> =~ /<key>CFBundleVersion<\/key>[\r\n\s]*<string>([b\d\.]+)<\/string>/) {
					$growl_version = $1;
				}
				close(FILEIN);
			}
		} else {
			print STDERR "/Library/PreferencePanes/Growl.prefPane/Contents/Info.plist or\n/Applications/Growl.app/Contents/Info.plist not found... " if ($options{debug});
 			$growl_version = "0";
		}

		### This check is for growl's less then 0.6
		### Growl team told me 1.0 would be versioned 1.00
		if ($growl_version eq "1.0") {
			if (-f "/Library/Receipts/Growl.pkg/Contents/Info.plist") {
				if (open(FILEIN, '/Library/Receipts/Growl.pkg/Contents/Info.plist')) {
					local $/ = undef;
					if (<FILEIN> =~ /<key>CFBundleShortVersionString<\/key>[\r\n\s]*<string>([\d\.]+)<\/string>/) {
						$growl_version = $1;
					}
					close(FILEIN);
				} 
			} else {
				print STDERR "/Library/Receipts/Growl.pkg/Contents/Info.plist not found... " if ($options{debug});
				$growl_version = "0";
			}
		}
	} else {
		print STDERR "missing\n" if ($options{debug});
	}

	$hash = {};
	$hash->{package} = "growl";
	$hash->{status} = STATUS_PRESENT;
	$hash->{description} = "[virtual package representing Growl]";
	$hash->{homepage} = "http://growl.info/";
	$hash->{descdetail} = <<END;
Growl is a global notification system for Mac OS X. Any
application can send a notification to Growl, which will
display an attractive message on your screen. Growl
currently works with a growing number of applications.

  http://growl.info/

Please note that this virtual package expects you to have
Growl installed system-wide in the
/Library/PreferencePanes directory, rather than in a
per-user ~/Library/PreferencePanes directory.
END
	$hash->{compilescript} = &gen_compile_script($hash);

	if (defined ($growl_version)) {
		$hash->{version} = $growl_version."-1";
		print STDERR $hash->{version}, "\n" if ($options{debug});
	} else {
		print STDERR "unknown\n" if ($options{debug});
		$hash->{version} = '0-0';
		$hash->{status} = STATUS_ABSENT;
	}
	$self->{$hash->{package}} = $hash;
}

=back

=head1 INTERNAL APIs

=over

=item $self->query_package(I<package_name>)

Query a package by name.

Returns false when not installed, returns the
full version when installed and configured.

=cut

sub query_package {
	my $self = shift;
	my $pkgname = shift;
	my ($hash);

	if (not ref($self)) {
		if (defined($the_instance)) {
			$self = $the_instance;
		} else {
			$self = Fink::VirtPackage->new();
		}
	}

	if (exists $self->{$pkgname} and exists $self->{$pkgname}->{status} and not $config->mixed_arch()) {
		my ($purge, $ok, $installstat) = split(/\s+/, $self->{$pkgname}->{status});
		return $self->{$pkgname}->{version} if ($installstat eq "installed" and exists $self->{$pkgname}->{version});
	}
	return undef;
}

=item $self->list(I<%options>)

Retrieves a complete hash of all virtual packages,
with versions, regardless of installed status.

The list is a hash reference, with the package name
as key and the value a reference to a hash containing
the package attributes.  The I<package> and I<version>
attributes are guaranteed to exist.

%options is provided for future implementation, but
currently does nothing.

=cut

sub list {
	my $self = shift;
	%options = (@_);

	my ($list, $pkgname, $hash, $newhash, $field);

	if (not ref($self)) {
		if (defined($the_instance)) {
			$self = $the_instance;
		} else {
			$self = Fink::VirtPackage->new();
		}
	}

	$list = {};
	foreach $pkgname (keys %$self) {
		next if $pkgname =~ /^_/;
		$hash = $self->{$pkgname};
		next unless exists $hash->{version};

		$newhash = { 'package' => $pkgname, 'version' => $hash->{version} };
		foreach $field (qw(depends provides conflicts maintainer description descdetail homepage status builddependsonly compilescript)) {
			if (exists $hash->{$field}) {
				$newhash->{$field} = $hash->{$field};
			}
		}
		$newhash->{status} = STATUS_ABSENT if $config->mixed_arch();
		$list->{$pkgname} = $newhash;
	}

	return $list;
}

=item &has_header(I<$headername>)

Searches for a header file in a list of common places.

Returns true if found, false if not.

=cut

sub has_header {
	my $headername = shift;
	my $dir;

	print STDERR "- checking for header $headername... " if ($options{debug});
	if ($headername =~ /^\// and -f $headername) {
		print STDERR "found\n" if ($options{debug});
		return 1;
	} else {
		for $dir ('/usr/X11R6/include', $basepath . '/include', '/usr/include') {
			if (-f $dir . '/' . $headername) {
				print STDERR "found in $dir\n" if ($options{debug});
				return 1;
			}
		}
	}
	print "missing\n" if ($options{debug});
	return;
}

=item &has_lib(I<$libname>)

Searches for a library in a list of common places.

Returns true if found, false if not.

=cut

sub has_lib {
	my $libname = shift;
	my $dir;

	print STDERR "- checking for library $libname... " if ($options{debug});
	if ($libname =~ /^\// and -f $libname) {
		print STDERR "found\n" if ($options{debug});
		return 1;
	} else {
		for $dir ('/usr/X11R6/lib', $basepath . '/lib', '/usr/lib') {
			if (-f $dir . '/' . $libname) {
				print STDERR "found in $dir\n" if ($options{debug});
				return 1;
			}
		}
	}
	print STDERR "missing\n" if ($options{debug});
	return;
}

=item &package_from_pkgconfig($name)

Creates a virtual package from a pkgconfig file.

If $name is a relative path, searches /usr, /usr/X11,
and /usr/X11R6 pkgconfig directories and takes the
first match.

The package name will be the in the form
"system-pkgconfig-I<name>".

Returns a package object hash.

=cut

sub package_from_pkgconfig {
	my $filename = shift;
	my @search_files;

	print STDERR "- scanning pkgconfig file $filename... " if ($options{debug});
	if ($filename =~ /^\//) {
		push(@search_files, $filename);
	} else {
		for my $dir ('/usr', '/usr/X11', '/usr/X11R6') {
			push(@search_files, $dir . '/lib/pkgconfig/' . $filename);
		}
	}

	for my $file (@search_files) {
		if (-e $file) {
			my $hash = {};
			my $name = basename($file);
			$name =~ s/\.pc$//;

			my $pkgconfig_hash = {};
			$hash->{package} = $pkgconfig_virtual_prefix . $name;

			if (open(PKGCONFIG, $file)) {
				while (my $line = <PKGCONFIG>) {
					chomp($line);
					if ($line =~ /^\s*([^\:]+)\s*\:\s*(.*?)\s*$/) {
						$pkgconfig_hash->{lc($1)} = $2;
					}
				}
				close(PKGCONFIG);
			} else {
				print STDERR "WARNING: could not read $file: $!\n" if ($options{debug});
			}

			$hash->{description} = "[virtual pkgconfig package representing $name]";
			$hash->{homepage} = "http://www.finkproject.org/faq/usage-general.php#virtpackage";
			$hash->{status} = STATUS_PRESENT;
			if ($pkgconfig_hash->{'version'}) {
				$hash->{version} = $pkgconfig_hash->{'version'} . '-1';
				print STDERR $hash->{version}, "\n" if ($options{debug});
			} else {
				$hash->{version} = '0-0';
				print STDERR "unknown\n" if ($options{debug});
			}
			$hash->{descdetail} = <<END;
$pkgconfig_hash->{'description'}

This package represents the pkgconfig file found at:
	$file
END
			my $requires = "";
			for ('requires', 'requires.private') {
				if (exists $pkgconfig_hash->{$_}) {
					$requires .= " " . $pkgconfig_hash->{$_};
				}
			}
			$requires =~ s/^ *//;
			if ($requires ne "") {
				$hash->{descdetail} .= "\nIt expects the following pkgconfig packages to exist:\n\t" . $requires . "\n";
			}
			$hash->{compilescript} = &gen_compile_script($hash);
			return $hash;

			last;
		}
	}
}

=item &check_x11_version()

Attempts to determine the version of X11 based on a number of
heuristics, including parsing the versions in man pages (less expensive)
and running B<Xserver -version> (more expensive).

Returns the X11 version if found.

=cut

### Check the installed x11 version
sub check_x11_version {
	my (@XF_VERSION_COMPONENTS, $XF_VERSION);
	for my $checkfile ('xterm.1', 'bdftruncate.1', 'gccmakedep.1') {
		for my $xdir ('/usr/X11R6', '/usr/X11') {
			if (-f "$xdir/man/man1/$checkfile") {
				if (open(CHECKFILE, "$xdir/man/man1/$checkfile")) {
					while (<CHECKFILE>) {
						if (/^.*Version\S* ([^\s]+) .*$/) {
							$XF_VERSION = $1;
							@XF_VERSION_COMPONENTS = split(/\.+/, $XF_VERSION, 4);
							last;
						}
					}
					close(CHECKFILE);
				} else {
					print STDERR "WARNING: could not read $checkfile: $!\n"
						if ($options{debug});
					return;
				}
			}
			last if (defined $XF_VERSION);
		}
	}
	if (not defined $XF_VERSION) {
		for my $binary (@xservers, 'X') {
			for my $xdir ('/usr/X11R6', '/usr/X11') {
				if (-x $xdir . '/bin/' . $binary) {
					if (open (XBIN, "$xdir/bin/$binary -version 2>\&1 |")) {
						while (my $line = <XBIN>) {
							if ($line =~ /(?:XFree86 Version|X Protocol.* Release|X.org Release) ([\d\.]+)/) {
								$XF_VERSION = $1;
								@XF_VERSION_COMPONENTS = split(/\.+/, $XF_VERSION, 4);
								last;
							}
						}
						close(XBIN);
					} else {
						print STDERR "couldn't run $binary: $!\n";
					}
					last;
				}
			}
		}
	}
	if (not defined $XF_VERSION) {
		print STDERR "could not determine XFree86 version number\n";
		return;
	}

	if (@XF_VERSION_COMPONENTS >= 4) {
		# it's a snapshot (ie, 4.3.99.15)
		# give back 3 parts of the component
		return (join('.', @XF_VERSION_COMPONENTS[0..2]));
	} elsif (@XF_VERSION_COMPONENTS >= 2) {
		return (join('.', @XF_VERSION_COMPONENTS[0..1]));
	} else {
		if ($XF_VERSION_COMPONENTS[0] =~ /X Protocol Version (.*), Revision (.*),/) {
			return ("$1.$2");
			} else {
				print "Could not parse: @XF_VERSION_COMPONENTS\n";
			}
	}
}

=item &gen_gcc_hash(I<$package>, I<$version>, I<$build>, I<$is_64bit>, I<$dpkg_status>)

Return a ref to a hash representing a gcc* package pdb structure. The
passed values are will not be altered.

=cut

sub gen_gcc_hash {
	my $package = shift;
	my $version = shift;
	my $build   = shift;
	my $is_64bit = shift;
	my $status = shift;
	$is_64bit = $is_64bit ? ' 64-bit' : '';

	my $revision = $build;
	unless (defined $revision and $revision =~ /^\d+$/) {
		$revision = 0;
		$revision = 1 if ($status eq STATUS_PRESENT);
	}

	my $return = {
		package          => $package,
		version          => $version . '-' . $revision,
		description      => "[virtual package representing the$is_64bit gcc $version compiler]",
		homepage         => 'http://www.finkproject.org/faq/comp-general.php#gcc2',
		builddependsonly => 'true',
		descdetail       => <<END,
This package represents the$is_64bit gcc $version compiler,
which is part of the Apple developer tools (also known as
XCode on Mac OS X 10.3 and above).  The latest versions of
the Apple developer tools are always available from Apple at:

  http://connect.apple.com/

(free registration required)

Note that some versions of GCC are *not* installed by default
when installing XCode.  Make sure you customize your install
and check all GCC versions to ensure proper compatibility
with Fink.

Note also that older compilers for 10.4 can be obtained by installing
the "XCode Legacy Compilers" package available at the same address.
END
		status           => $status
	};

	$return->{compilescript} = &gen_compile_script($return);
	return $return;
}


=item &gen_compile_script(I<\%pkg_hash>)

Return the text to put in compilescript for a package, given a ref to
a hash containing other parts (descdetail and homepage) and of the
package description.

=cut

sub gen_compile_script {
	my $pkg_hash = shift;

	my $descdetail = $pkg_hash->{descdetail};
	my $homepage = $pkg_hash->{homepage};

	my $return = <<END;
#!/bin/sh -e
cat <<EOMSG

+----------
|
| Attention!
| 
| Package %n is an autogenerated virtual package.
| 
| You cannot manipulate this type of package using the usual Fink tools.
| A detailed description of this package follows...
| 
END

	for my $line (split(/\n/, $descdetail)) {
		$return .= "| " . $line . "\n";
	}

	if (defined $homepage and length $homepage) {
		$return .= "| \n| Web site: $homepage\n";
	}

	$return .= <<END;
| 
+----------

EOMSG
exit 1
END

	return $return;
}


=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
