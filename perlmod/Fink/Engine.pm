# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Engine class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2004 The Fink Package Manager Team
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
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA	 02111-1307, USA.
#

package Fink::Engine;

use Fink::Services qw(&latest_version &sort_versions &execute &file_MD5_checksum &get_arch &expand_percent &count_files);
use Fink::CLI qw(&print_breaking &prompt_boolean &prompt_selection_new &get_term_width);
use Fink::Package;
use Fink::PkgVersion;
use Fink::Config qw($config $basepath $debarch);
use File::Find;
use Fink::Status;
use Fink::Command qw(mkdir_p);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&cmd_install);
	%EXPORT_TAGS = ( );		# eg: TAG => [ qw!name1 name2! ],
}
our @EXPORT_OK;

# The list of commands. Maps command names to a list containing
# a function reference, and three flags. The first flag indicates
# whether this command requires the package descriptions to be
# read, the second flag whether root permissions are needed the
# third flag whether apt-get might be called if the UseBinaryDist
# option is enabled. 1, if apt-get is called without the 
# '--ignore-breakage' option, 2, if it is called with '--ignore-breakage'
our %commands =
	( 'index'             => [\&cmd_index,             0, 1, 1],
	  'rescan'            => [\&cmd_rescan,            0, 0, 0],
	  'configure'         => [\&cmd_configure,         0, 1, 0],
	  'bootstrap'         => [\&cmd_bootstrap,         0, 1, 0],
	  'fetch'             => [\&cmd_fetch,             1, 1, 0],
	  'fetch-all'         => [\&cmd_fetch_all,         1, 1, 0],
	  'fetch-missing'     => [\&cmd_fetch_all_missing, 1, 1, 0],
	  'build'             => [\&cmd_build,             1, 1, 2],
	  'rebuild'           => [\&cmd_rebuild,           1, 1, 2],
	  'install'           => [\&cmd_install,           1, 1, 2],
	  'reinstall'         => [\&cmd_reinstall,         1, 1, 2],
	  'update'            => [\&cmd_install,           1, 1, 2],
	  'update-all'        => [\&cmd_update_all,        1, 1, 2],
	  'enable'            => [\&cmd_install,           1, 1, 2],
	  'activate'          => [\&cmd_install,           1, 1, 2],
	  'use'               => [\&cmd_install,           1, 1, 2],
	  'disable'           => [\&cmd_remove,            1, 1, 0],
	  'deactivate'        => [\&cmd_remove,            1, 1, 0],
	  'unuse'             => [\&cmd_remove,            1, 1, 0],
	  'remove'            => [\&cmd_remove,            1, 1, 0],
	  'delete'            => [\&cmd_remove,            1, 1, 0],
	  'purge'             => [\&cmd_purge,             1, 1, 0],
	  'apropos'           => [\&cmd_apropos,           0, 0, 0],
	  'describe'          => [\&cmd_description,       1, 0, 0],
	  'description'       => [\&cmd_description,       1, 0, 0],
	  'desc'              => [\&cmd_description,       1, 0, 0],
	  'info'              => [\&cmd_description,       1, 0, 0],
	  'scanpackages'      => [\&cmd_scanpackages,      1, 1, 1],
	  'list'              => [\&cmd_list,              0, 0, 0],
	  'listpackages'      => [\&cmd_listpackages,      1, 0, 0],
	  'selfupdate'        => [\&cmd_selfupdate,        0, 1, 1],
	  'selfupdate-cvs'    => [\&cmd_selfupdate_cvs,    0, 1, 1],
	  'selfupdate-rsync'  => [\&cmd_selfupdate_rsync,  0, 1, 1],
	  'selfupdate-finish' => [\&cmd_selfupdate_finish, 1, 1, 1],
	  'validate'          => [\&cmd_validate,          0, 0, 0],
	  'check'             => [\&cmd_validate,          0, 0, 0],
	  'cleanup'           => [\&cmd_cleanup,           1, 1, 1],
	  'splitoffs'         => [\&cmd_splitoffs,         1, 0, 0],
	  'splits'            => [\&cmd_splitoffs,         1, 0, 0],
	  'showparent'        => [\&cmd_showparent,        1, 0, 0],
	  'dumpinfo'          => [\&cmd_dumpinfo,          1, 0, 0],
	  'show-deps'         => [\&cmd_show_deps,         1, 0, 0],
	);

END { }				# module clean-up code here (global destructor)

### constructor using configuration

sub new_with_config {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $config_object = shift;

	my $self = {};
	bless($self, $class);

	$self->{config} = $config_object;

	$self->initialize();

	return $self;
}

### self-initialization

sub initialize {
	my $self = shift;
	my $config = $self->{config};
	my ($basepath);

	$self->{basepath} = $basepath = $config->param("basepath");
	if (!$basepath) {
		die "Basepath not set in config file!\n";
	}
}

### process command

sub process {
	my $self = shift;
	my $options = shift;
	my $cmd = shift;
	my ($proc, $pkgflag, $rootflag, $aptgetflag);

	unless (defined $cmd) {
		print "NOP\n";
		return;
	}

	if (not exists $commands{$cmd}) {
		die "fink: unknown command \"$cmd\".\nType 'fink --help' for more information.\n";
	}

	($proc, $pkgflag, $rootflag, $aptgetflag) = @{$commands{$cmd}};

	# check if we need to be root
	if ($rootflag and $> != 0) {
		&restart_as_root($options, $cmd, @_);
	}

	# check if we need apt-get
	if ($aptgetflag > 0 and 
	   ($config->param_boolean("UseBinaryDist") or Fink::Config::get_option("use_binary"))) {
		my $apt_problem = 0;
		# check if we are installed at '/sw'
		if (not $basepath eq '/sw') {
				print "\n";
				&print_breaking("ERROR: You have the 'UseBinaryDist' option enabled but Fink ".
				    "is not installed under '/sw'. This is not currently allowed.");
				$apt_problem = 1;
		}
		# check if apt-get is available
		if (not $apt_problem) {
			if (&execute("$basepath/bin/apt-get 1>/dev/null 2>/dev/null", 1)) {
				&print_breaking("ERROR: You have the 'UseBinaryDist' option enabled ".
				    "but apt-get could not be run. Try to install the 'apt' Fink package ".
				    "(with e.g. 'fink install apt').");
				$apt_problem = 1;
			}
		}
		# check if 'apt-get --ignore-breakage' is implemented
		if ($aptgetflag == 2 and not $apt_problem) {
			# only for the commands that needs them
			if (&execute("$basepath/bin/apt-get --ignore-breakage 1>/dev/null 2>/dev/null", 1)) {
				&print_breaking("ERROR: You have the 'UseBinaryDist' option enabled but the ".
				   "'apt-get' tool installed on this system doesn't support it. Please ".
				   "update your Fink installation (with e.g. 'fink selfupdate').");
				$apt_problem = 1;
			}
		}
		if($apt_problem) {
			my $prompt = "Continue with the 'UseBinaryDist' option temporarely disabled?";
			my $continue = prompt_boolean($prompt, 1, 60);
			if ($continue) {
				# temporarely disable UseBinaryDist
				$config->set_param("UseBinaryDist", "false");
				Fink::Config::set_options( { 'use_binary' => 0 } );
			}
			else {
				die "Failed to execute '$cmd'!\n";
			}
		}
	}
	
	# read package descriptions if needed
	if ($pkgflag) {
		Fink::Package->require_packages();
	}
	eval { &$proc(@_); };
	if ($@) {
		print "Failed: $@";
		return $? || 1;
	}

	return 0;
}

### restart as root with command

