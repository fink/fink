# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Engine class
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

package Fink::Engine;

use Fink::Services qw(&latest_version &sort_versions
					  &pkglist2lol &cleanup_lol
					  &execute &expand_percent
					  &count_files
					  &call_queue_clear &call_queue_add
					  &dpkg_lockwait &aptget_lockwait &store_rename &get_options
					  $VALIDATE_HELP &apt_available);
use Fink::CLI qw(&print_breaking &print_breaking_stderr
				 &prompt_boolean &prompt_selection
				 &get_term_width &die_breaking);
use Fink::Configure qw(&spotlight_warning);
use Fink::Finally;
use Fink::Finally::Buildlock;
use Fink::Finally::BuildConflicts;
use Fink::Package;
use Fink::PkgVersion;
use Fink::Config qw($config $basepath $dbpath);
use File::Find;
use Fink::Status;
use Fink::Command qw(mkdir_p rm_f);
use Fink::Notify;
use Fink::Validation;
use Fink::Checksum;
use Fink::Scanpackages;
use IO::Handle;

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

=head1 NAME

Fink::Engine - high-level actions for fink to perform

=head1 DESCRIPTION

=head2 Methods

=over 4

=cut

# The list of commands. Maps command names to a list containing
# a function reference, and three flags. The first flag indicates
# whether this command requires the package descriptions to be
# read, the second flag whether root permissions are needed the
# third flag whether apt-get might be called if the UseBinaryDist
# option is enabled. 1, if apt-get is called without the 
# '--ignore-breakage' option, 2, if it is called with '--ignore-breakage'
our %commands =
	( 'index'             => [\&cmd_index,             0, 1, 1],
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
	  'scanpackages'      => [\&cmd_scanpackages,      0, 1, 1],
	  'list'              => [\&cmd_list,              0, 0, 0],
	  'listpackages'      => [\&cmd_listpackages,      1, 0, 0],
	  'plugins'           => [\&cmd_listplugins,       0, 0, 0],
	  'selfupdate'        => [\&cmd_selfupdate,        0, 1, 1],
	  'self-update'       => [\&cmd_selfupdate,        0, 1, 1],
	  'selfupdate-cvs'    => [\&cmd_selfupdate_cvs,    0, 1, 1],
	  'selfupdate-rsync'  => [\&cmd_selfupdate_rsync,  0, 1, 1],
	  'selfupdate-finish' => [\&cmd_selfupdate_finish, 1, 1, 1],
	  'validate'          => [\&cmd_validate,          0, 0, 0],
	  'check'             => [\&cmd_validate,          0, 0, 0],
	  'cleanup'           => [\&cmd_cleanup,           0, 1, 1],
	  'splitoffs'         => [\&cmd_splitoffs,         1, 0, 0],
	  'splits'            => [\&cmd_splitoffs,         1, 0, 0],
	  'showparent'        => [\&cmd_showparent,        1, 0, 0],
	  'dumpinfo'          => [\&cmd_dumpinfo,          1, 0, 0],
	  'show-deps'         => [\&cmd_show_deps,         1, 0, 0],
	);

END { }				# module clean-up code here (global destructor)

### constructor using configuration

# Why is this here? Why not just inherit from Fink::Base?
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
	
	my $orig_ARGV = shift;
	my $cmd = shift;
	my @args = @_;
	
	my $start = time;
	my ($proc, $pkgflag, $rootflag, $aptgetflag);

	unless (defined $cmd) {
		print "NOP\n";
		return;
	}

	if (not exists $commands{$cmd}) {
		die "fink: unknown command \"$cmd\".\nType 'fink --help' for more information.\n";
	}

	# Store original @ARGV in case we want to know how we were called.
	# This is a stack (a ref to a list of refs to @ARGV) in case we
	# sublaunch a &process)
	# ATTN: Always work on copies of this struct, not the actual refs!!!
	{
		my @argv_stack = @{Fink::Config::get_option('_ARGV_stack', [])};
		push @argv_stack, [ @$orig_ARGV ];
		Fink::Config::set_options({ '_ARGV_stack' => \@argv_stack });
	}

	($proc, $pkgflag, $rootflag, $aptgetflag) = @{$commands{$cmd}};

	# check if we need to be root
	&restart_as_root if $rootflag;  # if it returns, we are assured to be root

	# check if we need apt-get
	if ($aptgetflag > 0 and ($self->{config}->binary_requested())) {
		my $apt_problem = 0;
		if (my $err = $self->{config}->bindist_check_prefix) {
				print "\n";	print_breaking("ERROR: $err");
				$apt_problem = 1;
		}
		# check if apt-get is available
		if (not $apt_problem) {
			if (!apt_available) {
				&print_breaking("ERROR: You have the 'UseBinaryDist' option enabled ".
				    "but apt-get could not be run. Try to install the 'apt' Fink package ".
				    "(with e.g. 'fink install apt').");
				$apt_problem = 1;
			}
		}
		# check if 'apt-get --ignore-breakage' is implemented
		if ($aptgetflag == 2 and not $apt_problem) {
			# only for the commands that needs them
			if (&execute("$basepath/bin/apt-get --ignore-breakage 1>/dev/null 2>/dev/null", quiet=>1)) {
				&print_breaking("ERROR: You have the 'UseBinaryDist' option enabled but the ".
				   "'apt-get' tool installed on this system doesn't support it. Please ".
				   "update your Fink installation (with e.g. 'fink selfupdate').");
				$apt_problem = 1;
			}
		}
		if($apt_problem) {
			my $prompt = "Continue with the 'UseBinaryDist' option temporarily disabled?";
			my $continue = prompt_boolean($prompt, default => 1, timeout => 60);
			if ($continue) {
				# temporarily disable UseBinaryDist
				$self->{config}->set_param("UseBinaryDist", "false");
				Fink::Config::set_options( { 'use_binary' => 0 } );
			}
			else {
				die "Failed to execute '$cmd'!\n";
			}
		}
	}

	# Warn about Spotlight
	if (&spotlight_warning()) {
		$self->{config}->save;
		$self->{config}->initialize;
	}
	
	# read package descriptions if needed
	if ($pkgflag) {
		Fink::Package->require_packages();
	}

	if (Fink::Config::get_option("maintainermode")) {
		print STDERR "Running in Maintainer Mode\n";
	}
	
	# Run the command
	{
		local $SIG{'INT'} = sub { die "User interrupt.\n" };
		eval { &$proc(@args); };
	}
	my $proc_rc = { '$@' => $@, '$?' => $? };  # save for later
	my $retval = 0;
	
	# Scan packages before we print any error message
	Fink::PkgVersion::scanpackages();
	
	# Rebuild the command line, for user viewing
	my $commandline = join ' ', 'fink', @$orig_ARGV;
	my $notifier = Fink::Notify->new();
	if ($proc_rc->{'$@'}) {                    # now deal with eval results
		my $msg = $proc_rc->{'$@'};
		$msg = '' if $msg =~ /^\s*$/; # treat empty messages nicely
		
		print ($msg ? "Failed: $msg" : "Exiting with failure.\n");
		my $notifydesc = $commandline . ($msg ? "\n$msg" : '');
		$notifier->notify(
			event => 'finkDoneFailed',
			description => $notifydesc,
		);

		$retval = $proc_rc->{'$?'} || 1;
	} else {	
		# FIXME: min_notify_secs should be less arbitrary! Option?
		my $min_notify_secs = 60;
		$notifier->notify(
			event => 'finkDonePassed',
			description => $commandline
		) if time() - $start > $min_notify_secs;
	}
	
	# remove ourselves from ARGV stack
	{
		my @argv_stack = @{Fink::Config::get_option('_ARGV_stack', [])};
		pop @argv_stack;
		Fink::Config::set_options({ '_ARGV_stack' => \@argv_stack });
	}

	return $retval;;
}

### restart as root (and not return!) if we are not already root

