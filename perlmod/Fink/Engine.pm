#
# Fink::Engine class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2003 The Fink Package Manager Team
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

use Fink::Services qw(&print_breaking
					  &prompt_boolean &prompt_selection
					  &latest_version &execute &get_term_width
					  &file_MD5_checksum &get_arch);
use Fink::Package;
use Fink::Shlibs;
use Fink::PkgVersion;
use Fink::Config qw($config $basepath $debarch);
use File::Find;
use Fink::Status;

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
# a function reference, and two flags. The first flag indicates
# whether this command requires the package descriptions to be
# read, the second flag whether root permissions are needed.
our %commands =
	( 'index' => [\&cmd_index, 0, 1],
	  'rescan' => [\&cmd_rescan, 0, 0],
	  'configure' => [\&cmd_configure, 0, 1],
	  'bootstrap' => [\&cmd_bootstrap, 0, 1],
	  'fetch' => [\&cmd_fetch, 1, 1],
	  'fetch-all' => [\&cmd_fetch_all, 1, 1],
	  'fetch-missing' => [\&cmd_fetch_all_missing, 1, 1],
	  'build' => [\&cmd_build, 1, 1],
	  'rebuild' => [\&cmd_rebuild, 1, 1],
	  'install' => [\&cmd_install, 1, 1],
	  'reinstall' => [\&cmd_reinstall, 1, 1],
	  'update' => [\&cmd_install, 1, 1],
	  'update-all' => [\&cmd_update_all, 1, 1],
	  'enable' => [\&cmd_install, 1, 1],
	  'activate' => [\&cmd_install, 1, 1],
	  'use' => [\&cmd_install, 1, 1],
	  'disable' => [\&cmd_remove, 1, 1],
	  'deactivate' => [\&cmd_remove, 1, 1],
	  'unuse' => [\&cmd_remove, 1, 1],
	  'remove' => [\&cmd_remove, 1, 1],
	  'delete' => [\&cmd_remove, 1, 1],
	  'purge' => [\&cmd_purge, 1, 1],
	  'apropos' => [\&cmd_apropos, 0, 0],
	  'describe' => [\&cmd_description, 1, 0],
	  'description' => [\&cmd_description, 1, 0],
	  'desc' => [\&cmd_description, 1, 0],
	  'info' => [\&cmd_description, 1, 0],
	  'scanpackages' => [\&cmd_scanpackages, 1, 1],
	  'list' => [\&cmd_list, 0, 0],
	  'listpackages' => [\&cmd_listpackages, 1, 0],
	  'selfupdate' => [\&cmd_selfupdate, 0, 1],
	  'selfupdate-cvs' => [\&cmd_selfupdate_cvs, 0, 1],
	  'selfupdate-rsync' => [\&cmd_selfupdate_rsync, 0, 1],
	  'selfupdate-finish' => [\&cmd_selfupdate_finish, 1, 1],
	  'validate' => [\&cmd_validate, 0, 0],
	  'check' => [\&cmd_validate, 0, 0],
	  'checksums' => [\&cmd_checksums, 1, 0],
	  'cleanup' => [\&cmd_cleanup, 1, 1],
	  'depends' => [\&cmd_depends, 1, 0],
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
	my ($cmdname, $cmdinfo, $info);
	my ($proc, $pkgflag, $rootflag);

	unless (defined $cmd) {
		print "NOP\n";
		return;
	}

	$cmdinfo = undef;
	while (($cmdname, $info) = each %commands) {
		if ($cmd eq $cmdname) {
			$cmdinfo = $info;
			last;
		}
	}
	if (not defined $cmdinfo) {
		die "fink: unknown command \"$cmd\".\nType 'fink --help' for more information.\n";
	}

	($proc, $pkgflag, $rootflag) = @$cmdinfo;

	# check if we need to be root
	if ($rootflag and $> != 0) {
		&restart_as_root($options, $cmd, @_);
	}

	# read package descriptions if needed
	if ($pkgflag) {
		Fink::Package->require_packages();
		Fink::Shlibs->require_shlibs();
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
	Fink::Shlibs->update_shlib_db();
}

sub cmd_rescan {
	Fink::Package->forget_packages();
	Fink::Package->require_packages();
	Fink::Shlibs->forget_shlibs();
	Fink::Shlibs->require_shlibs();
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
	my ($width, $namelen, $verlen, $dotab, $wanthelp);
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
				   'tab|t'		=> \$dotab,
				   'installed|i'	=> sub {$options{installedstate} |=3;},
				   'uptodate|u'		=> sub {$options{installedstate} |=2;},
				   'outdated|o'		=> sub {$options{installedstate} |=1;},
				   'notinstalled|n'	=> sub {$options{installedstate} |=4;},
				   'buildonly|b'	=> \$buildonly,
				   'section|s=s'	=> \$section,
				   'maintainer|m=s'	=> \$maintainer,
				   'tree|r=s'		=> \$pkgtree,
				   'help|h'		=> \$wanthelp
		) or die "fink list: unknown option\nType 'fink list --help' for more information.\n";
	}	 else { # apropos
		GetOptions(
				   'width|w=s'		=> \$width,
				   'tab|t'			=> \$dotab,
				   'help|h'			=> \$wanthelp
		) or die "fink list: unknown option\nType 'fink apropos --help' for more information.\n";
	}
	if ($wanthelp) {
		require Fink::FinkVersion;
		my $version = Fink::FinkVersion::fink_version();

		if ($cmd eq "list") {
			print <<"EOF";
Fink $version

Usage: fink list [options] [string]

Options:
  -w=xyz, --width=xyz  - Sets the width of the display you would like the output
                         formatted for. xyz is either a numeric value or auto.
                         auto will set the width based on the terminal width.
  -t, --tab            - Outputs the list with tabs as field delimiter.
  -i, --installed      - Only list packages which are currently installed.
  -u, --uptodate       - Only list packages which are up to date.
  -o, --outdated       - Only list packages for which a newer version is
                         available.
  -n, --notinstalled   - Only list packages which are not installed.
  -b, --buildonly      - Only list packages which are Build Only Depends
  -s=expr,             - Only list packages in the section(s) matching expr
    --section=expr       (example: fink list --section=x11).
  -m=expr,             - Only list packages with the maintainer(s) matching expr
    --maintainer=expr    (example: fink list --maintainer=beren12).
  -t=expr,             - Only list packages with the tree matching expr
    --tree=expr          (example: fink list --tree=stable).
  -h, --help           - This help text.

EOF
		} else { # apropos
			print <<"EOF";
Fink $version

Usage: fink apropos [options] [string]
       
Options:
  -w=xyz, --width=xyz  - Sets the width of the display you would like the output
                         formatted for. xyz is either a numeric value or auto.
                         auto will set the width based on the terminal width.
  -t, --tab            - Outputs the list with tabs as field delimiter.
  -h, --help           - This help text.

EOF
		}
	exit 0;
	}
	if ($options{installedstate} == 0) {$options{installedstate} = 7;}

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
		$width = $width - 5;					 # 5 chars for the first field
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
	Fink::Shlibs->require_shlibs();
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
			if (not ($options{installedstate} & 4)) {next; };
		} else {
			$lversion = &latest_version($package->list_versions());
			$vo = $package->get_version($lversion);
			if ($vo->is_installed()) {
				if (not ($options{installedstate} &2)) {next;};
				$iflag = " i ";
			} elsif ($package->is_any_installed()) {
				$iflag = "(i)";
				if (not ($options{installedstate} &1)) {next;};
			} else {
				$iflag = "   ";
				if (not ($options{installedstate} & 4)) {next; };
			}

			$description = $vo->get_shortdescription($desclen);
		}
		if (defined $buildonly) {
			next unless ( $vo->param_boolean("builddependsonly") );
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
		printf $formatstr,
				$iflag, $pname, $lversion, $description;
	}
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
			if (&execute("/bin/mkdir -p $treedir")) {
				die "can't create directory $treedir\n";
			}
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
		 or die "fink fetch: unknown option\nType 'fink fetch-missing --help' or 'fetch-all --help' for more information.\n";
		 
	if ($options{wanthelp} == 1) {
		require Fink::FinkVersion;
		my $finkversion = Fink::FinkVersion::fink_version();
		print <<"EOF";
Fink $finkversion

Usage: fink fetch-{missing,all} [options]
       
Options:
  -i, --ignore-restrictive  - Do not fetch sources for packages with 
                            a "Restrictive" license. Useful for mirroring.
  -p, --dry-run             - Prints filename, MD5, list of source URLs, Maintainer for each package
  -h, --help                - This help text.

EOF
		die " ";
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
	%options = &parse_fetch_options(@_);
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

	%options = &parse_fetch_options(@_);
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
	my ($vo, @versions);
	my ($buildonly, $wanthelp);

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
	Fink::Shlibs->require_shlibs();
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

		# shouldn't be able to remove or purge esstential pkgs
		@versions = $package->list_installed_versions();
		$vo = $package->get_version($versions[0]);
		if ( $vo->param_boolean("essential") ) {
			print "WARNING: $pname is essential, skipping.\n";
			next;
		}

		if (defined $buildonly) {
			next unless ( $vo->param_boolean("builddependsonly") );
		}

		push @packages, $package->get_name();
	}

	# Incase no packages meet the requirements above.
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

	require Fink::Validation;

	@flist = @_;
	if ($#flist < 0) {
		die "no input file specified for command 'validate'!\n";
	}
	
	foreach $filename (@flist) {
		die "File \"$filename\" does not exist!\n" unless (-f $filename);
		if ($filename =~/\.info$/) {
			Fink::Validation::validate_info_file($filename);
		} elsif ($filename =~/\.deb$/) {
			Fink::Validation::validate_dpkg_file($filename);
		} else {
			die "Don't know how to validate $filename!\n";
		}
	}
}