sub restart_as_root {
	my ($method, $cmd, $arg);

	$method = $config->param_default("RootMethod", "sudo");

	$cmd = "$basepath/bin/fink";

	# Pass on options
	$cmd .= ' ' . shift;

	foreach $arg (@_) {
		if ($arg =~ /^[A-Za-z0-9_.+-]+$/) {
			$cmd .= " $arg";
		} else {
			# safety first
			$arg =~ s/[\$\`\'\"|;]/_/g;
			$cmd .= " \"$arg\"";
		}
	}

	if ($method eq "sudo") {
		$cmd = "/usr/bin/sudo $cmd";
	} elsif ($method eq "su") {
		$cmd = "/usr/bin/su root -c '$cmd'";
	} else {
		die "Fink is not configured to become root automatically.\n";
	}

	exit &execute($cmd, 1);
}

### simple commands

sub cmd_index {
	Fink::Package->update_db();
}

sub cmd_rescan {
	Fink::Package->forget_packages();
	Fink::Package->require_packages();
}

sub cmd_configure {
	require Fink::Configure;
	Fink::Configure::configure();
}

sub cmd_bootstrap {
	require Fink::Bootstrap;
	Fink::Bootstrap::bootstrap();
}

sub cmd_selfupdate {
	require Fink::SelfUpdate;
	Fink::SelfUpdate::check();
}

sub cmd_selfupdate_cvs {
	require Fink::SelfUpdate;
	Fink::SelfUpdate::check(1);
}

sub cmd_selfupdate_rsync {
	require Fink::SelfUpdate;
	Fink::SelfUpdate::check(2);
}

sub cmd_selfupdate_finish {
	require Fink::SelfUpdate;
	Fink::SelfUpdate::finish();
}

sub cmd_list {
	do_real_list("list",@_);
}

sub do_real_list {
	my ($pattern, @allnames, @selected);
	my ($pname, $package, $lversion, $vo, $iflag, $description);
	my ($formatstr, $desclen, $name, @temp_ARGV, $section, $maintainer);
	my ($buildonly, $pkgtree);
	my %options =
	(
	 "installedstate" => 0
	);
	# bits used by $options{intalledstate}
	my $ISTATE_OUTDATED = 1;
	my $ISTATE_CURRENT  = 2;
	my $ISTATE_ABSENT   = 4;
	my ($width, $namelen, $verlen, $dotab);
	my $cmd = shift;
	use Getopt::Long;
	$formatstr = "%s	%-15.15s	%-11.11s	%s\n";
	$desclen = 43;
	@temp_ARGV = @ARGV;
	@ARGV=@_;
	Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
	if ($cmd eq "list") {
		GetOptions(
				   'width|w=s'		=> \$width,
				   'tab|t'			=> \$dotab,
				   'installed|i'	=> sub {$options{installedstate} |= $ISTATE_OUTDATED | $ISTATE_CURRENT ;},
				   'uptodate|u'		=> sub {$options{installedstate} |= $ISTATE_CURRENT  ;},
				   'outdated|o'		=> sub {$options{installedstate} |= $ISTATE_OUTDATED ;},
				   'notinstalled|n'	=> sub {$options{installedstate} |= $ISTATE_ABSENT   ;},
				   'buildonly|b'	=> \$buildonly,
				   'section|s=s'	=> \$section,
				   'maintainer|m=s'	=> \$maintainer,
				   'tree|r=s'		=> \$pkgtree,
				   'help|h'			=> sub {&help_list_apropos($cmd)}
		) or die "fink list: unknown option\nType 'fink $cmd --help' for more information.\n";
	}	 else { # apropos
		GetOptions(
				   'width|w=s'		=> \$width,
				   'tab|t'			=> \$dotab,
				   'help|h'			=> sub {&help_list_apropos($cmd)}
		) or die "fink list: unknown option\nType 'fink $cmd --help' for more information.\n";
	}
	if ($options{installedstate} == 0) {
		$options{installedstate} = $ISTATE_OUTDATED | $ISTATE_CURRENT | $ISTATE_ABSENT;
	}

	# By default or if --width=auto, compute the output width to fit exactly into the terminal
	if ((not defined $width and not $dotab) or (defined $width and
				(($width eq "") or ($width eq "auto") or ($width eq "=auto") or ($width eq "=")))) {
		$width = &get_term_width();
		if (not defined $width or $width == 0) {
			$dotab = 1;				# not a terminal, fallback to tabbed mode
			undef $width;
		}
	}
	
	if (defined $width) {
		$width =~ s/[\=]?([0-9]+)/$1/;
		$width = 40 if ($width < 40);	 # enforce minimum display width of 40 characters
		$width = $width - 5;			 # 5 chars for the first field
		$namelen = int($width * 0.2);	 # 20% for the name
		$verlen = int($width * 0.15);	 # 15% for the version
		if ($desclen != 0) {
			$desclen = $width - $namelen - $verlen - 5;
		}
		$formatstr = "%s  %-" . $namelen . "." . $namelen . "s  %-" . $verlen . "." . $verlen . "s  %s\n";
	} elsif ($dotab) {
		$formatstr = "%s\t%s\t%s\t%s\n";
		$desclen = 0;
	}
	Fink::Package->require_packages();
	@_ = @ARGV;
	@ARGV = @temp_ARGV;
	@allnames = Fink::Package->list_packages();
	if ($cmd eq "list") {
		if ($#_ < 0) {
			@selected = @allnames;
		} else {
			@selected = ();
			while (defined($pattern = shift)) {
				$pattern = lc quotemeta $pattern; # fixes bug about ++ etc in search string.
				if ((grep /\\\*/, $pattern) or (grep /\\\?/, $pattern)) {
					 $pattern =~ s/\\\*/.*/g;
					 $pattern =~ s/\\\?/./g;
					 push @selected, grep(/^$pattern$/, @allnames);
				} else {
					 push @selected, grep(/$pattern/, @allnames);
				}
			}
		}
	} else {
		$pattern = shift;
		@selected = @allnames;
		unless ($pattern) {
			die "no keyword specified for command 'apropos'!\n";
		}
	}

	foreach $pname (sort @selected) {
		$package = Fink::Package->package_by_name($pname);
		if ($package->is_virtual() == 1) {
			$lversion = "";
			$iflag = "   ";
			$description = "[virtual package]";
			next if ($cmd eq "apropos"); 
			next unless ($options{installedstate} & $ISTATE_ABSENT);
			next if (defined $buildonly);
			next if (defined $section);
			next if (defined $maintainer);
			next if (defined $pkgtree);
		} else {
			$lversion = &latest_version($package->list_versions());
			$vo = $package->get_version($lversion);
			if ($vo->is_installed()) {
				next unless ($options{installedstate} & $ISTATE_CURRENT);
				$iflag = " i ";
			} elsif ($package->is_any_installed()) {
				$iflag = "(i)";
				next unless ($options{installedstate} & $ISTATE_OUTDATED);
			} else {
				$iflag = "   ";
				next unless ($options{installedstate} & $ISTATE_ABSENT);
			}

			$description = $vo->get_shortdescription($desclen);
		}
		if (defined $buildonly) {
			next unless $vo->param_boolean("builddependsonly");
		}
		if (defined $section) {
			$section =~ s/[\=]?(.*)/$1/;
			next unless $vo->get_section($vo) =~ /\Q$section\E/i;
		}
		if (defined $maintainer) {
			next unless ( $vo->has_param("maintainer") && $vo->param("maintainer")  =~ /\Q$maintainer\E/i );
		}
		if (defined $pkgtree) {
#			$pkgtree =~ s/[\=]?(.*)/$1/;    # not sure if needed...
			next unless $vo->get_tree($vo) =~ /\b\Q$pkgtree\E\b/i;
		}
		if ($cmd eq "apropos") {
			next unless ( $vo->has_param("Description") && $vo->param("Description") =~ /\Q$pattern\E/i ) || $vo->get_name() =~ /\Q$pattern\E/i;  
		}
		if ($namelen && length($pname) > $namelen) {
			$pname = substr($pname, 0, $namelen - 3)."...";
		}

		printf $formatstr,
				$iflag, $pname, $lversion, $description;
	}
}

sub help_list_apropos {
	my $cmd = shift;
	require Fink::FinkVersion;
	my $version = Fink::FinkVersion::fink_version();

	if ($cmd eq "list") {
		print <<"EOF";
Fink $version

Usage: fink list [options] [string]

Options:
  -w xyz, --width=xyz  - Sets the width of the display you would like the output
                         formatted for. xyz is either a numeric value or auto.
                         auto will set the width based on the terminal width.
  -t, --tab            - Outputs the list with tabs as field delimiter.
  -i, --installed      - Only list packages which are currently installed.
  -u, --uptodate       - Only list packages which are up to date.
  -o, --outdated       - Only list packages for which a newer version is
                         available.
  -n, --notinstalled   - Only list packages which are not installed.
  -b, --buildonly      - Only list packages which are Build Only Depends
  -s expr,             - Only list packages in the section(s) matching expr
    --section=expr       (example: fink list --section=x11).
  -m expr,             - Only list packages with the maintainer(s) matching expr
    --maintainer=expr    (example: fink list --maintainer=beren12).
  -r expr,             - Only list packages with the tree matching expr
    --tree=expr          (example: fink list --tree=stable).
  -h, --help           - This help text.

EOF
	} else { # apropos
		print <<"EOF";
Fink $version

Usage: fink apropos [options] [string]

Options:
  -w xyz, --width=xyz  - Sets the width of the display you would like the output
                         formatted for. xyz is either a numeric value or auto.
                         auto will set the width based on the terminal width.
  -t, --tab            - Outputs the list with tabs as field delimiter.
  -h, --help           - This help text.

EOF
	}
	exit 0;
}

sub cmd_listpackages {
	my ($pname, $package);

	foreach $pname (Fink::Package->list_packages()) {
		print "$pname\n";
		$package = Fink::Package->package_by_name($pname);
		if ($package->is_any_installed()) {
			print "YES\n";
		} else {
			print "NO\n";
		}
	}
}

sub cmd_scanpackages {
	my @treelist = @_;
	my ($tree, $treedir, $cmd, $archive, $component);

	# do all trees by default
	if ($#treelist < 0) {
		@treelist = $config->get_treelist();
	}

	# create a global override file

	my ($pkgname, $package, $pkgversion, $prio, $section);
	open(OVERRIDE,">$basepath/fink/override") or die "can't write override file: $!\n";
	foreach $pkgname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pkgname);
		next unless defined $package;
		$pkgversion = $package->get_version(&latest_version($package->list_versions()));
		next unless defined $pkgversion;

		$section = $pkgversion->get_section();
		if ($section eq "bootstrap") {
			$section = "base";
		}

		$prio = "optional";
		if ($pkgname eq "apt" or $pkgname eq "apt-shlibs" or $pkgname eq "storable-pm") {
			$prio = "important";
		}
		if ($pkgversion->param_boolean("Essential")) {
			$prio = "required";
		}
		print OVERRIDE "$pkgname $prio $section\n";
	}
	close(OVERRIDE) or die "can't write override file: $!\n";

	# create the Packages.gz and Release files for each tree

	chdir "$basepath/fink";
	foreach $tree (@treelist) {
		$treedir = "dists/$tree/binary-$debarch";
		if ($tree =~ /^([^\/]+)\/(.+)$/) {
			$archive = $1;
			$component = $2;
		} else {
			$archive = $tree;
			$component = "main";
		}

		if (! -d $treedir) {
			mkdir_p $treedir or
				die "can't create directory $treedir\n";
		}

		$cmd = "dpkg-scanpackages $treedir override | gzip >$treedir/Packages.gz";
		if (&execute($cmd)) {
			unlink("$treedir/Packages.gz");
			die "package scan failed in $treedir\n";
		}

		open(RELEASE,">$treedir/Release") or die "can't write Release file: $!\n";
		print RELEASE <<EOF;
Archive: $archive
Component: $component
Origin: Fink
Label: Fink
Architecture: $debarch
EOF
		close(RELEASE) or die "can't write Release file: $!\n";
	}
}

### package-related commands

sub cmd_fetch {
	my ($package, @plist);

	@plist = &expand_packages(@_);
	if ($#plist < 0) {
		die "no package specified for command 'fetch'!\n";
	}

	foreach $package (@plist) {
		$package->phase_fetch(0, 0);
	}
}

sub cmd_description {
	my ($package, @plist);

	@plist = &expand_packages(@_);
	if ($#plist < 0) {
		die "no package specified for command 'description'!\n";
	}

	print "\n";
	foreach $package (@plist) {
		print $package->get_fullname().": ";
		print $package->get_description();
		print "\n";
	}
}

sub cmd_apropos {
	do_real_list("apropos", @_);	
}

sub parse_fetch_options {
	my $cmd = shift;
	my %options =
	  (
	   "norestrictive" => 0,
	   "dryrun" => 0,
	   "wanthelp" => 0,
	   );

	my @temp_ARGV = @ARGV;
	@ARGV=@_;
	Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
	GetOptions('ignore-restrictive|i'	=> sub {$options{norestrictive} = 1 } , 
			   'dry-run|d'				=> sub {$options{dryrun} = 1 } , 
			   'help|h'					=> sub {$options{wanthelp} = 1 })
		or die "fink fetch: unknown option\nType 'fink $cmd --help' for more information.\n";
	if ($options{wanthelp} == 1) {
		require Fink::FinkVersion;
		my $finkversion = Fink::FinkVersion::fink_version();
		print <<"EOF";
Fink $finkversion

Usage: fink $cmd [options]

Options:
  -i, --ignore-restrictive  - Do not fetch sources for packages with 
                            a "Restrictive" license. Useful for mirroring.
  -d, --dry-run             - Prints filename, MD5, list of source URLs, Maintainer for each package
  -h, --help                - This help text.

EOF
		exit 0;
	}
	@_ = @ARGV;
	@ARGV = @temp_ARGV;

	return %options;
}

#This sub is currently only used for bootstrap. No command line parsing needed
sub cmd_fetch_missing {
	my ($package, $options, @plist);

	@plist = &expand_packages(@_);
	if ($#plist < 0) {
		die "no package specified for command 'fetch'!\n";
	}
	foreach $package (@plist) {
		$package->phase_fetch(1, 0);
	}
}

sub cmd_fetch_all {
	my ($pname, $package, $version, $vo);
	
	my (%options, $norestrictive, $dryrun);
	%options = &parse_fetch_options("fetch-all", @_);
	$norestrictive = $options{"norestrictive"} || 0;
	$dryrun = $options{"dryrun"} || 0;
	
	foreach $pname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pname);
		$version = &latest_version($package->list_versions());
		$vo = $package->get_version($version);
		if (defined $vo) {
			if ($norestrictive && $vo->has_param("license")) {
					if($vo->param("license") =~ m/Restrictive\s*$/i) {
						print "Ignoring $pname due to License: Restrictive\n";
						next;
				}
			}
			eval {
				$vo->phase_fetch(0, $dryrun);
			};
			warn "$@" if $@;				 # turn fatal exceptions into warnings
		}
	}
}

sub cmd_fetch_all_missing {
	my ($pname, $package, $version, $vo);
	my (%options, $norestrictive, $dryrun);

	%options = &parse_fetch_options("fetch-missing", @_);
	$norestrictive = $options{"norestrictive"} || 0;
	$dryrun = $options{"dryrun"} || 0;

	foreach $pname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pname);
		$version = &latest_version($package->list_versions());
		$vo = $package->get_version($version);
		if (defined $vo) {
			if ($norestrictive) {
				if ($vo->has_param("license")) {
						if($vo->param("license") =~ m/Restrictive\s*$/i) {
							print "Ignoring $pname due to License: Restrictive\n";
							next;
					}
				}
			}
			eval {
				$vo->phase_fetch(1, $dryrun);
			};
			warn "$@" if $@;				 # turn fatal exceptions into warnings
		}
	}	
}

sub cmd_remove {
	my @packages = get_pkglist("remove", @_);

	Fink::PkgVersion::phase_deactivate(@packages);
	Fink::Status->invalidate();
}

sub get_pkglist {
	my $cmd = shift;
	my ($package, @plist, $pname, @selected, $pattern, @packages);
	my ($buildonly, $wanthelp, $po);

	use Getopt::Long;
	my @temp_ARGV = @ARGV;
	@ARGV=@_;
	Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
	GetOptions(
		'buildonly|b'	=> \$buildonly,
		'help|h'	=> \$wanthelp
	) or die "fink $cmd: unknown option\nType 'fink $cmd --help' for more information.\n";

	if ($wanthelp) {
		require Fink::FinkVersion;
		my $version = Fink::FinkVersion::fink_version();

		print <<"EOF";
Fink $version

Usage: fink $cmd [options] [string]

Options:
  -b, --buildonly      - Only packages which are Build Depends Only
  -h, --help           - This help text.

EOF
		exit 0;
	}

	Fink::Package->require_packages();
	@_ = @ARGV;
	@ARGV = @temp_ARGV;
	@plist = Fink::Package->list_packages();
	if ($#_ < 0) {
		if (defined $buildonly) {
			@selected = @plist;
		} else {
			die "no package specified for command '$cmd'!\n";
		}
	} else {
		@selected = ();
		while (defined($pattern = shift)) {
			$pattern = lc quotemeta $pattern; # fixes bug about ++ etc in search string.
			push @selected, grep(/^$pattern$/, @plist);
		}
	}

	if ($#selected < 0 ) {
		die "no package specified for command '$cmd'!\n";
	}

	foreach $pname (sort @selected) {
		$package = Fink::Package->package_by_name($pname);

		# Can't purge or remove virtuals
		next if $package->is_virtual();

		# Can only remove/purge installed pkgs
		unless ( $package->is_any_installed($package->list_installed_versions()) ) {
			print "WARNING: $pname is not installed, skipping.\n";
			next;
		}

		# shouldn't be able to remove or purge essential pkgs
		$po = Fink::PkgVersion->match_package($pname);
		if ( $po->param_boolean("essential") ) {
			print "WARNING: $pname is essential, skipping.\n";
			next;
		}

		if (defined $buildonly) {
			next unless ( $po->param_boolean("builddependsonly") );
		}

		push @packages, $package->get_name();
	}

	# In case no packages meet the requirements above.
	if ($#packages < 0) {
		print "Nothing ".$cmd."d\n";
		exit(0);
	}

	my $cmp1 = join(" ", $cmd, @packages);
	my $cmp2 = join(" ", @ARGV);

	if ($cmp1 ne $cmp2) {
		my $pkglist = join(", ", @packages);
		my $rmcount = $#packages + 1;
		print "Fink will attempt to $cmd $rmcount package(s).\n";
		&print_breaking("$pkglist\n\n");

		my $answer = &prompt_boolean("Do you want to continue?", 1);
		if (! $answer) {
			die "$cmd not performed!\n";
		}
	}

	return @packages;
}

sub cmd_purge {
	my @packages = get_pkglist("purge", @_);

	print "WARNING: this command will remove the package(s) and remove any\n";
	print "         global configure files, even if you modified them!\n\n";
 
	my $answer = &prompt_boolean("Do you want to continue?", 1);			
	if (! $answer) {
		die "Purge not performed!\n";
	} else {
		Fink::PkgVersion::phase_purge(@packages);
		Fink::Status->invalidate();
	}
}

sub cmd_validate {
	my ($filename, @flist);

	my ($wanthelp, $val_prefix);
	use Getopt::Long;
	my @temp_ARGV = @ARGV;
	@ARGV=@_;
	Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
	GetOptions(
		'prefix|p=s' => \$val_prefix,
		'help|h'     => \$wanthelp
	) or die "fink validate: unknown option\nType 'fink validate --help' for more information.\n";

	if ($wanthelp) {
		require Fink::FinkVersion;
		my $version = Fink::FinkVersion::fink_version();

		print <<"EOF";
Fink $version

Usage: fink validate [options] [package(s)]

Options:
  -p, --prefix    - Simulate an alternate Fink prefix (\%p) in files.
  -h, --help      - This help text.

EOF
		exit 0;
	}
	@_ = @ARGV;
	@ARGV = @temp_ARGV;

	require Fink::Validation;

	@flist = @_;
	if ($#flist < 0) {
		die "fink validate: no input file specified\nType 'fink validate --help' for more information.\n";
	}
	
	foreach $filename (@flist) {
		if ($filename =~/\.info$/) {
			Fink::Validation::validate_info_file($filename, $val_prefix);
		} elsif ($filename =~/\.deb$/) {
			Fink::Validation::validate_dpkg_file($filename, $val_prefix);
		} else {
			die "Don't know how to validate $filename!\n";
		}
	}
}

sub cmd_cleanup {
	my ($pname, $package, $vo, $file, $suffix);
	my (@old_src_files);

	# TODO - add option that specify whether to clean up source, .debs, or both
	# TODO - add --dry-run option that prints out what actions would be performed
	# TODO - option that steers which file to keep/delete: keep all files that
	#				 are refered by any .info file; keep only those refered to by the
	#				 current version of any package; etc.
	#				 Delete all .deb and delete all src? Not really needed, this can be
	#				 achieved each with single line CLI commands.
	# TODO - document --keep-src in the man page, and add a fink.conf entry for defaults

	my ($wanthelp, $keep_old);
	# dryrun is not yet used. Provided here as a starter for the --dry-run option.
	my $dryrun = 0;
	
	use Getopt::Long;
	my @temp_ARGV = @ARGV;
	@ARGV=@_;
	Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
	GetOptions(
		'keep-src|k' => \$keep_old,
		'help|h'     => \$wanthelp
	) or die "fink cleanup: unknown option\nType 'fink cleanup --help' for more information.\n";

	if ($wanthelp) {
		require Fink::FinkVersion;
		my $version = Fink::FinkVersion::fink_version();

		print <<"EOF";
Fink $version

Usage: fink cleanup [options]

Options:
  -k, --keep-src  - Move old source files to $basepath/src/old/.
  -h, --help      - This help text.

EOF
		exit 0;
	}
	@_ = @ARGV;
	@ARGV = @temp_ARGV;

	# Reset list of non-obsolete debs/source files
	my %deb_list = ();
	my %src_list = ();
	
	# Initialize file counter
	my %file_count = (
		'deb' => 0,
		'symlink' => 0,
		'src' => 0,
	);
	
	# Anonymous subroutine to find/nuke obsolete debs
	my $kill_obsolete_debs = sub {
		if (/^.*\.deb\z/s ) {
			if (not $deb_list{$File::Find::name}) {
				# Obsolete deb
				unlink $File::Find::name and $file_count{'deb'}++;
			}
		}
	};
	
	# Anonymous subroutine to find/nuke broken deb symlinks
	my $kill_broken_links = sub {
		if(-l && !-e) {
			# Broken link
			unlink $File::Find::name and $file_count{'symlink'}++;
		}
	};

	# Iterate over all packages and collect the deb files, as well
	# as all their source files.
	foreach $pname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pname);
		foreach $vo ($package->get_all_versions()) {
			# Skip dummy packages
			next if $vo->is_type('dummy');

			# deb file 
			$file = $vo->get_debfile();
			$deb_list{$file} = 1;

			# all source files
			foreach $suffix ( $vo->get_source_suffices() ) {
				$file = $vo->find_tarball($suffix);
				$src_list{$file} = 1 if defined($file);
			}
		}
	}
	
	# Now search through all .deb files in /sw/fink/dists/
	find ({'wanted' => $kill_obsolete_debs, 'follow' => 1}, "$basepath/fink/dists");
	
	# Remove broken symlinks in /sw/fink/debs (i.e. those that pointed to 
	# the .deb files we deleted above).
	find ($kill_broken_links, "$basepath/fink/debs");
	

	# Remove obsolete source files. We do not delete immediatly because that
	# will confuse readdir().
	@old_src_files = ();
	opendir(DIR, "$basepath/src") or die "Can't access $basepath/src: $!";
	while (defined($file = readdir(DIR))) {
		# $file = "$basepath/src/$file";
		# Skip all source files that are still used by some package
		next if $src_list{"$basepath/src/$file"};
		push @old_src_files, $file;
	}
	closedir(DIR);

	if ($keep_old) {
		unless (-d "$basepath/src/old") {
		mkdir("$basepath/src/old") or die "Can't create $basepath/src/old: $!";
		}
	}

	foreach $file (@old_src_files) {
		# For now, do *not* remove directories - this could easily kill
		# a build running in another process. In the future, we might want
		# to add a --dirs switch that will also delete directories.
		if (-f "$basepath/src/$file") {
		print("$file\n");
		if ($keep_old) {
				rename("$basepath/src/$file", "$basepath/src/old/$file") and $file_count{'src'}++;
			} else {
				unlink "$basepath/src/$file" and $file_count{'src'}++;
			}
		}
	}

	if ($config->param_boolean("UseBinaryDist") or Fink::Config::get_option("use_binary")) {
		# Delete obsolete .deb files in $basepath/var/cache/apt/archives using 
		# 'apt-get autoclean'
		my $aptcmd = "$basepath/bin/apt-get ";
		if (Fink::Config::verbosity_level() == 0) {
			$aptcmd .= "-qq ";
		}
		elsif (Fink::Config::verbosity_level() < 2) {
			$aptcmd .= "-q ";
		}
		if($dryrun) {
			$aptcmd .= "--dry-run ";
		}
		my $apt_cache_path = "$basepath/var/cache/apt/archives";
		my $deb_regexp = "\\.deb\$";
		my $files_before_clean = &count_files($apt_cache_path, $deb_regexp);

		if (&execute($aptcmd . "--option APT::Clean-Installed=false autoclean")) {
			print("WARNING: Cleaning deb packages in '$apt_cache_path' failed.\n");
		}
		my $files_deleted = $files_before_clean - &count_files($apt_cache_path, $deb_regexp);

		# Running scanpackages and updating apt-get db
		print "Updating the list of locally available binary packages.\n";
		&cmd_scanpackages;
		print "Updating the indexes of available binary packages.\n";
		if (&execute($aptcmd . "update")) {
			print("WARNING: Failure while updating indexes.\n");
		}

		print 'Obsolete deb packages deleted from apt cache: ' . $files_deleted . "\n";
	}

	print 'Obsolete deb packages deleted from fink trees: ' . $file_count{'deb'} . "\n";
	print 'Obsolete symlinks deleted: ' . $file_count{'symlink'} . "\n";
	if ($keep_old) {
		print 'Obsolete sources moved: ' . $file_count{'src'} . "\n\n";
	}
	else {
		print 'Obsolete sources deleted: ' . $file_count{'src'} . "\n\n";
	}
}

### building and installing

my ($OP_BUILD, $OP_INSTALL, $OP_REBUILD, $OP_REINSTALL) =
	(0, 1, 2, 3);

sub cmd_build {
	&real_install($OP_BUILD, 0, 0, @_);
}

sub cmd_rebuild {
	&real_install($OP_REBUILD, 0, 0, @_);
}

sub cmd_install {
	&real_install($OP_INSTALL, 0, 0, @_);
}

sub cmd_reinstall {
	&real_install($OP_REINSTALL, 0, 0, @_);
}

sub cmd_update_all {
	my (@plist, $pname, $package);

	foreach $pname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pname);
		if ($package->is_any_installed()) {
			push @plist, $pname;
		}
	}

	&real_install($OP_INSTALL, 1, 0, @plist);
}

use constant PKGNAME => 0;
use constant PKGOBJ  => 1;  # $item->[1] unused?
use constant PKGVER  => 2;
use constant OP      => 3;
use constant FLAG    => 4;

sub real_install {
	my $op = shift;
	my $showlist = shift;
	my $forceoff = shift; # check if this is a secondary loop
	my ($pkgspec, $package, $pkgname, $pkgobj, $item, $dep, $con, $cn);
	my ($all_installed, $any_installed, @conlist, @removals, %cons, $cname);
	my (%deps, @queue, @deplist, @vlist, @requested, @additionals, @elist);
	my (%candidates, @candidates, $pnode, $found);
	my ($oversion, $opackage, $v, $ep, $dp, $dname);
	my ($answer, $s);
	my (%to_be_rebuilt, %already_activated);

	if (Fink::Config::verbosity_level() > -1) {
		$showlist = 1;
	}

	%deps = ();		# hash by package name
	%cons = ();		# hash by package name

	%to_be_rebuilt = ();
	%already_activated = ();

	# should we try to download the deb from the binary distro?
	# warn if UseBinaryDist is enabled and not installed in '/sw'
	my $deb_from_binary_dist = 0;
	if ($config->param_boolean("UseBinaryDist") or Fink::Config::get_option("use_binary")) {
		if ($basepath eq '/sw') {
			$deb_from_binary_dist = 1;
		}
		else {
				print "\n";
				&print_breaking("WARNING: Downloading packages from the binary distribution ".
				                "is currently only possible if Fink is installed at '/sw'!.");
		}
	}
		
	# add requested packages
	foreach $pkgspec (@_) {
		# resolve package name
		#	 (automatically gets the newest version)
		$package = Fink::PkgVersion->match_package($pkgspec);
		unless (defined $package) {
			die "no package found for specification '$pkgspec'!\n";
		}
		# no duplicates here
		#	 (dependencies is different, but those are checked later)
		$pkgname = $package->get_name();
		if (exists $deps{$pkgname}) {
			print "Duplicate request for package '$pkgname' ignored.\n";
			next;
		}
		$pkgobj = Fink::Package->package_by_name($pkgname);
		# skip if this version/revision is installed
		#	 (also applies to update)
		if ($op != $OP_REBUILD and $op != $OP_REINSTALL
				and $package->is_installed()) {
			next;
		}
		# for build, also skip if present, but not installed
		if ($op == $OP_BUILD and $package->is_present()) {
			next;
		}
		# add to table
		$deps{$pkgname} = [ $pkgname, $pkgobj, $package, $op, 1 ];
		$to_be_rebuilt{$pkgname} = ($op == $OP_REBUILD);
	}

	@queue = keys %deps;
	if ($#queue < 0) {
		unless ($forceoff) {
			print "No packages to install.\n";
		}
		return;
	}

	# resolve dependencies for essential packages
	@elist = Fink::Package->list_essential_packages();
	foreach $ep (@elist) {
		# no virtual packages here
		$ep = [ Fink::Package->package_by_name($ep)->get_all_versions() ];
	}

	# recursively expand dependencies
	while ($#queue >= 0) {
		$pkgname = shift @queue;
		$item = $deps{$pkgname};

		# check installation state
		if ($item->[PKGVER]->is_installed() and $item->[OP] != $OP_REBUILD) {
			if ($item->[FLAG] == 0) {
				$item->[FLAG] = 2;
			}
			# already installed, don't think about it any more
			next;
		}

		# get list of dependencies
		if ($item->[OP] == $OP_BUILD or
				($item->[OP] == $OP_REBUILD and not $item->[PKGVER]->is_installed())) {
			# We are building an item without going to install it
			# -> only include pure build-time dependencies
			if (Fink::Config::verbosity_level() > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' will be built without being installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(2, "Depends", $forceoff);
			@conlist = $item->[PKGVER]->resolve_depends(2, "Conflicts", $forceoff);
		} elsif ((not $item->[PKGVER]->is_present() 
		  and not ($deb_from_binary_dist and $item->[PKGVER]->is_aptgetable()))
		  or $item->[OP] == $OP_REBUILD) {
			# We want to install this package and have to build it for that
			# -> include both life-time & build-time dependencies
			if (Fink::Config::verbosity_level() > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' will be built and installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(1, "Depends", $forceoff);
		} elsif (not $item->[PKGVER]->is_present() and $item->[OP] != $OP_REBUILD 
		         and $deb_from_binary_dist and $item->[PKGVER]->is_aptgetable()) {
			# We want to install this package and will download the .deb for it
			# -> only include life-time dependencies
			if (Fink::Config::verbosity_level() > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' will be downloaded as a binary package and installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(0, "Depends", $forceoff);
			
			# Do not use BuildConflicts for packages which are not going to be built!
#			@conlist = $item->[PKGVER]->resolve_depends(0, "Conflicts", $forceoff);
		} else {
			# We want to install this package and already have a .deb for it
			# -> only include life-time dependencies
			if (Fink::Config::verbosity_level() > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' will be installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(0, "Depends", $forceoff);
			
			# Do not use BuildConflicts for packages which are not going to be built!
#			@conlist = $item->[PKGVER]->resolve_depends(0, "Conflicts", $forceoff);
		}
		# add essential packages (being careful about packages whose parent is essential)
		if (not $item->[PKGVER]->param_boolean("Essential") and not $item->[PKGVER]->param_boolean("_ParentEssential")) {
			push @deplist, @elist;
		}
	DEPLOOP: foreach $dep (@deplist) {
			next if $#$dep < 0;		# skip empty lists

			# check the graph
			foreach $dp (@$dep) {
				$dname = $dp->get_name();
				if (exists $deps{$dname} and $deps{$dname}->[PKGVER] == $dp) {
					if ($deps{$dname}->[OP] < $OP_INSTALL) {
						$deps{$dname}->[OP] = $OP_INSTALL;
					}
					# add a link
					push @$item, $deps{$dname};
					next DEPLOOP;
				}
			}

			# check for installed pkgs (exact revision)
			foreach $dp (@$dep) {
				if ($dp->is_installed()) {
					$dname = $dp->get_name();
					if (exists $deps{$dname}) {
						die "Internal error: node for $dname already exists\n";
					}
					# add node to graph
					$deps{$dname} = [ $dname, Fink::Package->package_by_name($dname),
					                  $dp, $OP_INSTALL, 2 ];
					# add a link
					push @$item, $deps{$dname};
					# add to investigation queue
					push @queue, $dname;
					next DEPLOOP;
				}
			}

			# make list of package names (preserve order)
			%candidates = ();
			@candidates = ();
			foreach $dp (@$dep) {
				next if exists $candidates{$dp->get_name()};
				$candidates{$dp->get_name()} = 1;
				push @candidates, $dp->get_name();
			}

			# At this point, we are trying to fulfill a dependency. In the loop
			# above, we determined all potential candidates, i.e. packages which
			# would fulfill the dep. Now we have to decide which to use.

			$found = 0;		# Set to true once we decided which candidate to support.


			# Trivial case: only one candidate, nothing to be done, just use it.
			if ($#candidates == 0) {
				$dname = $candidates[0];
				$found = 1;
			}

			# Next, we check if by chance one of the candidates is already
			# installed. If so, that is the natural choice to fulfill the dep.
			if (not $found) {
				my $cand;
				foreach $cand (@candidates) {
					$pnode = Fink::Package->package_by_name($cand);
					if ($pnode->is_any_installed()) {
						$dname = $cand;
						$found = 1;
						last;
					}
				}
			}

			# Next, check if a relative of a candidate has already been marked
			# for installation (or is itself a dependency). If so, we use that
			# candidate to fulfill the dep.
			# This is a heuristic, but usually does exactly "the right thing".
			if (not $found) {
				my ($cand, $splitoff);
				my $candcount=0;
				SIBCHECK: foreach $cand (@candidates) {
					my $package = Fink::Package->package_by_name($cand);
					my $lversion = &latest_version($package->list_versions());
					my $vo = $package->get_version($lversion);
					
					if (exists $vo->{_relatives}) {
						foreach $splitoff (@{$vo->{_relatives}}) {
							# if the package is being installed, or is already installed,
							# auto-choose it
							if (exists $deps{$splitoff->get_name()} or $splitoff->is_installed()) {
								$dname = $cand;
								$candcount++;
							}
						}
					}
				}
				if ($candcount == 1) {
				    $found=1;
				}
			}

			# No decision has been made so far. Now see if the user has set a
			# regexp to match in fink.conf.
			if (not $found) {
				my $matchstr = $config->param("MatchPackageRegEx");
				my (@matched, @notmatched);
				if (defined $matchstr) {
					foreach $dname (@candidates) {
						if ( $dname =~ $matchstr ) {
							push(@matched, $dname);
						} else {
							push(@notmatched, $dname);
						}
					}
					if (1 == @matched) {
						# we have exactly one match, use it
						$dname = pop(@matched);
						$found = 1;
					} elsif (@matched > 1) {
						# we have multiple matches
						# reorder list so that matched ones are at the top
						@candidates = (@matched, @notmatched);
					}
				}
			}

			# None of our heuristics managed to narrow down the list to a
			# single choice. So as a last resort, ask the use!
			if (not $found) {
				my @choices = ();
				my $pkgindex = 1;
				my $choice = 1;
				my $founddebcnt = 0;
				foreach $dname (@candidates) {
					my $package = Fink::Package->package_by_name($dname);
					my $lversion = &latest_version($package->list_versions());
					my $vo = $package->get_version($lversion);
					my $description = $vo->get_shortdescription(60);
					push @choices, ( "$dname: $description" => $dname );
					if ($package->is_any_present()) {
						$choice = $pkgindex;
						$founddebcnt++;
				   }
				   $pkgindex++;
				}
				if ($founddebcnt > 1) {
				   $choice = 1; # Do not select anything if more than one choice is available
				}
				print "\n";
				&print_breaking("fink needs help picking an alternative to satisfy ".
								"a virtual dependency. The candidates:");
				$dname = &prompt_selection_new("Pick one:", [number=>$choice], @choices);
			}

			# the dice are rolled...

			$pnode = Fink::Package->package_by_name($dname);
			@vlist = ();
			foreach $dp (@$dep) {
				if ($dp->get_name() eq $dname) {
					push @vlist, $dp->get_fullversion();
				}
			}

			if (exists $deps{$dname}) {
				# node exists, we need to generate the version list
				# based on multiple packages
				@vlist = ();

				# first, get the current list of acceptable packages
				# this will run get_matching_versions over every version spec
				# for this package
				my $package = Fink::Package->package_by_name($dname);
				my @existing_matches;
				for my $spec (@{$package->{_versionspecs}}) {
					push(@existing_matches, $package->get_matching_versions($spec, @existing_matches));
					if (@existing_matches == 0) {
						print "unable to resolve version conflict on multiple dependencies\n";
						for my $spec (@{$package->{_versionspecs}}) {
							print "	 $dname $spec\n";
						}
						exit 1;
					}
				}

				for (@existing_matches) {
					push(@vlist, $_->get_fullversion());
				}

				unless (@vlist > 0) {
					print "unable to resolve version conflict on multiple dependencies\n";
					for my $spec (@{$package->{_versionspecs}}) {
						print "	 $dname $spec\n";
					}
					exit 1;
				}
			}

			# add node to graph
			$deps{$dname} = [ $dname, $pnode,
			                  $pnode->get_version(&latest_version(@vlist)),
			                  $OP_INSTALL, 0 ];
			# add a link
			push @$item, $deps{$dname};
			# add to investigation queue
			push @queue, $dname;
		}
	}

	CONLOOP: foreach $con (@conlist) {
		next if $#$con < 0;			# skip empty lists

		# check for installed pkgs (exact revision)
		foreach $cn (@$con) {
			if ($cn->is_installed()) {
				$cname = $cn->get_name();
				if (exists $cons{$cname}) {
					die "Internal error: node for $cname already exists\n";
				}
				# add node to graph
				$cons{$cname} = [ $cname, Fink::Package->package_by_name($cname),
				                  $cn, $OP_INSTALL, 2 ];
				next CONLOOP;
			}
		}
	}


	# generate summary
	@requested = ();
	@additionals = ();
	@removals = ();
	my $willbuild = 0;
	foreach $pkgname (sort keys %deps) {
		$item = $deps{$pkgname};
		if ($item->[FLAG] == 0) {
			push @additionals, $pkgname;
		} elsif ($item->[FLAG] == 1) {
			push @requested, $pkgname;
		}
		if ($item->[OP] == $OP_REBUILD or not $item->[PKGVER]->is_present()) {
			$willbuild = 1 unless ($item->[OP] == $OP_INSTALL and $item->[PKGVER]->is_installed());
		}
	}

	foreach $pkgname (sort keys %cons) {
		push @removals, $pkgname;
	}
			

	if ($willbuild) {
		if (Fink::PkgVersion->match_package("broken-gcc")->is_installed()) { 
			&print_breaking("\nWARNING: You are using a version of gcc which is known to produce incorrect output from C++ code under certain circumstances.\n\nFor information about upgrading, see the Fink web site.\n\n");
			sleep 10;
		}
	}

	# display list of requested packages
	if ($showlist && not $forceoff) {
		$s = "The following ";
		if ($#requested > 0) {
			$s .= scalar(@requested)." packages";
		} else {
			$s .= "package";
		}
		$s .= " will be ";
		if ($op == $OP_INSTALL) {
			$s .= "installed or updated";
		} elsif ($op == $OP_BUILD) {
			$s .= "built";
		} elsif ($op == $OP_REBUILD) {
			$s .= "rebuilt";
		} elsif ($op == $OP_REINSTALL) {
			$s .= "reinstalled";
		}
		$s .= ":";
		&print_breaking($s);
		&print_breaking(join(" ",@requested), 1, " ");
	}
	unless ($forceoff) {
		# ask user when additional packages are to be installed
		if ($#additionals >= 0 || $#removals >= 0) {
			if ($#additionals >= 0) {
				if ($#additionals > 0) {
					&print_breaking("The following ".scalar(@additionals).
							" additional packages will be installed:");
				} else {
					&print_breaking("The following additional package ".
							"will be installed:");
				}
				&print_breaking(join(" ",@additionals), 1, " ");
			}
			if ($#removals >= 0) {
				if ($#removals > 0) {
					&print_breaking("The following ".scalar(@removals).
							" packages will be removed:");
				} else {
					&print_breaking("The following package ".
							"will be removed:");
				}
				&print_breaking(join(" ",@removals), 1, " ");
			}
			$answer = &prompt_boolean("Do you want to continue?", 1);
			if (! $answer) {
				die "Package requirements not satisfied\n";
			}
		}
	}

	# remove buildconfilcts before new builds reinstall after build
	Fink::Engine::cmd_remove("remove", @removals) if (scalar(@removals) > 0);

	# fetch all packages that need fetching
	foreach $pkgname (sort keys %deps) {
		$item = $deps{$pkgname};
		next if $item->[OP] == $OP_INSTALL and $item->[PKGVER]->is_installed();
		if (not $item->[PKGVER]->is_present() and $item->[OP] != $OP_REBUILD 
		    and $deb_from_binary_dist and $item->[PKGVER]->is_aptgetable()) {
			# download the deb
			$item->[PKGVER]->phase_fetch_deb(1, 0);
		}

		if ($item->[OP] == $OP_REBUILD or not $item->[PKGVER]->is_present()) {
			$item->[PKGVER]->phase_fetch(1, 0);
		}
	}

	# install in correct order...
	while (1) {
		$all_installed = 1;
		$any_installed = 0;
	PACKAGELOOP: foreach $pkgname (sort keys %deps) {
			$item = $deps{$pkgname};
			next if (($item->[FLAG] & 2) == 2);	 # already installed
			$all_installed = 0;

			$package = $item->[PKGVER];
			my $pkg;

			# concatenate dependencies of package and its relatives
			my ($dpp, $pkgg, $isgood);
			my ($dppname,$pkggname,$tmpname);
			my @extendeddeps = ();
			foreach $dpp (@{$item}[5..$#{$item}]) {
				$isgood = 1;
				$dppname = $dpp->[PKGNAME];
				if (exists $package->{_relatives}) {
					foreach $pkgg (@{$package->{_relatives}}){
						$pkggname = $pkgg->get_name();
						if ($pkggname eq $dppname) {
							$isgood = 0;
						} 
					}
				}
				push @extendeddeps, $deps{$dppname} if $isgood;
			}

			if (exists $package->{_relatives}) {
				foreach $pkg (@{$package->{_relatives}}) {
					my $name = $pkg->get_name();
					if (exists $deps{$name}) {
						foreach $dpp (@{$deps{$name}}[5..$#{$deps{$name}}]) {
							$isgood = 1;
							$dppname = $dpp->[PKGNAME];
							foreach $pkgg (@{$package->{_relatives}}){
								$pkggname = $pkgg->get_name();
								if ($pkggname eq $dppname) {
									$isgood = 0;
								} 
							}
							push @extendeddeps, $deps{$dppname} if $isgood;
						}
					}
				}
			}

			# check dependencies
			foreach $dep (@extendeddeps) {
				next PACKAGELOOP if (($dep->[FLAG] & 2) == 0);
			}

			my @batch_install;

			$any_installed = 1;

			# Mark item as done (FIXME - why can't we just delete it from %deps?)
			$item->[FLAG] |= 2;

			next if $already_activated{$pkgname};

			# Check whether package has to be (re)built. Defaults to false.
			$to_be_rebuilt{$pkgname} = 0 unless exists $to_be_rebuilt{$pkgname};

			# If there is no .deb present, we definitely have to (re)built.
			$to_be_rebuilt{$pkgname} |= not $package->is_present();

			if (not $to_be_rebuilt{$pkgname} and exists $package->{_relatives}) {
				# So far, it seems the package doesn't have to be rebuilt. However,
				# it has splitoff relatives. If any of those is going to be rebuilt,
				# then rebuild the package, too!
				# Reasoning: If any splitoff is rebuilt, then fink automatically 
				# will rebuild all others splitoffs (including master), too. This
				# check here essential is there to make the dependency engine
				# properly aware of that fact. Without it, odd things can happen
				# (like for example an old version of a splitoff being installed,
				# then its package being rebuilt, then a new version of one of its
				# relatives being installed).
				foreach $pkg (@{$package->{_relatives}}) {
					next unless exists $to_be_rebuilt{$pkg->get_name()};
					$to_be_rebuilt{$pkgname} |= $to_be_rebuilt{$pkg->get_name()};
					last if $to_be_rebuilt{$pkgname}; # short circuit
				}
			}

			# Now (re)build the package if we determined above that it is necessary.
			my $is_build = $to_be_rebuilt{$pkgname};
			if ($is_build) {
				### only run one deep per depend
				### set forceoff to count depth of depends
				### and to silence the dep engine so it
				### only asks once at the begining
				unless ($forceoff) {
					### Double check it didn't already get
					### installed in an other loop
					if (!$package->is_installed() || $op == $OP_REBUILD) {
						$package->phase_unpack();
						$package->phase_patch();
						$package->phase_compile();
						$package->phase_install();
						$package->phase_build();
					} else {
						&real_install($OP_BUILD, 0, 1, $package->get_name());
					}
				}
			}

			# Install the package unless we already did that in a previous
			# iteration, and if the command issued by the user was an "install"
			# or a "reinstall" or a "rebuild" of an currently installed pkg.
			if (($item->[OP] == $OP_INSTALL or $item->[OP] == $OP_REINSTALL)
					 or ($is_build and $package->is_installed())) {
				push(@batch_install, $package);
				$already_activated{$pkgname} = 1;
			}
			
			# Mark the package and all its "relatives" as being rebuilt if we just
			# did perform a build - this way we won't rebuild packages twice when
			# we process another splitoff of the same parent.
			# In addition, we check for all splitoffs whether they have to be reinstalled.
			# That is the case if they are currently installed and were just rebuilt.
			$to_be_rebuilt{$pkgname} = 0;
			if (exists $package->{_relatives}) {
				foreach $pkg (@{$package->{_relatives}}) {
					my $name = $pkg->get_name();
					$to_be_rebuilt{$name} = 0;
					next if $already_activated{$name};
					# Reinstall any installed splitoff if we just rebuilt
					if ($is_build and $pkg->is_installed()) {
						push(@batch_install, $pkg);
						$already_activated{$name} = 1;
						next;
					}
					# Also (re)install if that was requested by the user
					next unless exists $deps{$name};
					$item = $deps{$name};
					if ((($item->[FLAG] & 2) != 2) and
							($item->[OP] == $OP_INSTALL or $item->[OP] == $OP_REINSTALL)) {
						push(@batch_install, $pkg);
						$already_activated{$name} = 1;
					}
				}
			}

			# Finally perform the actually installation
			Fink::PkgVersion::phase_activate(@batch_install) unless (@batch_install == 0);
			# Reinstall buildconficts after the build
			&real_install($OP_INSTALL, 1, 1, @removals) if (scalar(@removals) > 0);
			# Mark all installed items as installed

			foreach $pkg (@batch_install) {
					$deps{$pkg->get_name()}->[FLAG] |= 2;
			}

		}
		last if $all_installed;

		if (!$any_installed) {
			die "Problem resolving dependencies. Check for circular dependencies.\n";
		}
	}
}

### helper routines

sub expand_packages {
	my ($pkgspec, $package, @package_list);

	@package_list = ();
	foreach $pkgspec (@_) {
		$package = Fink::PkgVersion->match_package($pkgspec);
		unless (defined $package) {
			die "no package found for specification '$pkgspec'!\n";
		}
		push @package_list, $package;
	}
	return @package_list;
}

### Display pkgs in an info file based on and pkg name

sub cmd_splitoffs {
	my ($pkg, $package, @pkgs, $arg);

	print "\n";
	foreach $arg (@_) {
		$package = Fink::PkgVersion->match_package($arg);
		unless (defined $package) {
			print "no package found for specification '$arg'!\n";
			next;
		}

		@pkgs = $package->get_splitoffs(1, 1);
		if ($arg ne $pkgs[0]->get_name()) {
			print "$arg is a child, it's parent ";
		}
		printf("%s has ", $pkgs[0]->get_name());
		unless ($pkgs[1]) {
			printf("no children.\n");
		} else {
			printf("%d child", $#pkgs);
			if ($#pkgs > 1) {
				print "ren";
			}
			print ":\n";
			foreach $pkg (@pkgs) {
				unless ($pkg eq $pkgs[0]) {
					printf("\t-> %s\n", $pkg->get_name());
				}
			}
		}
		print "\n";
	}
}

### Display a pkg's parent

sub cmd_showparent {
	my ($pkg, $package, @pkgs, $arg);

	print "\n";
	foreach $arg (@_) {
		$package = Fink::PkgVersion->match_package($arg);
		unless (defined $package) {
			print "no package found for specification '$arg'!\n";
			next;
		}

		@pkgs = $package->get_splitoffs(1, 1);
		unless ($arg eq $pkgs[0]->get_name()) {
			printf("%s's parent is %s.\n", $arg, $pkgs[0]->get_name());
		} else {
			printf("%s is the parent.\n", $arg);
		}
	}
}


### display a pkg's package description (parsed .info file)
sub cmd_dumpinfo {

	my (@fields, @percents, $wantall, $wanthelp);

	use Getopt::Long;
	my @temp_ARGV = @ARGV;
	@ARGV=@_;
	Getopt::Long::Configure(qw(bundling ignore_case require_order no_getopt_compat prefix_pattern=(--|-)));
	GetOptions(
		'all|a'	=>     \$wantall,
		'field|f=s',   \@fields,
		'percent|p=s', \@percents,
		'help|h'	=> \$wanthelp
	) or die "fink dumpinfo: unknown option\nType 'fink dumpinfo --help' for more information.\n";
	if ($wanthelp) {
		require Fink::FinkVersion;
		my $version = Fink::FinkVersion::fink_version();
		print <<"EOF";
Fink $version

Usage: fink dumpinfo [options] [package(s)]

Options:
  -a, --all            - All package info fields (default behavior).
  -f s, --field=s      - Just the specific field(s) specified.
  -p s, --percent=key  - Just the percent expansion for specific key(s).
  -h, --help           - This help text.

The following pseudo-fields are available in addition to all fields
described in the Fink Packaging Manual:
  infofile     - Full path to package description file.
  sources      - Source and all SourceN values in numerical order.
  splitoffs    - Package name for SplitOff and all SplitOffN in numerical
                 order. You cannot ask for splitoff packages by SplitOffN
                 field name of the parentfields by field name--they are
                 handled as full and independent packages.
  parent       - Package name of main package (if a splitoff package).
  family       - "splitoffs", "parent", and "splitoffs" of "parent".
  status       - For this version of the package:
                   "latest" if the most recent known version, or
                   "old" if a more recent version is known;
                 followed by:
                   "installed" if this version is currently installed.
  allversions  - List of all known versions of the package name in order.
                 Currently-installed version (if any) is prefixed with "i".
  env          - Shell environment in effect during pkg construction.

EOF
		exit 0;
	}

	Fink::Package->require_packages();
	@_ = @ARGV;
	@ARGV = @temp_ARGV;

	# handle clustered param values
	@fields   = split /,/, lc ( join ',', @fields   ) if @fields;
	@percents = split /,/,    ( join ',', @percents ) if @percents;

	my @pkglist = &expand_packages(@_);
	if (! @pkglist) {
		die "fink dumpinfo: no package(s) specified\nType 'fink dumpinfo --help' for more information.\n";
	}

	foreach my $pkg (@pkglist) {

		# default to all fields if no fields or %expands specified
		if ($wantall or not (@fields or @percents)) {
			@fields = (qw/
					   infofile package epoch version revision parent family
					   status allversions
					   description type license maintainer
					   pre-depends depends builddepends
					   provides replaces conflicts buildconflicts
					   recommends suggests enhances
					   essential builddependsonly
					   custommirror
					   /);
			foreach ($pkg->get_source_suffices) {
				if ($_ eq "") {
					push @fields, (qw/
								   source sourcerename source-md5
								   nosourcedirectory sourcedirectory
								   tarfilesrename
								   /);
				} else {
					push @fields, ("source${_}", "source${_}rename",
								   "source${_}-md5",
								   "source${_}extractdir",
								   "tar${_}filesrename"
								  );
				}
			}
			push @fields, (qw/
						   updateconfigguess updateconfigguessindirs
						   updatelibtool updatelibtoolindirs
						   updatepomakefile
						   patch patchscript /,
						   $pkg->params_matching(/^set/),
						   $pkg->params_matching(/^noset/),
						   qw/
						   env
						   configureparams gcc compilescript noperltests
						   updatepod installscript
						   jarfiles docfiles shlibs runtimevars splitoffs files
						   preinstscript postinstscript
						   prermscript postrmscript
						   conffiles infodocs daemonicname daemonicfile
						   homepage descdetail descusage
						   descpackaging descport
						   /);
		};

		foreach (@fields) {
			if ($_ eq 'infofile') {
				printf "infofile: %s\n", $pkg->get_info_filename();
			} elsif ($_ eq 'package') {
				printf "%s: %s\n", $_, $pkg->get_name();
			} elsif ($_ eq 'version') {
				printf "%s: %s\n", $_, $pkg->get_version(); 
			} elsif ($_ eq 'revision') {
				printf "%s: %s\n", $_, $pkg->param_default('revision', '1');
			} elsif ($_ eq 'parent') {
				printf "%s: %s\n", $_, $pkg->{parent}->get_name() if exists $pkg->{parent};
			} elsif ($_ eq 'splitoffs') {
				printf "%s: %s\n", $_, join ', ', map { $_->get_name() } @{$pkg->{_splitoffs}} if defined $pkg->{_splitoffs} and @{$pkg->{_splitoffs}};
			} elsif ($_ eq 'family') {
				printf "%s: %s\n", $_, join ', ', map { $_->get_name() } $pkg->get_splitoffs(1, 1);
			} elsif ($_ eq 'status') {
				my $package = Fink::Package->package_by_name($pkg->get_name());
				my $lversion = &latest_version($package->list_versions());
				print "$_:";
				$pkg->get_fullversion eq $lversion
					? print " latest"
					: print " old";
				print " have-deb" if $pkg->is_present();
				print " installed" if $pkg->is_installed();
				print "\n";
			} elsif ($_ eq 'allversions') {
				# multiline field, so indent 1 space always
				my $package = Fink::Package->package_by_name($pkg->get_name());
				my $lversion = &latest_version($package->list_versions());
				print "$_:\n";
				foreach (&sort_versions($package->list_versions())) {
					printf " %1s%1s\t%s\n",
						$package->get_version($_)->is_present() ? "b" : "",
						$package->get_version($_)->is_installed() ? "i" : "",
						$_;
				}
			} elsif ($_ eq 'description') {
				printf "%s: %s\n", $_, $pkg->get_shortdescription;
			} elsif ($_ =~ /^desc(detail|usage|packaging|port)$/) {
				# multiline field, so indent 1 space always
				# format_description does that for us
				print "$_:\n", Fink::PkgVersion::format_description($pkg->param($_)) if $pkg->has_param($_);
			} elsif ($_ eq 'type'       or $_ eq 'license' or
					 $_ eq 'maintainer' or $_ eq 'homepage'
					) {
				printf "%s: %s\n", $_, $pkg->param_default($_,'[undefined]');
			} elsif ($_ eq 'pre-depends'    or $_ eq 'depends'        or
					 $_ eq 'builddepends'   or $_ eq 'provides'       or
					 $_ eq 'replaces'       or $_ eq 'conflicts'      or
					 $_ eq 'buildconflicts' or $_ eq 'recommends'     or
					 $_ eq 'suggests'       or $_ eq 'enhances'		
					) {
				my $deplist = $pkg->pkglist($_);
				printf "%s: %s\n", $_, $deplist if defined $deplist;
			} elsif ($_ eq 'essential'         or $_ eq 'builddependsonly'  or
					 $_ =~ /^noset/            or $_ eq 'noperltests'       or
					 $_ eq 'updatepod'
					) {
				my $bool = $pkg->param_boolean($_);
				if ($bool) {
					$bool = "true";
				} elsif (defined $bool) {
					$bool = "false";
				} else {
					$bool = "[undefined]";
				}
				printf "%s: %s\n", $_, $bool;
			} elsif ($_ eq 'nosourcedirectory' or $_ eq 'updateconfigguess' or
					 $_ eq 'updatelibtool'     or $_ eq 'updatepomakefile'
					) {
				# these are not for SplitOff pkgs
				my $bool = $pkg->param_boolean($_);
				if ($bool) {
					$bool = "true";
				} elsif (defined $bool) {
					$bool = "false";
				} else {
					$bool = "[undefined]";
				}
				printf "%s: %s\n", $_, $bool unless exists $pkg->{parent};
			} elsif ($_ eq 'sources') {
				# multiline field, so indent 1 space always
				my @suffixes = map { $pkg->get_source($_) } $pkg->get_source_suffices;
				if (@suffixes) {
					print "$_:\n";
					print map { " $_\n" } @suffixes;
				}
			} elsif ($_ =~ /^source(\d*)$/) {
				my $src = $pkg->get_source($1);
				printf "%s: %s\n", $_, $src if defined $src && $src ne "none";
			} elsif ($_ eq 'gcc' or $_ eq 'epoch' or $_ =~ /^source\d*-md5$/) {
				printf "%s: %s\n", $_, $pkg->param($_) if $pkg->has_param($_);
			} elsif ($_ eq 'configureparams') {
				my $cparams = &expand_percent(
					$pkg->prepare_percent_c,
					$pkg->{_expand}, "fink dumpinfo " . $pkg->get_name . '-' . $pkg->get_fullversion
				);
				$cparams =~ s/\n//g;
				printf "%s: %s\n", $_, $cparams if length $cparams;
			} elsif ($_ =~ /^source(\d*rename|directory|\d+extractdir)$/ or
					 $_ =~ /^tar\d*filesrename$/ or
					 $_ =~ /^update(configguess|libtool)indirs$/ or
					 $_ =~ /^set/ or $_ =~ /^(jar|doc|conf)files$/ or
					 $_ eq 'patch' or $_ eq 'infodocs' or
					 $_ =~ /^daemonicname$/
					) {
				# singleline fields start on the same line, have
				# embedded newlines removed, and are not wrapped
				if ($pkg->has_param($_)) {
					my $value = $pkg->param_expanded($_);
					$value =~ s/^\s+//m;
					$value =~ s/\n/ /g; # merge into single line
					printf "%s: %s\n", $_, $value;
				}
			} elsif ($_ eq 'files') {
				# singleline fields start on the same line, have
				# embedded newlines removed, and are not wrapped
				# need conditionals processing
				if ($pkg->has_param($_)) {
					my $value = $pkg->conditional_space_list(
						$pkg->param_expanded("Files"),
						"Files of ".$pkg->get_fullname()." in ".$pkg->get_info_filename
					);
					printf "%s: %s\n", $_, $value if length $value;
				}
			} elsif ($_ =~ /^(((pre|post)(inst|rm))script)|(shlibs|runtimevars|custommirror)|daemonicfile$/) {
				# multiline fields start on a new line and are
				# indented one extra space
				if ($pkg->has_param($_)) {
					my $value = $pkg->param_expanded($_);
					$value =~ s/^/ /gm;
					printf "%s:\n%s\n", $_, $value;
				}
			} elsif ($_ =~ /^(patch|compile|install)script$/) {
				# multiline field with specific accessor
				my $value = $pkg->get_script($_);
				if (length $value) {
					$value =~ s/^/ /gm;
					printf "%s:\n%s\n", $_, $value;
				}
			} elsif ($_ eq 'env') {
				# multiline field, but has special format and own accessor
				my $value = $pkg->get_env;
				printf "%s:\n", $_;
				print map { " $_=".$value->{$_}."\n" } sort keys %$value;
			} else {
				die "Unknown field $_\n";
			}
		}
		$pkg->prepare_percent_c;
		foreach (@percents) {
			s/^%(.+)/$1/;  # remove optional leading % (but allow '%')
			printf "%%%s: %s\n", $_, &expand_percent("\%{$_}", $pkg->{_expand}, "fink dumpinfo " . $pkg->get_name . '-' . $pkg->get_fullversion);
		}
	}
}

# display the dependencies "from a user's perspective" of a given package
sub cmd_show_deps {
	my( $field, $pkglist, $did_print );  # temps used in dep-listing loops

	my @plist = &expand_packages(@_);
	if ($#plist < 0) {
		die "no package specified for command 'show-deps'!\n";
	}

	print "\n";

	foreach my $pkg (@plist) {
		my @relatives = ();
		if (exists $pkg->{_relatives}) {
			@relatives = @{$pkg->{_relatives}};
		}

		printf "Package: %s (%s)\n", $pkg->get_name(), $pkg->get_fullversion();

		print "To install the compiled package...\n";

		print "  The following other packages (and their dependencies) must be installed:\n";
		&show_deps_display_list(
			[qw/ Depends Pre-Depends /],
			[ $pkg ],
			0
		);
		
		print "  The following other packages must not be installed:\n";
		&show_deps_display_list(
			[qw/ Conflicts /],
			[ $pkg ],
			0
		);

		print "To compile this package from source...\n";

		print "  The following packages are also compiled at the same time:\n";
		if (@relatives) {
			foreach (@relatives) {
				printf "    %s (%s)\n", $_->get_name(), $_->get_fullversion();
			}
		} else {
			print "    [none]\n";
		}

		print "  The following other packages (and their dependencies) must be installed:\n";
		&show_deps_display_list(
			[qw/ Depends Pre-Depends BuildDepends /],
			[ $pkg, @relatives ],
			1
		);

		print "  The following other packages must not be installed:\n";
		&show_deps_display_list(
			[qw/ BuildConflicts /],
			[ $pkg, @relatives ],
			1
		);

		print "\n";
	}
}

# pretty-print a set of PkgVersion::pkglist (each "or" group on its own line)
# pass:
#   ref to list of field names
#   ref to list of PkgVersion objects
#   boolean whether to exclude packages themselves when printing
sub show_deps_display_list {
	my $fields = shift;
	my $pkgs = shift;
	my $exclude_selves = shift;

	my $family_regex;
	if ($exclude_selves) {
		# regex for any ("or") package name from the given pkgs
		$family_regex = join '|', map { qr/\Q$_\E/i } map { $_->get_name() } (@$pkgs);
	}

	my $field_value;    # used in dep processing loop (string from pkglist())

	my $did_print = 0;  # did we print anything at all?
	foreach my $field (@$fields) {
		foreach (@$pkgs) {
			next unless defined( $field_value = $_->pkglist($field) );
			foreach (split /\s*,\s*/, $field_value) {
				# take each requested field of each requested pkg
				# and parse apart "and"-separated "or" groups

				if (defined $family_regex) {
					# optionally remove own family from build-time deps
					while (s/(\A|\|)\s*($family_regex)\s*(\(.*?\))?\s*(\||\Z)/|/) {};
					s/^\s*\|\s*//;
					s/\s*\|\s*$//;
				}

				if (length $_) {
					printf "    %s\n", $_;
					$did_print++;
				}
			}
		}
	}
	print "    [none]\n" unless $did_print;

}

### EOF
1;