sub restart_as_root {
	return if $> == 0;

	my $cmd = "$basepath/bin/fink";

	if (my @argv = @{Fink::Config::get_option('_ARGV_stack', [])}) {
		# there is an ARGV in the stack
		foreach my $arg (@{$argv[-1]}) {
			# why aren't we just using String::ShellQuote?
			if ($arg =~ /^[A-Za-z0-9_.+-]+$/) {
				$cmd .= " $arg";
			} else {
				# safety first (protect shell metachars, quote whole string)
				$arg =~ s/[\$\`\'\"|;]/_/g;
				$cmd .= " \"$arg\"";
			}
		}
	}

	my $method = $config->param_default("RootMethod", "sudo");
	if ($method eq "sudo") {
		my $env = '';
		foreach (qw/ PERL5LIB /) {
			# explicitly propagate env vars that sudo wipes
			$env .= "$_='".$ENV{"$_"}."'" if defined $ENV{"$_"};
		}
		$env = "/usr/bin/env $env" if length $env;
		$cmd = "/usr/bin/sudo $env $cmd";
	} elsif ($method eq "su") {
		$cmd = "/usr/bin/su root -c '$cmd'";
	} else {
		die "Fink is not configured to become root automatically.\n";
	}

	exit &execute($cmd, quiet=>1);
}

# these must be numerical and in the correct order (and should really be constants)
my ($OP_FETCH, $OP_BUILD, $OP_INSTALL, $OP_REBUILD, $OP_REINSTALL) =
	(-1, 0, 1, 2, 3);

### simple commands

sub cmd_index {
	my $full;
	
	get_options('index', [
		[ 'full|f' => \$full, 'Do a full reindex, discarding even valid caches.' ],
	], \@_);
	
	# Need to auto-index if specifically running 'fink index'!
	$config->set_param("NoAutoIndex", 0);
	if ($full) {
		Fink::Package->forget_packages({ disk => 1 });
	}
	Fink::Package->update_db(no_load => 1, no_fastload => 1);
}

sub cmd_configure {
	require Fink::Configure;
	Fink::Configure::configure(@_);
}

sub cmd_bootstrap {
	require Fink::Bootstrap;
	Fink::Bootstrap::bootstrap();
}

sub cmd_selfupdate {
	require Fink::SelfUpdate;
	Fink::SelfUpdate::cmd_selfupdate(@_);
}

sub cmd_selfupdate_cvs {
	&cmd_selfupdate('--method=cvs', @_);
}

sub cmd_selfupdate_rsync {
	&cmd_selfupdate('--method=rsync', @_);
}

sub cmd_selfupdate_finish {
	&cmd_selfupdate('--finish', @_);
}

sub cmd_list {
	do_real_list("list",@_);
}

sub cmd_listplugins {
	print "Notification Plugins:\n\n";
	Fink::Notify->list_plugins();
	print "\n";
	print "Checksum Plugins:\n\n";
	Fink::Checksum->list_plugins();
	print "\n";

	require Fink::SelfUpdate;
	print "Selfupdate-Method Plugins:\n\n";
	Fink::SelfUpdate->list_plugins();
	print "\n";
}

sub cmd_apropos {
	do_real_list("apropos", @_);	
}


# Given a list of PkgVersions, find the versions which should be visible to
# the user. PkgVersions passed in do NOT have to be loaded!
sub _user_visible_versions {
	my @pvs = @_;
	foreach my $magic (qw(status virtual)) {
		unless ($config->want_magic_tree($magic)) {
			# Filter out versions of type: dummy ($magic)
			@pvs = grep {
				!$_->is_type('dummy') || $_->get_subtype('dummy') ne $magic
			} @pvs;
		}
	}
	return @pvs;
}

sub do_real_list {
	my ($pattern, @allnames, @selected);
	my ($formatstr, $desclen, $name, $section, $maintainer);
	my ($buildonly, $format);
	my %options =
	(
	 "installedstate" => 0
	);
	# bits used by $options{intalledstate}
	my $ISTATE_OUTDATED = 1;
	my $ISTATE_CURRENT  = 2;
	my $ISTATE_ABSENT   = 4;
	my $ISTATE_TOONEW   = 8; # FIXME: Add option details!
	my ($width, $namelen, $verlen, $dotab);
	my $cmd = shift;
	use Getopt::Long;
	$formatstr = "%s	%-15.15s	%-11.11s	%s\n";
	$desclen = 43;
	$format = 'table';
	
	my @options = (
		[ 'width|w=s'	=> \$width,
			'Sets the width of the display you would like the output ' .
			'formatted for. NUM is either a numeric value or auto. auto will ' .
			'set the width based on the terminal width.', 'NUM' ],
		[ 'tab|t'		=> \$dotab,
			'Outputs the list with tabs as field delimiter.' ],
		[ 'format|f=s'	=> \$format,
			"The output format. FMT is 'table' (default), 'dotty', or 'dotty-build'", 'FMT' ],
	);

	if ($cmd eq "list") {
		@options = ( @options,
			[ 'installed|i'		=>
				sub {$options{installedstate} |= $ISTATE_OUTDATED | $ISTATE_CURRENT ;},
				'Only list packages which are currently installed.' ],
			[ 'uptodate|u'		=>
				sub {$options{installedstate} |= $ISTATE_CURRENT  ;},
				'Only list packages which are up to date.' ],
			[ 'outdated|o'		=>
				sub {$options{installedstate} |= $ISTATE_OUTDATED ;},
				'Only list packages for which a newer version is available.' ],
			[ 'notinstalled|n'	=>
				sub {$options{installedstate} |= $ISTATE_ABSENT   ;},
				'Only list packages which are not installed.' ],
			[ 'newer|N'			=>
				sub {$options{installedstate} |= $ISTATE_TOONEW   ;},
				'Only list packages whose installed version is newer than '
				. 'anything fink knows about.' ],
			[ 'buildonly|b'		=> \$buildonly,
				'Only list packages which are Build Depends Only' ],
			[ 'section|s=s'		=> \$section,
				"Only list packages in the section(s) matching EXPR\n" .
				"(example: fink list --section=x11).", 'EXPR'],
			[ 'maintainer|m=s'	=> \$maintainer,
				"Only list packages with the maintainer(s) matching EXPR\n" .
				"(example: fink list --maintainer=beren12).", 'EXPR'],
		);
	}		
	get_options($cmd, \@options, \@_,
		helpformat => "%intro{[options] [string],foo bar}\n%all{}\n");
	
	
	if ($options{installedstate} == 0) {
		$options{installedstate} = $ISTATE_OUTDATED | $ISTATE_CURRENT
			| $ISTATE_ABSENT | $ISTATE_TOONEW;
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
	@allnames = Fink::Package->list_packages();
	if ($cmd eq "list") {
		if (@_) {
			# prepare the regex patterns
			foreach (@_) {
				# will be using in regex, so mask regex chars
				$_ = lc quotemeta $_;
				# we accept shell filename-glob wildcards (* and ?)
				# convert them to perl regex form
				if (s/\\\*/.*/g or s/\\\?/./g) {
					# no automatic substringing for a glob
					$_ = '\A' . $_ . '\Z';
				}
			}
			# match all patterns in a single go
			$pattern = join '|', @_;
			@selected = grep /$pattern/, @allnames;
		} else {
			# no patterns specified, so list them all
			@selected = @allnames;
		}
	} else {
		$pattern = shift;
		@selected = @allnames;
		unless ($pattern) {
			die "no keyword specified for command 'apropos'!\n";
		}
	}
	
	if ($format eq 'dotty' or $format eq 'dotty-build') {
		print "digraph packages {\n";
		print "concentrate=true;\n";
		print "size=\"30,40\";\n";
	}

	my $reload_disable_save = Fink::Status->is_reload_disabled();  # save previous setting
	Fink::Status->disable_reload(1);  # don't keep stat()ing status db
	foreach my $pname (sort @selected) {
		my $package = Fink::Package->package_by_name($pname);
		
		# Look only in versions the user should see. noload
		my @pvs = _user_visible_versions($package->get_all_versions(1));
		my @provs = _user_visible_versions($package->get_all_providers( no_load => 1 ));
		next unless @provs; # if no providers, it doesn't really exist!
		
		my @vers = map { $_->get_fullversion() } @pvs;
		my $lversion = @vers ? latest_version(@vers) : '';

		# noload: don't bother loading fields until we know we need them
		my $vo = $lversion ? $package->get_version($lversion, 1) : 0;
		
		my $iflag;
		if ($vo && $vo->is_installed()) {
			if ($vo->is_type('dummy') && $vo->get_subtype('dummy') eq 'status') {
				# Newer version than fink knows about
				next unless $options{installedstate} & $ISTATE_TOONEW;
				$iflag = "*i*";
			} else {
				next unless $options{installedstate} & $ISTATE_CURRENT;
				$iflag = " i ";
			}
		} elsif (grep { $_->is_installed() } @pvs) {
			next unless $options{installedstate} & $ISTATE_OUTDATED;
			$iflag = "(i)";
		} elsif (grep { $_->is_installed() } @provs) {
			next unless $options{installedstate} & $ISTATE_CURRENT;
			$iflag = " p ";
			$lversion = ''; # no version for provided
		} else {
			next unless $options{installedstate} & $ISTATE_ABSENT;
			$iflag = "   ";
		}
		
		# Now load the fields
		$vo = $lversion ? $package->get_version($lversion) : 0;
		
		my $description = $vo
			? $vo->get_shortdescription($desclen)
			: '[virtual package]';
		
		if (defined $buildonly) {
			next unless $vo && $vo->param_boolean("builddependsonly");
		}
		if (defined $section) {
			next unless $vo && $vo->get_section($vo) =~ /\Q$section\E/i;
		}
		if (defined $maintainer) {
			next unless $vo && $vo->has_param("maintainer")
				&& $vo->param("maintainer")  =~ /\Q$maintainer\E/i ;
		}
		if ($cmd eq "apropos") {
			next unless $vo;
			my $ok = $vo->has_param("Description")
				&& $vo->param("Description") =~ /\Q$pattern\E/i;
			$ok ||= $vo->get_name() =~ /\Q$pattern\E/i;;
			next unless $ok;
		}			

		my $dispname = $pname;
		if ($namelen && length($pname) > $namelen) {
			# truncate pkg name if wider than its field
			$dispname = substr($pname, 0, $namelen - 3)."...";
		}

		if ($format eq 'dotty' or $format eq 'dotty-build') {
			print "\"$pname\" [shape=box];\n";
			if (ref $vo) {
				# grab the Depends of pkg (not BDep, not others in family)
				for my $dep (@{$vo->get_depends(($format eq 'dotty-build'),0)}) {
					# for each ANDed (comma-sep) chunk...
					for my $subdep (@$dep) {
						# include all ORed items in it
						$subdep =~ /^([+\-.a-z0-9]+)/; # only %n, not versioning
						print "\"$pname\" -> \"$1\";\n";
					}
				}
			}
		} else {
			printf $formatstr,
					$iflag, $pname, $lversion, $description;
		}
	}

	if ($format eq 'dotty' or $format eq 'dotty-build') {
		print "}\n";
	}

	Fink::Status->disable_reload($reload_disable_save);  # restore previous setting
}

sub cmd_listpackages {
	my ($pname, $package);

	foreach $pname (Fink::Package->list_packages()) {
		print "$pname\n";
		$package = Fink::Package->package_by_name($pname);
		if ($package->is_any_installed() or $package->is_provided()) {
			print "YES\n";
		} else {
			print "NO\n";
		}
	}
}

=item aptget_update

  my $success = aptget_update $quiet;

Update the apt-get package database. Returns boolean indicating
whether the update worked within the limits of fink's configs.

=cut

sub aptget_update {
	my $quiet = shift || 0;
	
	return 1 unless $config->binary_requested();  # binary-mode disabled
	return 0 unless apt_available;
	print "Downloading the indexes of available packages in the binary distribution.\n";
	my $aptcmd = aptget_lockwait();
	if ($config->verbosity_level == 0) {
		$aptcmd .= " -qq";
	} elsif ($config->verbosity_level < 2) {
		$aptcmd .= " -q";
	}
	# set proxy env vars
	my $http_proxy = $config->param_default("ProxyHTTP", "");
	if ($http_proxy) {
		$ENV{http_proxy} = $http_proxy;
		$ENV{HTTP_PROXY} = $http_proxy;
	}
	my $ftp_proxy = $config->param_default("ProxyFTP", "");
	if ($ftp_proxy) {
		$ENV{ftp_proxy} = $ftp_proxy;
		$ENV{FTP_PROXY} = $ftp_proxy;
	}
	if (&execute($aptcmd . " update", quiet => $quiet)) {
		print("WARNING: Failure while updating indexes.\n");
		return 0;
	}
	return 1;
}

=item cmd_scanpackages

  $ fink scanpackages [ TREE1 ... ]

Command to update the packages in the given trees.

=cut

sub cmd_scanpackages {
	scanpackages({}, \@_);
	aptget_update;
}

=item scanpackages

  scanpackages $opts, \@trees;

Update the apt-get package database in the given trees.

=cut

sub scanpackages {
	my $opts = shift || { };
	my $trees = shift || [ ];
	
	# Don't scan restrictive if it's unwanted
	if (!exists $opts->{restrictive}
			&& $config->has_param('ScanRestrictivePackages')
			&& !$config->param_boolean('ScanRestrictivePackages')) {
		$opts->{restrictive} = 0;
	}

	# Use lowest verbosity
	if (!exists $opts->{verbosity}) {
		my $v = $config->verbosity_level;
		$v = 1 if $v > 1; # Only allow > 1 if given as an explicit option
		$opts->{verbosity} = $v;
	}
	
	print STDERR "Updating the list of locally available binary packages.\n";
	
	# Run scanpackages
	Fink::Scanpackages->scan_fink($opts, @$trees);
}

### package-related commands

sub cmd_fetch {
	my ($package, @plist);

	my (%options, $norestrictive, $dryrun);
	my @sav = @_;
	%options = &parse_fetch_options("fetch", @_);
	$norestrictive = $options{"norestrictive"} || 0;
	$dryrun = $options{"dryrun"} || 0;

	@_ = @sav;
	if( $dryrun ) {
		shift;
	}
	if( $norestrictive ) {
		shift;
	}

	if( $options{"recursive"} ) {
		shift;
		# if we need the dep engine, may as well let it do *everything* for us
		&real_install($OP_FETCH, 0, 0, $dryrun, @_);
		return;
	}

	@plist = &expand_packages(@_);
	if ($#plist < 0) {
		die "no package specified for command 'fetch'!\n";
	}

	&call_queue_clear;
	foreach $package (@plist) {
		my $pname = $package->get_name();
		if ($norestrictive && $package->get_license() =~ /Restrictive$/i) {
				print "Ignoring $pname due to License: Restrictive\n";
				next;
		}
		&call_queue_add([ $package, 'phase_fetch', 0, $dryrun ]);
	}
	&call_queue_clear;
}

sub parse_fetch_options {
	my $cmd = shift;
	my %options = map { $_ => 0 } qw(norestrictive dryrun recursive);
	
	get_options($cmd, [
	 	[ 'ignore-restrictive|i'	=> \$options{norestrictive},
	 		'Do not fetch sources for packages with a "Restrictive" license. ' .
	 		'Useful for mirroring.' ],
		[ 'dry-run|d'				=> \$options{dryrun},
			'Prints filename, checksum, list of source URLs, maintainer for each ' .
			'package.' ],
		[ 'recursive|r'				=> \$options{recursive},
			'Fetch dependent packages also.' ],
	], \@_);
	return %options;
}

#This sub is currently only used for bootstrap. No command line parsing needed
sub cmd_fetch_missing {
	my @plist;

	@plist = &expand_packages(@_);
	if ($#plist < 0) {
		die "no package specified for command 'cmd_fetch_missing'!\n";
	}
	&call_queue_clear;
	map { &call_queue_add([ $_, 'phase_fetch', 1, 0 ]) } @plist;
	&call_queue_clear;
}

sub cmd_fetch_all {
	&do_fetch_all("fetch-all", @_);
}

sub cmd_fetch_all_missing {
	&do_fetch_all("fetch-missing", @_);
}

sub do_fetch_all {
	my $cmd = shift;
	my ($pname, $package, $version, $vo);
	
	my (%options, $norestrictive, $missing_only, $dryrun);
	%options = &parse_fetch_options($cmd, @_);
	$norestrictive = $options{"norestrictive"} || 0;
	$missing_only = $cmd eq "fetch-missing";
	$dryrun = $options{"dryrun"} || 0;

	if ($options{"recursive"}) {
		print "fetch_all already fetches everything; --recursive is meaningless\n";
	}

	&call_queue_clear;
	foreach $pname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pname);
		$version = &latest_version($package->list_versions());
		$vo = $package->get_version($version);
		if (defined $vo) {
			if ($norestrictive && $vo->get_license() =~ m/Restrictive$/i) {
				print "Ignoring $pname due to License: Restrictive\n";
				next;
			}
			&call_queue_add([
				sub {
					eval {
						$_[0]->phase_fetch($_[1], $_[2]);
					};
					warn "$@" if $@;				 # turn fatal exceptions into warnings
				},
				$vo, $missing_only, $dryrun ]);
		}
	}
	&call_queue_clear;
}

=item cmd_description

  cmd_description @pkgspecs;

Print the description of the given packages.

=cut

sub cmd_description {
	my ($package, @plist);

	@plist = &expand_packages({ provides => 'return' }, @_);
	if ($#plist < 0) {
		die "no package specified for command 'description'!\n";
	}

	print "\n";
	foreach $package (@plist) {
		if ($package->isa('Fink::Package')) {
			$package->print_virtual_pkg;
		} else {
			print $package->get_fullname().": ";
			print $package->get_description();
			if ($package->param_boolean("BuildDependsOnly")) {
				print " .\n Note: This package contains compile-time files only.\n";
			}
			if ($package->is_obsolete()) {
				my $depends_field = $package->pkglist_default('Depends','');
				$depends_field =~ s/(\A|,)\s*fink-obsolete-packages(\(|\s|,|\Z)/"$1$2" eq ",," && ","/e;

				print " .\n";
				print " Note: This package is obsolete. Maintainers should upgrade their\n";
				print " package dependencies to use its replacement, which is probably:\n";
				print " $depends_field\n";
			}
		}
		print "\n";
	}
}

sub cmd_remove {
	my $recursive;
	
	get_options('remove', [
		[ 'recursive|r' => \$recursive,
			'Also remove packages that depend on the package(s) to be removed.' ],
	], \@_, helpformat => "%intro{[options] [package(s)]}\n%all{}\n");

	if ($recursive) {
		if (&execute("$basepath/bin/apt-get 1>/dev/null 2>/dev/null", quiet=>1)) {
			&print_breaking("ERROR: Couldn't call apt-get, which is needed for ".
			    "the recursive option. Try to install the 'apt' Fink package ".
			    "(with e.g. 'fink install apt').");
			die "Purge not performed!\n";
		}
		my @packages = get_pkglist("remove --recursive", @_);
		Fink::PkgVersion::phase_deactivate_recursive(@packages);
	}
	else {
		my @packages = get_pkglist("remove", @_);
		Fink::PkgVersion::phase_deactivate([@packages]);
	}
}

sub get_pkglist {
	my $cmd = shift;
	my ($package, @plist, $pname, @selected, $pattern, @packages);
	my ($buildonly, $po);
	
	get_options($cmd, [
		[ 'buildonly|b'	=> \$buildonly, "Only packages which are Build Depends Only" ],
	], \@_, helpformat => "%intro{[options] [string]}\n%all{}\n");
			
	Fink::Package->require_packages();
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
		
		# Can only remove/purge installed pkgs
		my ($vers) = $package->list_installed_versions();		
		unless (defined $vers) {
			print "WARNING: $pname is not installed, skipping.\n";
			next;
		}
		my $pv = $package->get_version($vers);
		
		# Can't purge or remove virtuals (but status packages are ok!)
		if ($pv->is_type('dummy') && $pv->get_subtype('dummy') eq 'virtual') {
			print "WARNING: $pname is a virtual package, skipping.\n";
		}

		# shouldn't be able to remove or purge essential pkgs
		if ($pv->param_boolean('essential')) {
			print "WARNING: $pname is essential, skipping.\n";
			next;
		}

		if (defined $buildonly) {
			next unless ( $pv->param_boolean("builddependsonly") );
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
		my $pkgcount = $#packages + 1;
		my $prompt = "Fink will attempt to $cmd $pkgcount package" .
			( $pkgcount > 1 ? "s" : "" ) .
			"\n\n" .
			"Do you want to continue?";
		my $answer = &prompt_boolean($prompt, default => 1);
		if (! $answer) {
			die "$cmd not performed!\n";
		}
	}

	return @packages;
}

sub cmd_purge {
	my $recursive;
	get_options('remove', [
		[ 'recursive|r' => \$recursive,
			'Also remove packages that depend on the package(s) to be removed.' ],
	], \@_, helpformat => "%intro{[options] [package(s)]}\n%all{}\n");

	print "WARNING: this command will remove the package(s) and remove any\n";
	print "         global configure files, even if you modified them!\n\n";
 
	my $answer = &prompt_boolean("Do you want to continue?", default => 1);
	if (! $answer) {
		die "Purge not performed!\n";
	}
	
	if ($recursive) {
		if (&execute("$basepath/bin/apt-get 1>/dev/null 2>/dev/null", quiet=>1)) {
			&print_breaking("ERROR: Couldn't call apt-get, which is needed for ".
			    "the recursive option. Try to install the 'apt' Fink package ".
			    "(with e.g. 'fink install apt').");
			die "Purge not performed!\n";
		}
		my @packages = get_pkglist("purge --recursive", @_);
		Fink::PkgVersion::phase_purge_recursive(@packages);
	}
	else {
		my @packages = get_pkglist("purge", @_);
		Fink::PkgVersion::phase_purge([@packages]);
	}
}

sub cmd_validate {
	my ($filename, @flist);

	my ($val_prefix);
	my $pedantic = 1;
	
	get_options('validate', [
		[ 'prefix|p=s'	=> \$val_prefix, "Simulate an alternate Fink prefix (%p) in files." ],
		[ 'pedantic!'	=> \$pedantic, "Display even the most nitpicky warnings (default)." ],
	], \@_);
	
	Fink::Config::set_options( { "Pedantic" => $pedantic } );

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
			print "Error: don't know how to validate $filename!\n";
		}
	}
}

sub cmd_cleanup {
	# TODO - option that steers which file to keep/delete: keep all
	#        files that are refered by any .info file vs keep only
	#        those refered to by the current version of any package,
	#        etc. Delete all .deb and delete all src? Not really
	#        needed, this can be achieved each with single line CLI
	#        commands.

	my(%opts, %modes);
	
	get_options('cleanup', [
		[ 'debs'              => \$modes{debs},
			"Delete .deb (compiled binary package) files." ],
		[ 'sources|srcs'      => \$modes{srcs},	"Delete source files." ],
		[ 'buildlocks|bl'     => \$modes{bl},	"Delete stale buildlock packages." ],
		[ 'dpkg-status'       => \$modes{dpkg},
			"Remove uninstalled packages from dpkg status database." ],
		[ 'obsolete-packages' => \$modes{obs},	"Uninstall obsolete packages." ],
		[ 'all|a'             => \$modes{all},	"All of the above actions." ],
		[ 'keep-src|k'        => \$opts{keep_old},
			"Move old source files to $basepath/src/old/ instead of deleting them." ],
		[ 'dry-run|d'         => \$opts{dryrun},
			"Print the items that would be removed, but do not actually remove them." ],
	], \@_, helpformat => <<HELPFORMAT,
%intro{[mode(s) and options]}
One or more of the following modes must be specified:
%opts{debs,sources,buildlocks,dpkg-status,obsolete-packages,all}

Options:
%opts{keep-src,dry-run,help}

HELPFORMAT
	);

	# use legacy action if no explicit modes given
	# (must not fail...this is how FinkCommander calls it)
	$modes{srcs} = $modes{debs} = 1 if !scalar(grep { $_ } values %modes);
	
	($modes{srcs} || $modes{all}) && &cleanup_sources(%opts);
	($modes{debs} || $modes{all}) && &cleanup_debs(%opts);
	($modes{bl}   || $modes{all}) && &cleanup_buildlocks(%opts, internally=>0);
	($modes{obs}  || $modes{all}) && &cleanup_obsoletes(%opts);
	($modes{dpkg} || $modes{all}) && &cleanup_dpkg_status(%opts);
}

=item cleanup_*

These functions each remove some kind of obsolete files or data
structures. Each function may take one or more options, typically
due to various command-line flags.

=over 4

=item cleanup_sources

    &cleanup_sources(%opts);

Remove files from %p/src that are not listed as a Source or SourceN of
any package in the active Trees of the active Distribution. The
following options are known:

=over 4

=item dryrun

If true, just print the names of the sources, don't actually delete or
move them.

=item keep_old

If true, the files are moved to a subdirectory %p/src/old instead of
actually being deleted.

=back

=cut

sub cleanup_sources {
	my %opts = (dryrun => 0, keep_old => 0, @_);
	Fink::Package->require_packages();
	
	my $srcdir = "$basepath/src";
	my $oldsrcdir = "$srcdir/old";

	my $file_count = 0;
	
	# Iterate over all packages and collect all their source files.
	if ($config->verbosity_level() > 0) {
		print "Collecting active source filenames...\n";
	}
	my %src_list = ();
	foreach my $pname (Fink::Package->list_packages()) {
		my $package = Fink::Package->package_by_name($pname);
		foreach my $vo ($package->get_all_versions()) {
			next if $vo->is_type('dummy');  # Skip dummy packages
			foreach my $suffix ($vo->get_source_suffixes()) {
				$src_list{$vo->get_tarball($suffix)} = 1;
			}
		}
	}

	# Remove obsolete source files. We do not delete immediatly
	# because that will confuse readdir().
	# can't use File::Find here...has no maxdepth setting:(
	my @old_src_files = ();
	my $file;
	opendir(DIR, $srcdir) or die "Can't access $srcdir: $!";
	while (defined($file = readdir(DIR))) {
		# Collect sources that are not in use
		push @old_src_files, $file if not $src_list{$file};
	}
	closedir(DIR);

	if ($opts{keep_old} && !$opts{dryrun}) {
		unless (-d $oldsrcdir) {
			mkdir($oldsrcdir) or die "Can't create $oldsrcdir: $!";
		}
	}

	my $print_it = $opts{dryrun} || $config->verbosity_level() > 1;

	my $verb;
	if ($opts{dryrun}) {
		$verb = 'Obsolete';
	} elsif ($opts{keep_old}) {
		$verb = 'Moving obsolete';
	} else {
		$verb = 'Removing obsolete';
	}

	foreach my $file (sort @old_src_files) {
		# For now, do *not* remove directories - this could easily kill
		# a build running in another process. In the future, we might want
		# to add a --dirs switch that will also delete directories.
		if (-f "$srcdir/$file") {
			print "$verb source: $srcdir/$file\n" if $print_it;
			if (!$opts{dryrun}) {
				if ($opts{keep_old}) {
					rename("$srcdir/$file", "$oldsrcdir/$file") and $file_count++;
				} else {
					unlink "$srcdir/$file" and $file_count++;
				}
			}
		}
	}
	if (!$opts{dryrun}) {
		print 'Obsolete sources ',
			  ($opts{keep_old} ? "moved to $oldsrcdir" : "deleted from $srcdir"),
			  ": $file_count\n\n";
	}
}

=item cleanup_debs

Remove .deb from the Distribution that are not associated with package
descriptions in the active Trees of the current Distribution. Also
remove the symlinks from %p/fink/debs to these files, and any other
dangling symlinks that may be present. If we are in UsebinaryDist
mode, also remove .deb from apt's download cache. The following option
is known:

=over 4

=item dryrun

Just print the names of the .deb files, don't actually delete them.
Skip the symlink check. Pass --dry-run to apt-cache when removing
obsolete downloaded .deb.

=back

=cut

sub cleanup_debs {
	my %opts = (dryrun => 0, @_);

	return if $config->mixed_arch(message=>'cleanup .deb archives');
	my $debarch = $config->param('Debarch');

	Fink::Package->require_packages();

	my $file_count;

	# Handle obsolete debs (files matching the glob *.deb that are not
	# associated with an active package description)
	# .deb filename format is "%n_%v-%r_$platform-$arch.deb"
	my $kill_obsolete_debs = <<'EOFUNC';
		sub {
			# parse apart filename according to .deb spec
			my @atoms = /^(.*)_(.*)_$debarch\.deb$/;
			if (@atoms == 2) {

				# check if that %n at that %v-%r exists
				my $deb_in_database = 0;
				my $package = Fink::Package->package_by_name($atoms[0]);
				if (defined $package) {
					$deb_in_database = 1 if grep /^(\d+:|)\Q$atoms[1]\E$/, $package->list_versions();
				}

				# no pdb entry for the .deb file
				if (not $deb_in_database) {
					print "REMOVE deb: $File::Find::fullname\n";  # PRINT_IT
					unlink $File::Find::fullname and $file_count++;  # UNLINK_IT
				}
			}
		}
EOFUNC
	$opts{dryrun}
		? $kill_obsolete_debs =~ s/REMOVE/Obsolete/
		: $kill_obsolete_debs =~ s/REMOVE/Removing obsolete/;
	$kill_obsolete_debs =~ s/.*PRINT_IT// unless $opts{dryrun} || $config->verbosity_level() > 1;
	$kill_obsolete_debs =~ s/.*UNLINK_IT// if $opts{dryrun};
	$kill_obsolete_debs = eval $kill_obsolete_debs;
#	use B::Deparse;
#	my $deparser = new B::Deparse;
#	print "sub ", $deparser->coderef2text($kill_obsolete_debs), "\n";
	if ($config->verbosity_level() > 0) {
		print "Scanning deb collection...\n";
	}
	$file_count = 0;
	find ({'wanted' => $kill_obsolete_debs, 'follow' => 1}, "$basepath/fink/dists");
	if (!$opts{dryrun}) {
		print "Obsolete deb packages ",
			  ($opts{dryrun} ? "found in" : "deleted from"),
			  " fink trees: $file_count\n\n";
	}
	
	if ($opts{dryrun}) {
		print "Skipping symlink cleanup in dryrun mode\n";
	} else {
		# Remove broken symlinks in %p/fink/debs, such as ones pointing to
		# the to the .deb files we just deleted
		my $kill_broken_links = sub {
			if(-l && !-e) {
				unlink $File::Find::name and $file_count++;
			}
		};
		$file_count = 0;
		find ($kill_broken_links, "$basepath/fink/debs");
		print "Obsolete symlinks deleted: $file_count\n\n";
	};

	if ($config->binary_requested()) {
		# Delete obsolete .deb files in $basepath/var/cache/apt/archives using 
		# 'apt-get autoclean'
		my $aptcmd = aptget_lockwait() . " ";
		if ($config->verbosity_level() == 0) {
			$aptcmd .= "-qq ";
		}
		elsif ($config->verbosity_level() < 2) {
			$aptcmd .= "-q ";
		}
		if($opts{dryrun}) {
			$aptcmd .= "--dry-run ";
		}
		my $apt_cache_path = "$basepath/var/cache/apt/archives";
		my $deb_regexp = "\\.deb\$";
		my $files_before_clean = &count_files($apt_cache_path, $deb_regexp);

		if (&execute($aptcmd . "--option APT::Clean-Installed=false autoclean")) {
			print("WARNING: Cleaning deb packages in '$apt_cache_path' failed.\n");
		}
		if (!$opts{dryrun}) {
			print "Obsolete deb packages deleted from apt cache: ",
				  $files_before_clean - &count_files($apt_cache_path, $deb_regexp),
				  "\n\n";
		}

		if ($opts{dryrun}) {
			print "Skipping scanpackages and in dryrun mode\n";
		} else {
			if (apt_available) {
				scanpackages({ verbosity => 0 });
				aptget_update(1);
			}
		}
	}
}

=item cleanup_buildlocks

Search for all installed lockpkgs. Optionally have lockpkgs remove
themselves. Returns a boolean indicating whether there are any active
buildlocks still present after cleanup. The following options are known:

=over 4

=item dryrun

If true, don't actually remove things.

=item internally

Set to true if being called implicitly or for automatic cleanup. Set
to false (or omit) if being called explicitly by the user (for
example, by 'fink cleanup').

=back

=cut

sub cleanup_buildlocks {
	my %opts = (dryrun => 0, internally => 0, @_);

	return 1 if Fink::Config::get_option("no_buildlock");

	print "Reading buildlock packages...\n";
	my $lockdir = "$basepath/var/run/fink/buildlock";
	my @files;
	if (opendir my $dirhandle, $lockdir) {
		@files = readdir $dirhandle;
		close $dirhandle;
	} else {
		print "Warning: could not read buildlock directory $lockdir: $!\n";
	}
	
	# Find the files that are really locks
	my @bls;
	my ($LOCKS_NONE, $LOCKS_PRESENT, $LOCKS_IN_USE) = 0..2; 
	my $locks_left = $LOCKS_NONE;
	for my $file (@files) {
		# lock packages are named fink-buildlock-%n-%v-%r. They install
		# %n-%v-%r.pid and have a lockfile %n-%v-%r_$timestamp.lock
		my ($fullv) = ($file =~ /(.+)_.+\.lock$/) or next;
		my $lockfile = "$lockdir/$file";
		my $pidfile = "$lockdir/$fullv.pid";
		my $lockpkg = "fink-buildlock-$fullv";
		next unless -f $pidfile;
		
		# We have a lock, and the package seems to be installed
		$locks_left = $LOCKS_PRESENT;

		# Check that it's not currently building, hoepfully we won't have
		# to invoke dpkg.
		if (my $fh = Fink::Finally::Buildlock->can_remove($lockfile)) {
			push @bls, $lockpkg;
			close $fh;	# Another process could try to remove the BL between
						# now and when we actually perform the removal. That's
						# fine, dpkg-lockwait shall protect us.
		} else {
			$locks_left = $LOCKS_IN_USE; # Something is building
		}
	}
	
	# Remove the locks
	if (@bls) {
		if ($opts{dryrun}) {
			print map "\t$_\n", @bls if $config->verbosity_level() > 1;
		} else {
			print map "\tWill remove $_\n", @bls
				if $config->verbosity_level() > 1;
			if (&execute(dpkg_lockwait() . " -r @bls 2>/dev/null",
												quiet => 1, ignore_INT => 1)) {
				print $opts{internally}
					? "Some buildlocks could not be removed.\n"
					: "Warning: could not remove all buildlock packages!\n";
			} else {
				$locks_left = $LOCKS_NONE if $locks_left == $LOCKS_PRESENT;
			}
			Fink::PkgVersion->dpkg_changed;
		}
	} else {
		print "\tAll buildlocks accounted for.\n"
			if $opts{dryrun} || $config->verbosity_level() > 1;
	}

	return $locks_left;
}

=item cleanup_obsoletes

Search for all installed packages that are tagged "obsolete" and
attempt to remove them. Returns a boolean indicating whether there any
obsolete packages that were not removed. The following option is
known:

=over 4

=item dryrun

If true, don't actually remove them.

=back

=cut

sub cleanup_obsoletes {
	my %opts = (dryrun => 0, @_);

	my %obsolete_pkgs = ();  # NAME=>PkgVersion-object
	my ($maxlen_name, $maxlen_vers) = (0, 0);

	# start with all packages in dpkg status db (likely to be
	# installed, so more efficient than starting with package
	# database) as ref to hash of NAME=>{fields hash}
	my $status_pkgs = Fink::Status->list();
	
	# get installed version of each as hash of NAME=>VERSION
	my %installed = map { $_ => Fink::Status->query_package($_) } keys %$status_pkgs;

	# find the obsolete ones
	Fink::Package->require_packages();
	foreach my $name (sort keys %installed) {
		my $vers = $installed{$name};  # actually %v-%r
		next unless defined $vers && length $vers;

		# found an installed package...check if it's obsolete

		# more efficient to do brute-force regex on Status data
		# instead of locating PV object and using formal API there
		my $depends_field = $status_pkgs->{$name}->{depends};
		next unless defined $depends_field;
		next unless $depends_field =~ /(\A|,)\s*fink-obsolete-packages(\(|\s|,|\Z)/;

		# track longest package name and version string
		$maxlen_name = length $name if length $name > $maxlen_name;
		$maxlen_vers = length $vers if length $vers > $maxlen_vers;

		$obsolete_pkgs{$name} = $status_pkgs->{$name};
	}

	my $err = 'The following ' . scalar(keys %obsolete_pkgs) . ' obsolete package(s) ';
	$err .= ($opts{dryrun} ? 'would' : 'will');
	$err .= ' be removed:';
	&print_breaking("\n$err");
	foreach my $name (sort keys %obsolete_pkgs) {
		printf "   %${maxlen_name}s  %${maxlen_vers}s  %s\n", $name, $obsolete_pkgs{$name}->{version}, $obsolete_pkgs{$name}->{description};
	}
	print "\n";

	my $problems = 0;
	if (%obsolete_pkgs) {
		my $cmd = dpkg_lockwait() . ' --purge ';
		$cmd .= '--dry-run ' if $opts{dryrun};
		$problems = 1 if &execute($cmd . (join ' ', sort keys %obsolete_pkgs), ignore_INT => 1);
	}

	if ($problems) {
		&print_breaking("\nWARNING: not all obsolete packages could be removed.");
	} elsif (!$opts{dryrun}) {
		# all obsoletes removed, so remove the fink-obsolete-packages sentinel itself
		&execute(dpkg_lockwait() . ' --purge fink-obsolete-packages', ignore_INT => 1);
	}

	return $problems;
}

=item cleanup_dpkg_status

Remove entries for purged packages from the dpkg "status" database. A
backup of the original file is kept in the same location with a
timestamp in its filename. Standard dpkg-compatible locking of the
database file is used to prevent race conditions or other concurrency
problems that could result in file corruption. The following option is
known:

=over 4

=item dryrun

If true, don't actually remove them.

=back

=cut

sub cleanup_dpkg_status {
	my %opts = (dryrun => 0, @_);

	my $cmd = $basepath . '/sbin/fink-dpkg-status-cleanup';
	$cmd .= ' --dry-run' if $opts{dryrun};

	return &execute($cmd, ignore_INT=>1);
}

=back

=cut

### building and installing

sub cmd_build {
	&real_install($OP_BUILD, 0, 0, 0, @_);
}

sub cmd_rebuild {
	&real_install($OP_REBUILD, 0, 0, 0, @_);
}

sub cmd_install {
	&real_install($OP_INSTALL, 0, 0, 0, @_);
}

sub cmd_reinstall {
	&real_install($OP_REINSTALL, 0, 0, 0, @_);
}

sub cmd_update_all {
	my (@plist, $pname, $package);

	foreach $pname (Fink::Package->list_packages()) {
		$package = Fink::Package->package_by_name($pname);
		if ($package->is_any_installed()) {
			push @plist, $pname;
		}
	}

	&real_install($OP_INSTALL, 1, 0, 0, @plist);
}

use constant PKGNAME => 0;
use constant PKGOBJ  => 1;  # $item->[1] unused?
use constant PKGVER  => 2;
use constant OP      => 3;
use constant FLAG    => 4;

our %validated_info_files = ();  # keys are filenames that have been checked

sub real_install {
	my $op = shift;
	my $showlist = shift;
	my $forceoff = shift; # check if this is a secondary loop
	my $dryrun = shift;
		
	my ($pkgspec, $package, $pkgname, $item, $dep);
	my ($all_installed, $any_installed);
	my (%deps, @queue, @deplist, @requested, @additionals);
	my ($answer, $s);
	my (%to_be_rebuilt, %already_activated);

	# if we only want to fetch, run the engine in mode=build, but
	# abort before doing any actual building
	my $fetch_only = 0;
	if ($op == $OP_FETCH) {
		$fetch_only = 1;
		$op = $OP_BUILD;
	}

	# correct verb tense for actions
	my $to_be = ( $fetch_only || $dryrun
				  ? 'would be'
				  : 'will be'
				  );

	my $verbosity = $config->verbosity_level();
	$showlist = 1 if $verbosity > -1;

	%deps = ();		# hash by package name

	%to_be_rebuilt = ();
	%already_activated = ();

	# should we try to download the deb from the binary distro?
	# warn if UseBinaryDist is enabled and not installed in '/sw'
	my $deb_from_binary_dist = 0;
	if ($config->binary_requested()) {
		if (my $err = $config->bindist_check_prefix) {
			print "\n";	print_breaking("WARNING: $err");
		} else {
			$deb_from_binary_dist = 1;
		}
	}

	# don't bother doing this on point release, of course it's out-of-date  ;)
	if ($config->param_default("SelfUpdateMethod", "point") ne "point") {
		my $up_to_date_text;

		require Fink::SelfUpdate;
		my ($method, $timestamp, $data) = &Fink::SelfUpdate::last_done;
		if ($timestamp) {
			my $age = (time-$timestamp) / (60*60*24);  # days since last selfupdate
			if ($age > 14) {
				$up_to_date_text = "your info file index has not been updated for " . int($age) . " days.";
			}
		} else {
			$up_to_date_text = "unable to determine last selfupdate time.";
		}

		if (defined $up_to_date_text) {
			my $oldindexes = lc(Fink::Config::get_option("OldIndexes", "warn"));
			if ($oldindexes !~ /^(ignore|update|warn)$/) {
				$oldindexes = 'warn';
				print_breaking_stderr "WARNING: unknown value for 'OldIndexes' in fink.conf: $oldindexes";
			}
			
			if ($oldindexes eq "warn") {
				print_breaking_stderr "WARNING: $up_to_date_text You should run 'fink selfupdate' to get the latest package descriptions.\n";
			} elsif ($oldindexes eq "update") {
				print_breaking_stderr "WARNING: $up_to_date_text Fink will now update it automatically.";
				require Fink::SelfUpdate;
				Fink::SelfUpdate::check();
			}
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

		# pedantically validate .info of explicitly requested packages
		if (Fink::Config::get_option("validate")) {
			# Can't validate virtuals
			if ($package->is_type('dummy') && $package->get_subtype('dummy') eq 'virtual') {
				print "Package '" . $package->get_name() . "' is a virtual package, skipping validation.\n";
			} elsif ($package->is_type('dummy') && $package->get_info_filename() eq '') {
				print "Package '" . $package->get_name() . "' is a dummy package without info file, skipping validation.\n";
			} else {
				my $info_filename = $package->get_info_filename();
				if (not $validated_info_files{$info_filename}++) {
					my %saved_options = map { $_ => Fink::Config::get_option($_) } qw/ verbosity Pedantic /;
					Fink::Config::set_options( {
						'verbosity' => 3,
						'Pedantic'  => 1
											   } );
					if(!Fink::Validation::validate_info_file($info_filename)) {
						if(Fink::Config::get_option("validate") eq "on") {
							die "Please correct the above problems and try again!\n";
						} else {
							warn "Validation of .info failed.\n";
						}
					}
					Fink::Config::set_options(\%saved_options);
				}
			}
		}

		# no duplicates here
		#	 (dependencies is different, but those are checked later)
		$pkgname = $package->get_name();
		if (exists $deps{$pkgname}) {
			print "Duplicate request for package '$pkgname' ignored.\n";
			next;
		}
		# skip if this version/revision is installed
		#	 (also applies to update)
		if ($op != $OP_REBUILD and $op != $OP_REINSTALL
				and $package->is_installed()) {
			next;
		}

		# for build, also skip if present, but not installed
		if ($op == $OP_BUILD and $package->is_locally_present()) {
			next;
		}
		# if asked to reinstall but have no .deb, have to rebuild it
		if ($op == $OP_REINSTALL and not $package->is_present()) {
			if ($verbosity > 2) {
				printf "No .deb found so %s must be rebuilt\n", $package->get_fullname();
			}
			$op = $OP_REBUILD;
		}
		# add to table
		@{$deps{$pkgname}}[ PKGNAME, PKGOBJ, PKGVER, OP, FLAG ] = (
			$pkgname, Fink::Package->package_by_name($pkgname),
			$package, $op, 1
		);
		$to_be_rebuilt{$pkgname} = ($op == $OP_REBUILD || $op == $OP_BUILD);
	}

	@queue = sort keys %deps;
	if ($#queue < 0) {
		unless ($forceoff) {
			print "No packages to install.\n";
		}
		return;
	}

	# recursively expand dependencies
	my %ok_versions;	# versions of each pkg that are ok to use
	my %conflicts;		# pkgname => list of conflicts
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
		my @con_lol;
		if ($item->[OP] == $OP_BUILD or
				($item->[OP] == $OP_REBUILD and not $item->[PKGVER]->is_installed())) {
			# We are building an item without going to install it
			# -> only include pure build-time dependencies
			if ($verbosity > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' $to_be built without being installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(2, "Depends", $forceoff);
			@con_lol = $item->[PKGVER]->resolve_depends(2, "Conflicts", $forceoff);
		} elsif ((not $item->[PKGVER]->is_present() 
		  and not ($deb_from_binary_dist and $item->[PKGVER]->is_aptgetable()))
		  or $item->[OP] == $OP_REBUILD) {
			# We want to install this package and have to build it for that
			# -> include both life-time & build-time dependencies
			if ($verbosity > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' $to_be built and installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(1, "Depends", $forceoff);
			@con_lol = $item->[PKGVER]->resolve_depends(1, "Conflicts", $forceoff);
		} elsif (not $item->[PKGVER]->is_present() and $item->[OP] != $OP_REBUILD 
		         and $deb_from_binary_dist and $item->[PKGVER]->is_aptgetable()) {
			# We want to install this package and will download the .deb for it
			# -> only include life-time dependencies
			if ($verbosity > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' $to_be downloaded as a binary package and installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(0, "Depends", $forceoff);
			
			# Do not use BuildConflicts for packages which are not going to be built!
		} else {
			# We want to install this package and already have a .deb for it
			# -> only include life-time dependencies
			if ($verbosity > 2) {
				print "The package '" . $item->[PKGVER]->get_name() . "' $to_be installed.\n";
			}
			@deplist = $item->[PKGVER]->resolve_depends(0, "Depends", $forceoff);
			
			# Do not use BuildConflicts for packages which are not going to be built!
		}
		
		foreach $dep (@deplist) {
			choose_pkgversion(\%deps, \@queue, $item, \%ok_versions, @$dep);
		}	
		$conflicts{$pkgname} = [ map { @$_ } @con_lol ];
	}

	# generate summary
	@requested = ();
	@additionals = ();

	my $willbuild = 0;  # at least one new package will be compiled probably
	my $bad_infos = 0;  # at least one .info failed validation
	foreach $pkgname (sort keys %deps) {
		$item = $deps{$pkgname};
		if ($item->[FLAG] == 0) {
			push @additionals, $pkgname;
		} elsif ($item->[FLAG] == 1) {
			push @requested, $pkgname;
		}
		if ($item->[OP] == $OP_REBUILD || $item->[OP] == $OP_BUILD || 
		    (not $item->[PKGVER]->is_present() and not($deb_from_binary_dist and $item->[PKGVER]->is_aptgetable()))) {
			unless (($item->[OP] == $OP_INSTALL and $item->[PKGVER]->is_installed())) {
				$willbuild = 1;
				$to_be_rebuilt{$pkgname} = 1;

				# validate the .info if desired
				# only use default level for dependencies of explicit packages
				# (explicitly requested pkgs were severely validated earlier)
				if (Fink::Config::get_option("validate")) {
					my $info_filename = $item->[PKGVER]->get_info_filename();
					if (not $validated_info_files{$info_filename}++) {
						my %saved_options = map { $_ => Fink::Config::get_option($_) } qw/ Pedantic /;
						Fink::Config::set_options( {
							'Pedantic'  => 0
												   } );
						$bad_infos = 1 unless Fink::Validation::validate_info_file($info_filename);
						Fink::Config::set_options(\%saved_options);
					}
				}
			}
		}
	}
	if($bad_infos) {
		if(Fink::Config::get_option("validate") eq "on") {
			die "Please correct the above problems and try again!\n";
		} else {
			warn "Validation of .info failed.\n";
		}
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
		$s .= " $to_be ";
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
		# find the packages we're likely to remove
		my @removals = list_removals(\%deps, \%conflicts);
		
		# ask user when additional packages are to be installed
		if ($#additionals >= 0 || @removals) {
			if ($#additionals >= 0 and not $fetch_only) {
				if ($#additionals > 0) {
					&print_breaking("The following ".scalar(@additionals).
							" additional packages $to_be installed:");
				} else {
					&print_breaking("The following additional package ".
							"$to_be installed:");
				}
				&print_breaking(join(" ",@additionals), 1, " ");
			}
			if (@removals and not $fetch_only) {
				my $number = scalar(@removals) > 1
					? (scalar(@removals) . " packages") : "package";
				&print_breaking(
					"The following $number might be temporarily removed:");
				&print_breaking(join(" ",@removals), 1, " ");
			}
			if (not $dryrun) {
				$answer = &prompt_boolean("Do you want to continue?",
						  				  default => 1);
				if (! $answer) {
					die "Package requirements not satisfied\n";
				}
			}
		}
	}
	
	# Pre-fetch all the stuff we'll need
	prefetch($deb_from_binary_dist, $dryrun, values %deps);

	# if we were really in fetch or dry-run modes, stop here
	return if $fetch_only || $dryrun;

	# cross-building is not supported yet because we don't have a
	# generic way to pass the arch info to the compiler
	$config->mixed_arch(message=>'build or install/remove binary packages', fatal=>1);

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
				foreach $pkgg ($package->get_relatives){
					$pkggname = $pkgg->get_name();
					if ($pkggname eq $dppname) {
						$isgood = 0;
					} 
				}
				push @extendeddeps, $deps{$dppname} if $isgood;
			}

			foreach $pkg ($package->get_relatives) {
				my $name = $pkg->get_name();
				if (exists $deps{$name}) {
					foreach $dpp (@{$deps{$name}}[5..$#{$deps{$name}}]) {
						$isgood = 1;
						$dppname = $dpp->[PKGNAME];
						foreach $pkgg ($package->get_relatives){
							$pkggname = $pkgg->get_name();
							if ($pkggname eq $dppname) {
								$isgood = 0;
							} 
						}
						push @extendeddeps, $deps{$dppname} if $isgood;
					}
				}
			}

			# check dependencies
			next PACKAGELOOP if grep { ($_->[FLAG] & 2) == 0 } @extendeddeps;
			
			### switch debs during long builds
			foreach $dep (@extendeddeps) {
				if (!$dep->[PKGVER]->is_installed()) {
					### If the deb exists, we install it without asking.
					### If it doesn't exist, we allow the process to continue
					### (it will quit with an error, and the user must then
					### start over)
					if ($dep->[PKGVER]->is_present()) {
						Fink::PkgVersion::phase_activate([$dep->[PKGVER]]);
					}
				}
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

			if (not $to_be_rebuilt{$pkgname}) {
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
				foreach $pkg ($package->get_relatives) {
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

				{
					my $rebuild_count = 0;
					for my $pkgname (keys %to_be_rebuilt) {
						if (not exists $deps{$pkgname}) {
							$rebuild_count++;
						} else {
							my $p = $deps{$pkgname}->[PKGVER];
							if (not defined $p or not $p->has_parent) {
								$rebuild_count += $to_be_rebuilt{$pkgname};
							}
						}
					}
					# FIXME: factor out a standard Xterm notifier with
					# new event types
					my $use_xttitle = grep { /^xterm$/i } split / /, $config->param_default('NotifyPlugin', 'Growl');
					print "\033]2;building " . $package->get_fullname . " (" . ($rebuild_count - 1) . " remaining)\007" if $use_xttitle;
				}

				unless ($forceoff) {
					### Double check it didn't already get
					### installed in an other loop
					if (!$package->is_installed() || $op == $OP_REBUILD) {
						# Remove the BuildConflicts, and reinstall after
						my $buildconfs = Fink::Finally::BuildConflicts->new(
							$conflicts{$pkgname});

						$package->log_output(1);
						{
							my $bl = Fink::Finally::Buildlock->new($package);
							$package->phase_unpack();
							$package->phase_patch();
							$package->phase_compile();
							$package->phase_install();
							$package->phase_build();
						}
						$package->log_output(0);
					} else {
						&real_install($OP_BUILD, 0, 1, $dryrun,
							$package->get_name());
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
			foreach $pkg ($package->get_relatives) {
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

			# Finally perform the actually installation
			Fink::PkgVersion::phase_activate([@batch_install]) unless (@batch_install == 0);

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

=item expand_packages

  my @pkglist = expand_packages @pkgspecs;
  my @pkglist = expand_packages $opts, @pkgspecs;

Expand a list of package specifications into objects. Options are the same
as for Fink::PkgVersion::match_package.

=cut

sub expand_packages {
	my ($pkgspec, $package, @package_list);
	my $opts = ref($_[0]) ? shift : {};
	
	@package_list = ();
	foreach $pkgspec (@_) {
		$package = Fink::PkgVersion->match_package($pkgspec, %$opts);
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

	my (@fields, @percents, @env_vars, $wantall);
	
	get_options('dumpinfo', [
		[ 'all|a'		=> \$wantall,	"All package info fields (default behavior)."		],
		[ 'field|f=s'	=> \@fields,	"Just the specific field(s) specified."				],
		[ 'percent|p=s'	=> \@percents,	"Just the percent expansion for specific key(s)."	],
		[ 'env|e=s'		=> \@env_vars,	"Just the specific environment variable(s), in a format that can be 'eval'ed."	],
	], \@_, helpformat => <<HELPFORMAT);
%intro{[options] [package(s)]}
%all{}

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
  trees        - Trees in which this package (same version) exists.

The "_" environment variable is interpretted to mean "the whole
environment" for the --env mode and the "all" percent-expansion key
is interpretted to mean "all known percent-expansion keys" for the
--percent mode.

HELPFORMAT
	
	Fink::Package->require_packages();

	# handle clustered param values
	@fields   = split /,/, lc ( join ',', @fields   ) if @fields;
	@percents = split /,/,    ( join ',', @percents ) if @percents;
	# Need this line to unconfuse emacs perl-mode /,

	my @pkglist = &expand_packages(@_);
	if (! @pkglist) {
		die "fink dumpinfo: no package(s) specified\nType 'fink dumpinfo --help' for more information.\n";
	}

	foreach my $pkg (@pkglist) {
		$pkg->prepare_percent_c;

		# default to all fields if no fields or %expands specified
		if ($wantall or (!@fields and !@percents and !@env_vars)) {
			# don't list fields that cause indexer exclusion
			@fields = (qw/
					   infofile debfile package epoch version revision parent family
					   status allversions trees
					   description type license maintainer
					   pre-depends depends builddepends
					   provides replaces conflicts buildconflicts
					   recommends suggests enhances
					   essential builddependsonly
					   custommirror
					   /);
			foreach ($pkg->get_source_suffixes) {
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
			foreach ($pkg->get_patchfile_suffixes) {
				push @fields, ( "patchfile${_}", "patchfile${_}-md5" );
			}
			push @fields, (qw/
						   updateconfigguess updateconfigguessindirs
						   updatelibtool updatelibtoolindirs
						   updatepomakefile
						   patch patchscript
						   /,
						   $pkg->params_matching("^set"),
						   $pkg->params_matching("^noset"),
						   qw/
						   env
						   configureparams gcc compilescript noperltests
						   updatepod installscript
						   jarfiles docfiles appbundles
						   shlibs runtimevars splitoffs files
						   preinstscript postinstscript
						   prermscript postrmscript
						   conffiles infodocs daemonicname daemonicfile
						   homepage descdetail descusage
						   descpackaging descport
						   testscript
						   /);
		};

		foreach (@fields) {
			if ($_ eq 'infofile') {
				printf "infofile: %s\n", $pkg->get_info_filename();
			} elsif ($_ eq 'debfile') {
				printf "%s: %s\n", $_, join(' ', $pkg->get_debfile());
			} elsif ($_ eq 'package') {
				printf "%s: %s\n", $_, $pkg->get_name();
			} elsif ($_ eq 'epoch') {
				printf "%s: %s\n", $_, $pkg->get_epoch();
			} elsif ($_ eq 'version') {
				printf "%s: %s\n", $_, $pkg->get_version();
			} elsif ($_ eq 'revision') {
				printf "%s: %s\n", $_, $pkg->get_revision();
			} elsif ($_ eq 'parent') {
				printf "%s: %s\n", $_, $pkg->get_parent->get_name() if $pkg->has_parent;
			} elsif ($_ eq 'splitoffs') {
				printf "%s: %s\n", $_, join ', ', map { $_->get_name() } $pkg->parent_splitoffs;
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
				my $pkgname = $pkg->get_name();
				my $package = Fink::Package->package_by_name($pkgname);
				my $lversion = &latest_version($package->list_versions());
				print "$_:\n";
				foreach my $vers (&sort_versions($package->list_versions())) {
					my $pv = $package->get_version($vers);
					printf " %1s%1s\t%s\n",
						( $pv->is_present() or $config->binary_requested() && $pv->is_aptgetable() ) ? "b" : "",
						$pv->is_installed() ? "i" : "",
						$vers;
				}
			} elsif ($_ eq 'description') {
				printf "%s: %s\n", $_, $pkg->get_shortdescription;
			} elsif ($_ =~ /^desc(packaging|port)$/) {
				# multiline field, so indent 1 space always
				# format_description does that for us
				print "$_:\n", Fink::PkgVersion::format_description($pkg->param($_)) if $pkg->has_param($_);
			} elsif ($_ =~ /^desc(detail|usage)$/) {
				# multiline field, so indent 1 space always
				# format_description does that for us
				print "$_:\n", Fink::PkgVersion::format_description($pkg->param_expanded($_, 2)) if $pkg->has_param($_);
			} elsif ($_ eq 'type' or $_ eq 'maintainer' or $_ eq 'homepage') {
				printf "%s: %s\n", $_, $pkg->param_default($_,'[undefined]');
			} elsif ($_ eq 'license') {
				my $license = $pkg->get_license();
				$license = '[undefined]' if not length $license;
				printf "%s: %s\n", $_, $license;
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
				printf "%s: %s\n", $_, $bool unless $pkg->has_parent;
			} elsif ($_ eq 'sources') {
				# multiline field, so indent 1 space always
				my @suffixes = map { $pkg->get_source($_) } $pkg->get_source_suffixes;
				if (@suffixes) {
					print "$_:\n";
					print map { " $_\n" } @suffixes;
				}
			} elsif ($_ =~ /^source(\d*)$/) {
				my $src = $pkg->get_source($1);
				printf "%s: %s\n", $_, $src if defined $src && $src ne "none";
			} elsif ($_ eq 'gcc' or $_ =~ /^source\d*-md5$/) {
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
					 $_ =~ /^set/ or $_ =~ /^jarfiles$/ or
					 $_ =~ /^patch(|\d*file|\d*file-md5)$/ or $_ eq 'appbundles' or
 					 $_ eq 'infodocs' or $_ =~ /^daemonicname$/
					) {
				# singleline fields start on the same line, have
				# embedded newlines removed, and are not wrapped
				if ($pkg->has_param($_)) {
					my $value = $pkg->param_expanded($_);
					$value =~ s/^\s+//m;
					$value =~ s/\n/ /g; # merge into single line
					printf "%s: %s\n", $_, $value;
				}
			} elsif ($_ =~ /^(|conf|doc)files$/) {
				# singleline fields start on the same line, have
				# embedded newlines removed, and are not wrapped
				# need conditionals processing
				if ($pkg->has_param($_)) {
					my $value = $pkg->conditional_space_list(
						$pkg->param_expanded($_),
						"$_ of ".$pkg->get_fullname()." in ".$pkg->get_info_filename
					);
					printf "%s: %s\n", $_, $value if length $value;
				}
			} elsif ($_ eq 'shlibs') {
				# multiline field with specific accessor
				my $value = $pkg->get_shlibs_field();
				if (length $value) {
					$value =~ s/^/ /gm;
					printf "%s:\n%s", $_, $value;
				}
			} elsif ($_ =~ /^(((pre|post)(inst|rm))script)|(runtimevars|custommirror)|daemonicfile$/) {
				# multiline fields start on a new line and are
				# indented one extra space
				if ($pkg->has_param($_)) {
					my $value = $pkg->param_expanded($_);
					$value =~ s/^/ /gm;
					printf "%s:\n%s\n", $_, $value;
				}
			} elsif ($_ =~ /^(patch|compile|install|test)script$/) {
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
			} elsif ($_ eq 'trees') {
				printf "%s: %s\n", $_, join(' ', $pkg->get_full_trees);
			} else {
				die "Unknown field $_\n";
			}
		}
		
		# Allow 'all' for all percents
		if (scalar(@percents) == 1 && $percents[0] eq 'all') {
			# sort them by disctionary ordering (D d I i)
			@percents = sort {lc $a cmp lc $b || $a cmp $b} keys %{$pkg->{_expand}};
		}

		foreach (@percents) {
			s/^%(.+)/$1/;  # remove optional leading % (but allow '%')
			printf "%%%s: %s\n", $_, &expand_percent("\%{$_}", $pkg->{_expand}, "fink dumpinfo " . $pkg->get_name . '-' . $pkg->get_fullversion);
		}


		if (@env_vars) {
			my %pkg_env = %{$pkg->get_env};

			# replace each given "_" sentinel with full variable list
			# go backwards to avoid looping over a just-replaced _
			for (my $i = $#env_vars; $i >= 0; $i--) {
				splice( @env_vars, $i, 1, sort keys %pkg_env) if $env_vars[$i] eq '_';
			}

			foreach my $env_var (@env_vars) {
				if ($_ eq '_') {
					# sentinel for "all env vars"
					foreach (sort keys %pkg_env) {
						printf "%s=%s\n", $_, $pkg_env{$_};
					}
				} elsif (defined $pkg_env{$env_var}) {
					# only print a requested var if it is defined
					printf "%s=%s\n", $env_var, $pkg_env{$env_var};
				} else {
					# requested var not defined...don't print it
					# FIXME: should we print it as blank instead?
				}
			}
		}
	}
}

# display the dependencies "from a user's perspective" of a given package
sub cmd_show_deps {
	my @plist = &expand_packages(@_);
	if ($#plist < 0) {
		die "no package specified for command 'show-deps'!\n";
	}

	print "\n";

	foreach my $pkg (@plist) {
		my @relatives = $pkg->get_relatives;

		printf "Package: %s (%s)\n", $pkg->get_name(), $pkg->get_fullversion();

		print "To install the compiled package...\n";

		print "  The following other packages (and their dependencies) must be installed:\n";
		&show_deps_display_list($pkg, 0, 0);
		
		print "  The following other packages must not be installed:\n";
		&show_deps_display_list($pkg, 0, 1);

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
		&show_deps_display_list($pkg, 1, 0);

		print "  The following other packages must not be installed:\n";
		&show_deps_display_list($pkg, 1, 1);

		print "\n";
	}
}

# pretty-print a set of PkgVersion::pkglist (each "or" group on its own line)
# pass:
#   PkgVersion object
#   $run_or_build (see PkgVersion::get_depends)
#   $dep_of_confl (see PkgVersion::get_depends)
sub show_deps_display_list {
	my $pkg = shift;
	my $run_or_build = shift;
	my $dep_or_confl = shift;

	# get the data
	my $lol = $pkg->get_depends($run_or_build, $dep_or_confl);

	# stringify each OR cluster
	my @results = map { join ' | ', @$_ } grep defined $_, @$lol;

	# organize and display the list of packages
	if (@results) {
		print map "    $_\n", sort @results;
	} else {
		print "    [none]\n";
	}
}

=item choose_package_ask

  my $pkgname = choose_package_ask $candidates;

Ask the user to pick between candidate packages which satisfy a dependency.
This is used as a last resort, if no other selection heuristic has worked.

The parameter $candidates is a list-ref of package names.

=cut

sub choose_package_ask {
	my $candidates = shift;
	
	# Get the choices
	my @pos = map { Fink::Package->package_by_name($_) } @$candidates;

	# shuffle all "obsolete" pkgs to bottom of list
	my(@choices_cur, @choices_obs);
	foreach my $po (@pos) {
		my $pv = $po->get_latest_version;
		my $name = $po->get_name;
		my $desc = $pv->get_shortdescription(60);
		if ($pv->is_obsolete) {
			push @choices_obs, ("$name: (obsolete) $desc" => $name);
		} else {
			push @choices_cur, ("$name: $desc" => $name);
		}
	}
	my @choices = (@choices_cur, @choices_obs);
	
	# If just one package has a deb available, make it the default
	my @have_deb = grep { $_->is_any_present } @pos;
	my $default = scalar(@have_deb == 1)
		? [ "value" => $have_deb[0]->get_name ]
		: [];

	return prompt_selection("Pick one:",
		intro	=> "fink needs help picking an alternative to satisfy a "
			. "virtual dependency. The candidates:",
		choices	=> \@choices,
		default	=> $default,
		category => 'virtualdep',
	);
}

=item choose_filter

  my $result = choose_filter $candidates, $filter;

Find the unique item in a list that matches a given filter.

The parameter $candidates is a list-ref of items to choose from.

The parameter $filter should be a coderef that returns a boolean value
dependent on the value of $_.

If the filter returns true for just one candidate, that candidate is returned.
Otherwise this function returns false, and $candidates is re-ordered so that
matching candidates are earlier than non-matching ones.

=cut

sub choose_filter {
	my ($candidates, $filter) = @_;
	my (@matched, @unmatched);
	
	foreach (@$candidates) {
		if (&$filter()) {
			push @matched, $_;
		} else {
			push @unmatched, $_;
		}
	}
	if (@matched == 1) {
		return $matched[0];
	} else {
		@$candidates = (@matched, @unmatched);
		return 0;
	}
}


=item choose_package_conf

  my $pkgname = choose_package_conf $candidates;

Try to pick between candidate packages which satisfy a dependency, by using
elements of Fink's configuration. Currently, the way to do this is with the
MatchPackageRegex option.

The parameter $candidates is a list-ref of package names. It may be re-ordered
to reflect that certain candidates are more desirable than others.

If a single package is found, returns its name. Otherwise returns false.

=cut

sub choose_package_conf {
	my $candidates = shift;	
	my $matchstr = $config->param("MatchPackageRegEx");
	return 0 unless defined $matchstr;
	return choose_filter($candidates, sub { /$matchstr/ });
}

=item choose_package_from_relatives

  my $pkgname = choose_package_from_relatives $candidates;
  my $pkgname = choose_package_from_relatives $candidates,
      $will_install;

Try to pick between candidate packages which satisfy a dependency, by using
the status of a package's relatives as a heuristic.

If one package has a relative that is either installed, or marked for
installation, then usually that package is the right alternative to choose.

The parameter $candidates is a list-ref of package names. It may be re-ordered
to reflect that certain candidates are more desirable than others.

The parameter $will_install is a function or coderef which can be used
to determine if a PkgVersion is marked for installation. If omitted, it is
assumed that no packages are marked. It should operate on the
PkgVersion in $_, and should be callable with no arguments.

If a single package is found, this function returns its name.
Otherwise returns false.

=cut

sub choose_package_from_relatives {
	my $candidates = shift;
	my $will_install = shift || sub { 0 };
	
	return choose_filter($candidates, sub {
		grep { $_->is_installed || &$will_install() }
			Fink::Package->package_by_name($_)->get_latest_version
				->get_relatives
	});
}

=item choose_package_installed

  my $pkgname = choose_package_installed $candidates;

Try to pick between candidate packages which satisfy a dependency, by choosing
any package that is currently installed. (Even if it's a different version.)

The parameter $candidates is a list-ref of package names. Returns a package
name if one is found, otherwise false.

=cut

sub choose_package_installed {
	my $candidates = shift;
	foreach my $pkg (@$candidates) {
		return $pkg if Fink::Package->package_by_name($pkg)->is_any_installed;
	}
	return 0;
}

=item choose_package

  my $po = choose_package $candidates;
  my $po = choose_package $candidates, $will_install;

Pick between candidate packages which satisfy a dependency, using all
means available. See choose_package_from_relatives for parameters.

Returns a package object.

=cut

sub choose_package {
	my $candidates = shift;
	my $will_install = shift;
	my $found = 0;		# Set to name of candidate, if one has been found

	# Trivial case: only one candidate, nothing to be done, just use it.
	if (@$candidates == 1) {
		$found = $candidates->[0];
	}

	# Next, we check if by chance one of the candidates is already installed.
	# This would be a different version from any of the alternative PkgVersions
	# we looked at before, probably an upgrade is needed?
	$found = choose_package_installed($candidates) if not $found;

	# Next, check if a relative of a candidate has already been marked
	# for installation (or is itself a dependency). If so, we use that
	# candidate to fulfill the dep.
	# This is a heuristic, but usually does exactly "the right thing".
	$found = choose_package_from_relatives($candidates,
		$will_install) if not $found;

	# Now see if the user has set a regexp to match in fink.conf.
	$found = choose_package_conf($candidates) if not $found;
	
	# As a last resort, ask the user!
	$found = choose_package_ask($candidates) if not $found;
	
	return Fink::Package->package_by_name($found);
}

=item choose_pkgversion_marked

  my $did_find = choose_pkgversion_marked $dep_graph, $queue_item, @pkgversions;

Try to choose a PkgVersion to install, by choosing one already marked in the
dependency graph.

If a PkgVersion is chosen it is returned, and any necessary
modifications made to the dependency graph and the current dependency queue
item.

Otherwise, a false value is returned.

=cut

sub choose_pkgversion_marked {
	my ($deps, $item, @pvs) = @_;
	for my $dp (@pvs) {
		my $dname = $dp->get_name();
		if (exists $deps->{$dname} and $deps->{$dname}->[PKGVER] == $dp) {
			if ($deps->{$dname}->[OP] < $OP_INSTALL) {
				$deps->{$dname}->[OP] = $OP_INSTALL;
			}
			# add a link
			push @$item, $deps->{$dname};
			return $dp;
		}
	}
	return 0;
}

=item choose_pkgversion_installed

  my $did_find = choose_pkgversion_installed $dep_graph, $dep_queue,
    $queue_item, @pkgversions;

Try to choose a PkgVersion to install, by choosing one already installed.

If a PkgVersion is chosen it is returned, and any necessary
modifications made to the dependency graph, the dependency queue and the
current dependency queue item.

Otherwise, a false value is returned.

=cut

sub choose_pkgversion_installed {
	my ($deps, $queue, $item, @pvs) = @_;
	foreach my $dp (@pvs) {
		if ($dp->is_installed()) {
			my $dname = $dp->get_name();
			if (exists $deps->{$dname}) {
				die "Internal error: node for $dname already exists\n";
			}
			# add node to graph
			@{$deps->{$dname}}[ PKGNAME, PKGOBJ, PKGVER, OP, FLAG ] = (
				$dname, Fink::Package->package_by_name($dname),
				$dp, $OP_INSTALL, 2
			);
			# add a link
			push @$item, $deps->{$dname};
			# add to investigation queue
			push @$queue, $dname;
			return $dp;
		}
	}
	return 0;
}

=item pvs2pkgnames

  my @pkgnames = pvs2pkgnames @pvs;

Given a set of PkgVersions, find the unique package names B<preserving order>.

=cut

sub pvs2pkgnames {
	my %seen;
	my @results;
	for my $pv (@_) {
		push @results, $pv->get_name unless $seen{$pv->get_name}++;
	}
	return @results;
}

=item choose_pkgversion_by_package

  choose_pkgversion_by_package $dep_graph, $dep_queue, $queue_item,
    @pkgversions;

Choose a PkgVersion to install, by determining a preferred Package.

Any necessary modifications will be made to the dependency graph, the
dependency queue and the current dependency queue item.

=cut

sub choose_pkgversion_by_package {
	my ($deps, $queue, $item, $ok_versions, @pvs) = @_;
	
	# We turn our PkgVersions into a list of candidate package names,
	my @candidates = pvs2pkgnames @pvs;
	
	# Find the best package
	my $po = choose_package(\@candidates, sub { exists $deps->{$_->get_name} });
	my $pkgname = $po->get_name;
	
	# Restrict to PVs of the chosen pkg
	@pvs = grep { $_->get_name eq $pkgname } @pvs;
	
	# If we previously looked at this package, restrict to the available vers
	if (exists $ok_versions->{$pkgname}) {
		my %old = map { $_ => 1 } @{$ok_versions->{$pkgname}};
		@pvs = grep { $old{$_->get_fullversion} } @pvs;
	}
		
	# Choose a version
	my @vers = map { $_->get_fullversion } @pvs;
	my $latest = latest_version(@vers);
	my ($pv) = grep { $_->get_fullversion eq $latest } @pvs;
	unless (defined $pv) {
		print_breaking <<MSG;
Unable to resolve version conflict on multiple dependencies, for package
$pkgname.
MSG
		die "\n";
	}
	
	# add node to graph
	@{$deps->{$po->get_name}}[ PKGNAME, PKGOBJ, PKGVER, OP, FLAG ] = (
	   $pkgname, $po, $pv, $OP_INSTALL, 0
	);
	$ok_versions->{$pkgname} = \@vers;
	
	# add a link
	push @$item, $deps->{$po->get_name};
	# add to investigation queue
	push @$queue, $po->get_name;
}

=item choose_pkgversion

  choose_pkgversion $dep_graph, $dep_queue, $queue_item, $ok_versions, 
  	@pkgversions;

Choose a PkgVersion to install, using all available methods. The parameter
@pkgversions is a list of alternative PkgVersions to choose from.

Any necessary modifications will be made to the dependency graph, the
dependency queue and the current dependency queue item.

=cut

sub choose_pkgversion {
	my ($deps, $queue, $item, $ok_versions, @pvs) = @_;	
	return unless @pvs;		# skip empty lists
	
	# Check if any of the PkgVersions is already in the dep graph.
	return if choose_pkgversion_marked($deps, $item, @pvs);

	# Check if any of the PkgVersions is already installed
	return if choose_pkgversion_installed($deps, $queue, $item, @pvs);
	
	# Find the best PkgVersion by finding the best Package
	choose_pkgversion_by_package($deps, $queue, $item, $ok_versions, @pvs);	
}

=item prefetch

  prefetch $use_bindist, $dryrun, @dep_items;

For each of the given deps, determine if we'll need to fetch the source or
download the .deb via apt-get, and then do all the fetching.

=cut

sub prefetch {
	my ($use_bindist, $dryrun, @dep_items) = @_;

	# FIXME: factor out a standard Xterm notifier with new event types
	my $use_xttitle = grep { /^xterm$/i } split / /, $config->param_default('NotifyPlugin', 'Growl');
	
	&call_queue_clear;
	
	my @aptget; # Batch 'em
	my $count = 0;
	foreach my $dep (sort { $a->[PKGNAME] cmp $b->[PKGNAME] } @dep_items) {
		my $func;

		print "\033]2;pre-fetching " . $dep->[PKGVER]->get_fullname . " (" . (int(@dep_items) - ++$count) . " remaining)\007" if $use_xttitle;

		# What action do we take?
		if (grep { $dep->[OP] == $_ } ($OP_REINSTALL, $OP_INSTALL)) {
			if ($dep->[PKGVER]->is_installed || $dep->[PKGVER]->is_present) {
				next; # We have what we need, skip it
			} elsif ($use_bindist && $dep->[PKGVER]->is_aptgetable) {
				# Use apt
				push @aptget, $dep->[PKGVER];
			} elsif ($dep->[OP] == $OP_REINSTALL) {	# Shouldn't get here!
				die "Can't reinstall a package without a .deb\n";
			} else {
				# Fetch source
				&call_queue_add([ $dep->[PKGVER], 'phase_fetch',
								1, $dryrun ]);
			}
		} elsif (grep { $dep->[OP] == $_ }
						($OP_FETCH, $OP_BUILD, $OP_REBUILD)) {
			# Fetch source
			&call_queue_add([ $dep->[PKGVER], 'phase_fetch', 1, $dryrun ]);
		} else {
			die "Don't know about operation number $dep->[OP]!\n";
		}
	}

	if (@aptget) {
		print "\033]2;pre-fetching binaries with apt-get\007" if $use_xttitle;
		&call_queue_add([ $aptget[0], 'phase_fetch_deb', 1, $dryrun, @aptget ]);
	}
	
	print "\033]2;\007" if $use_xttitle;

	&call_queue_clear;
}

=item list_removals

  my @pkgnames = $engine->list_removals \%deps, \%conflicts;

List the package names that we may remove at some point.

=cut

sub list_removals {
	my ($deps, $conflicts) = @_;
	
	my %removals;
	for my $rpv (map { @$_ } values %$conflicts) {
		my $rname = $rpv->get_name;
		next if $removals{$rname};
		
		my $item = $deps->{$rname};
		my $will_inst = $item && ($item->[PKGVER] eq $rpv)
			&& ($item->[OP] == $OP_INSTALL || $item->[OP] == $OP_REINSTALL);
		$removals{$rname} = 1 if $will_inst || $rpv->is_installed;
	}
	return sort keys %removals;
}

=back

=cut

### EOF
1;
# vim: ts=4 sw=4 noet