# HACK HACK HACK
# This is to be removed soon again, only a temporary tool to allow
# checking of all available MD5 values in all packages.
sub cmd_checksums {
	my ($pname, $package, $vo, $i, $file, $chk);

	# Iterate over all packages
	foreach $pname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pname);
		foreach $vo ($package->get_all_versions()) {
			# Skip packages that do not have source files
			next if not defined $vo->{_sourcecount};
		
			# For each tar ball, if a checksum was specified, locate it and
			# verify the checksum.
			for ($i = 1; $i <= $vo->{_sourcecount}; $i++) {
				$chk = $vo->get_checksum($i);
				if ($chk ne "-") {
					$file = $vo->find_tarball($i);
					if (defined($file) and $chk ne &file_MD5_checksum($file)) {
						print "Checksum of tarball $file of package ".$vo->get_fullname()." is incorrect.\n";
					}
				}
			}
		}
	}
}

sub cmd_cleanup {
	my ($pname, $package, $vo, $i, $file);
	my (@to_be_deleted);

	# TODO - add option that specify whether to clean up source, .debs, or both
	# TODO - add --dry-run option that prints out what actions would be performed
	# TODO - option that steers which file to keep/delete: keep all files that
	#				 are refered by any .info file; keep only those refered to by the
	#				 current version of any package; etc.
	#				 Delete all .deb and delete all src? Not really needed, this can be
	#				 achieved each with single line CLI commands.
	
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
			next if $vo->{_type} eq "dummy";

			# deb file 
			$file = $vo->get_debfile();
			$deb_list{$file} = 1;

			# all source files
			if (defined $vo->{_sourcecount}) {
				for ($i = 1; $i <= $vo->{_sourcecount}; $i++) {
					$file = $vo->find_tarball($i);
					$src_list{$file} = 1 if defined($file);
				}
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
	@to_be_deleted = ();
	opendir(DIR, "$basepath/src") or die "Can't access $basepath/src: $!";
	while (defined($file = readdir(DIR))) {
		$file = "$basepath/src/$file";
		# Skip all source files that are still used by some package
		next if $src_list{$file};
		push @to_be_deleted, $file;
	}
	closedir(DIR);

	foreach $file (@to_be_deleted) {
		# For now, do *not* remove directories - this could easily kill
		# a build running in another process. In the future, we might want
		# to add a --dirs switch that will also delete directories.
		if (-f $file) {
			unlink $file and $file_count{'src'}++;
	}
}

	print 'Obsolete deb packages deleted: ' . $file_count{'deb'} . "\n";
	print 'Obsolete symlinks deleted: ' . $file_count{'symlink'} . "\n";
	print 'Obsolete sources deleted: ' . $file_count{'src'} . "\n\n";
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
			@deplist = $item->[PKGVER]->resolve_depends(2, $op, "Depends", $forceoff);
			@conlist = $item->[PKGVER]->resolve_depends(2, $op, "Conflicts", $forceoff);
		} elsif (not $item->[PKGVER]->is_present() or $item->[OP] == $OP_REBUILD) {
			# We want to install this package and have to build it for that
			# -> include both life-time & build-time dependencies
			@deplist = $item->[PKGVER]->resolve_depends(1, $op, "Depends", $forceoff);
			@conlist = $item->[PKGVER]->resolve_depends(2, $op, "Conflicts", $forceoff);
		} else {
			# We want to install this package and already have a .deb for it
			# -> only include life-time dependencies
			@deplist = $item->[PKGVER]->resolve_depends(0, $op, "Depends", $forceoff);
			@conlist = $item->[PKGVER]->resolve_depends(2, $op, "Conflicts", $forceoff);
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
				if (exists $deps{$dname} and $deps{$dname}->[2] == $dp) {
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
			$found = 0;

			if ($#candidates == 0) {	# only one candidate
				$dname = $candidates[0];
				$found = 1;
			}

			if (not $found) {
				# check for installed pkgs (by name)
				my $cand;
				foreach $cand (@candidates) {
					$pnode = Fink::Package->package_by_name($cand);
					if ($pnode->is_any_installed()) {
						$dname = $cand;
						$found++;
						last;
					}
				}
			}

			if (not $found) {

				# check if a sibling package has been marked for install
				# if so, choose it instead of asking

				my ($cand, $splitoff);
				SIBCHECK: foreach $cand (@candidates) {
					my $package = Fink::Package->package_by_name($cand);
					my $lversion = &latest_version($package->list_versions());
					my $vo = $package->get_version($lversion);
					
					if (exists $vo->{_relatives}) {
						foreach $splitoff (@{$vo->{_relatives}}) {
							# if the package is being installed, or is already installed,
							# auto-choose it
							if ( exists $deps{$splitoff->get_name()} ) {
								$dname = $cand;
								$found++;
							} elsif ( $splitoff->is_installed() ) {
								$dname = $cand;
								$found++;
							}
						}
					}
				}
			}
			if (not $found) {
				# See if the user has a regexp to match in fink.conf
				my $matchstr = $config->param("MatchPackageRegEx");
				my $matchcount =0;
				my $usename;
				if (defined $matchstr) {
					foreach $dname (@candidates) {
						if ( $dname =~ $matchstr ) {
							$matchcount++;
							$usename = $dname;
						}
					}
					if (1 == $matchcount ) {
						$dname = $usename;
						$found = 1;
					}
				}
			}
			if (not $found) {
				# let the user pick one

				my $labels = {};
				my $pkgindex = 1;
				my $choice = 1;
				my $founddebcnt = 0;
				foreach $dname (@candidates) {
					my $package = Fink::Package->package_by_name($dname);
					my $lversion = &latest_version($package->list_versions());
					my $vo = $package->get_version($lversion);
					my $description = $vo->get_shortdescription(60);
					$labels->{$dname} = "$dname: $description";
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
				$dname =
					&prompt_selection("Pick one:", $choice, $labels, @candidates);
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
	foreach $pkgname (sort keys %deps) {
		$item = $deps{$pkgname};
		if ($item->[FLAG] == 0) {
			push @additionals, $pkgname;
		} elsif ($item->[FLAG] == 1) {
			push @requested, $pkgname;
		}
	}

	foreach $pkgname (sort keys %cons) {
		push @removals, $pkgname;
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

	# fetch all packages that need fetching
	foreach $pkgname (sort keys %deps) {
		$item = $deps{$pkgname};
		next if $item->[OP] == $OP_INSTALL and $item->[PKGVER]->is_installed();
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

			# concatinate dependencies of package and its relatives
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

			# Check whether package has to be (re)built. For normal packages that
			# means the user explicitly requested the rebuild; but for splitoffs
			# and their parents, we also have to check if any of their "relatives"
			# is scheduled for rebuilding.
			# But first, check if there is no .deb present - in that case we have
			# to build in any case.
			$to_be_rebuilt{$pkgname} = 0 unless exists $to_be_rebuilt{$pkgname};
			$to_be_rebuilt{$pkgname} |= not $package->is_present();
			if (not $to_be_rebuilt{$pkgname} and exists $package->{_relatives}) {
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
					&real_install($OP_BUILD, 0, 1, $package->get_name());
					### Double check it didn't already get
					### installed in an other loop
					unless ($package->is_installed() &&
						$op != $OP_REBUILD) {
						$package->phase_unpack();
						$package->phase_patch();
						$package->phase_compile();
						$package->phase_install();
						$package->phase_build();
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
			# In addition, we check for the splitoffs whether they have to be reinstalled.
			# That is the case if they are currently installed and where rebuild just now.
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
			} else {
				$to_be_rebuilt{$pkgname} = 0;
			}

			# Finally perform the actually installation
			Fink::PkgVersion::phase_activate(@batch_install) unless (@batch_install == 0);
			# Rebuild Shlibs db before next build
			Fink::Shlibs->forget_shlibs();
			Fink::Shlibs->require_shlibs(1);
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

### Display the depends for a package

sub cmd_depends {
	my ($pkg, $package, @deplist, $fullname);

	foreach $pkg (@_) {
		$package = Fink::PkgVersion->match_package($pkg);
		unless (defined $package) {
			print "no package found for specification '$pkg'!\n";
			next;
		}

		$fullname = $package->get_fullname();
		if ($package->find_debfile()) {
			if (Fink::Config::verbosity_level() > 2) {
				print "Reading dependencies from ".$fullname." deb file...\n";
			}
			@deplist = split(/\s*\,\s*/, $package->get_debdeps());
		} else {
			if (Fink::Config::verbosity_level() > 2) {
				print "Reading dependencies from ".$fullname." info file...\n";
			}
			@deplist = split(/\s*\,\s*/, $package->param_default("Depends", ""));
		}

		print "Depends for $fullname are...\n";
		print join(', ', @deplist)."\n\n";
	}
}

### EOF
1;
