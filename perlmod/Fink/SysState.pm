# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::SysState module
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
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA.
#

package Fink::SysState;

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION		= 1.00;
	@ISA			= qw(Exporter);
	@EXPORT			= qw($DETAIL_FIRST $DETAIL_PACKAGE $DETAIL_ALL);
	%EXPORT_TAGS	= ( );	# eg: TAG => [ qw!name1 name2! ],
	@EXPORT_OK		= qw();
}

END { }

use Fink::CLI		qw(&print_breaking_stderr);
use Fink::Config	qw($config);
use Fink::Services	qw(&pkglist2lol &version_cmp &spec2struct &spec2string
					   &sort_versions);
use Fink::Status;
use Fink::VirtPackage;

use Carp;	
use Storable qw(&freeze);

### GLOBALS

# How detailed a dep-check should we do?
our ($DETAIL_FIRST, $DETAIL_PACKAGE, $DETAIL_ALL) = 0..20;


=head1 NAME

Fink::SysState - Analyze the state of packages on the system

=head1 DESCRIPTION

Fink::SysState allows checking the consistency of a set of packages and their
dependencies.

Changes can be made to the current state, and then checked for problems.

NOTE: The states considered by this package are hypothetical states. No
packages are really added or removed by this package.

=head1 SYNOPSIS

	use Fink::SysState;


	# Get the current state
	my $state = Fink::SysState->new();

	# Examine the state
	my $version = $state->installed($pkgname);
	my @providers = $state->providers($pkgname); 

	my @pkgnames = $state->list_packages();
	my @pkgnames = $state->provided();


	# Look for dependency problems
	my @problems = $state->check();


	# Add and remove items. 
	my $new_item = {
		package => foo,
		version => 1.0-1,
		depends => 'bar, baz (>= 4.0-1)',
	};

	$state->add($new_item, $new_item2);
	$state->add_pkgversion($pv, $pv2, $pv3);
	$state->remove($pkgname, $pkgname2);


	# Make several changes at once
	my $changes = {
		add				=> [ @hashes	],
		add_pkversion	=> [ @pvs		],
		remove			=> [ @pkgnames	],
	};

	$state->change($changes, $changes2, ...);


	# Try out changed states
	$state->add(...); # Or remove, add_pkgversions, change
	...
	$state->undo();

	$state->checkpoint($checkpoint_name);
	...
	$state->undo($checkpoint_name);


	# Resolve inconsistent states
	my @extra_pvs = $state->resolve_install(@install_pvs);

=head1 METHODS

=head2 Constructing new objects

=over 4

=item new

	my $state = Fink::SysState->new();

Make a new state object, reflecting the current state of the system.

=cut

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	my $self = { };
	bless $self, $class;
	
	$self->_initialize;
	return $self;
}

# $self->_initialize();
#
# Initialize this state to the current state of the system.
sub _initialize {
	my $self = shift;
	
	for my $module (qw(Fink::Status Fink::VirtPackage)) {
		my $list = $module->list();
		for my $pkgname (keys %$list) {
			next unless defined $module->query_package($pkgname);
			$self->add($list->{$pkgname});
		}
	}

	$self->{history} = [ {} ];
}

=back

=head2 Examining the state

=cut

# my $pkg_item = $self->_package($pkgname);
#
# Gets the package-item hash (like an argument to &add) for the given package.
# If the package does not exist, throws an exception.
sub _package {
	my ($self, $pkgname) = @_;
	
	confess "Fink::SysState: No such package: $pkgname"
		unless defined $self->{packages}{$pkgname};
	return $self->{packages}{$pkgname};
}

# my $content = $self->_pkglist($pkgname, $field, $transform);
#
# Gets the contents of the package-listing field $field of package $pkgname in
# structural format.
#
# Requires a transformation code-ref that operates on $_, and turns each item of
# the package list from an array of alternative specification strings into the 
# desired format.
#
# Returns an empty list if the field does not exist. Throws an exception on 
# other errors.
sub _pkglist {
	my ($self, $pkgname, $field, $transform) = @_;
	my $pkg = $self->_package($pkgname);
	
	unless (ref $pkg->{$field}) {
		if (defined $pkg->{$field}) {
			$pkg->{$field} = pkglist2lol($pkg->{$field});
			for (@{ $pkg->{$field} }) {
				&$transform();
			}
		} else {
			$pkg->{$field} = [ ];
		}
	}
	
	return $pkg->{$field};
}

# my $depends = $self->_depends($pkgname);
#
# Gets the dependencies of a package in structural format.
#
# The structure is an array of requirements, each containing a array of
# alternatives that can satisfy the requirement. Each alternative is a
# specification structure as returned by spec2struct.
#
# If a package has no dependencies, returns an empty list. Throws an exception
# on other errors.
sub _depends {
	my ($self, $pkgname) = @_;
	return $self->_pkglist($pkgname, 'depends',
		sub { map { $_ = spec2struct($_, "'$_' in $pkgname") } @$_ });
}

# my $conflicts = $self->_conflicts($pkgname);
#
# Gets the conflicting packages of a package in structural format.
#
# The structure is an array of specification structures as returned by
# spec2struct.
#
# If a package has no conflicts, returns an empty list. Throws an exception
# on other errors.
sub _conflicts {
	my ($self, $pkgname) = @_;
	return $self->_pkglist($pkgname, 'conflicts',
		sub { $_ = spec2struct($_->[0], "'$_->[0]' in $pkgname") });
}

# my $provides = $self->_provides($pkgname);
#
# Gets the packages provided by a package in structural format.
#
# The structure is an array of package names.
#
# If a package provides nothing, returns an empty list. Throws an exception
# on other errors.
sub _provides {
	my ($self, $pkgname) = @_;
	return $self->_pkglist($pkgname, 'provides',
		sub { $_ = $_->[0] });
}

# my $replaces = $self->_replaces($pkgname);
#
# Gets the packages replaced by a package in structural format.
#
# The structure is an array of specification structures as returned by
# spec2struct.
#
# If a package replaces nothing, returns an empty list. Throws an exception
# on other errors.
sub _replaces {
	my ($self, $pkgname) = @_;
	return $self->_pkglist($pkgname, 'replaces',
		sub { $_ = spec2struct($_->[0], "'$_->[0]' in $pkgname") });
}

# my @satnames = $self->_satisfiers($spec);
#
# Find all package names that satisfy the given specification struct. Names are
# of real packages, not virtual ones.
sub _satisfiers {
	my ($self, $spec) = @_;
	my @sat;
	
	my $name = $spec->{package};
	my $vers = $self->installed($name);
	if (exists $spec->{version}) {
		return ( ($vers && version_cmp($vers, @$spec{qw(relation version)}))
			? ($name) : () );
	} else {
		return ($vers ? ($name) : (), $self->providers($name));
	}
}


=over 4

=item installed

	my $version = $state->installed($pkgname);

Determines whether a package is installed, and if so what version.

If a package is not installed, returns undef.

=cut

sub installed {
	my ($self, $pkgname) = @_;
	
	return undef unless defined $self->{packages}{$pkgname};
	return $self->{packages}{$pkgname}{version};
}

=item providers

	my @provider_pkgnames = $state->providers($pkgname);

Gets the names of the packages that provide the named package.

=cut

sub providers {
	my ($self, $pkgname) = @_;
	return () unless defined $self->{provides}{$pkgname};
	return keys %{ $self->{provides}{$pkgname} };
}

=item list_packages

	my @pkgnames = $state->list_packages();

Get a list of the names of every package installed.

=cut

sub list_packages {
	my $self = shift;
	return keys %{$self->{packages}};
}

=item provided

	my @pkgnames = $state->provided();

Get a list of every package that has been explicitly provided by another 
package. Each such package may or may not be itself installed.

=cut

sub provided {
	my $self = shift;
	return keys %{$self->{provides}};
}

=back

=head2 Changing the system state

=cut

# $self->_start_changing();
#
# Start making changes to the system.
#
# Any internal method that may change the system state should call this method
# before making any changes, and call _stop_changing when it's done.
sub _start_changing {
	my $self = shift;
	unless ($self->{change_level}++) {
		$self->{current_change} = [ ];
	}
}

# $self->_made_change(added => $pkgname);
# $self->_made_change(removed => $pkg_hash);
#
# Every time an internal method B<directly> makes a change to the system state,
# it should call this method to notify the reversion system.
#
# If another method is called to make the change, this method should B<not> be
# called, that's an indirect change.
sub _made_change {
	my ($self, $action, $item) = @_;
	
	if ($action eq 'added') {
		unshift @{$self->{current_change}}, { remove => [ $item ] };
		#print "Adding $item\n";
	} elsif ($action eq 'removed') {
		unshift @{$self->{current_change}}, { add => [ $item ] };
		#print "Removing $item->{package}\n";
	} else {
		croak "Fink::SysState: Unknown action: $action";
	}
}

# $self->_stop_changing();
#
# Stop making changes to the system.
sub _stop_changing {
	my $self = shift;
	unless (--$self->{change_level}) {
		push @{$self->{history}}, { changes => $self->{current_change} };
	}
}

{
	# Various categories of fields
	my @fields_required = qw(package version);
	my @fields_pkglist = qw(depends conflicts provides replaces);
	my %fields_allowed = map { $_ => 1 } @fields_required, @fields_pkglist;
	
	# $self->_remove_replaced_conflicts($pkgname);
	#
	# Remove packages that are replaced and conflicted by the given package.
	sub _remove_replaced_conflicts {
		my ($self, $pkgname) = @_;
		
		my %repl = map { $_ => 1 } map { $self->_satisfiers($_) }
			@{ $self->_replaces($pkgname) };
		my %con = map { $_ => 1 } map { $self->_satisfiers($_) }
			@{ $self->_conflicts($pkgname) };
		delete $repl{$pkgname}; # Don't remove what we just added!
		
		my @repcon = grep { $con{$_} } keys %repl;
		$self->remove(@repcon);
	};

=over 4

=item add

	my $new_item = {
		package => foo,
		version => 1.0-1,
		depends => 'bar, baz (>= 4.0-1)',
	};

	$state->add($new_item, $new_item2, ...);

Adds one or more packages to this system state, getting the information about
them from hash-refs.

Each package must be specified by a hash, containing at minimum the fields
'package' and 'version'. The fields 'depends', 'provides' and 'conflicts' are
also considered meaningful; other fields will be silently deleted.

If a package with the same name as one of those added already exists in the
state, it will be removed and replaced. An exception will be thrown on
other errors.

=cut

	sub add {
		my $self = shift;
		$self->_start_changing();
		
		for my $pkgitem (@_) {
			# Validate fields
			for my $field (@fields_required) {
				confess "Fink::SysState: Required field missing: $field"
					unless defined $pkgitem->{$field};
			}
			my @badfields = grep { !$fields_allowed{$_} } keys %$pkgitem;
			delete $pkgitem->{$_} for (@badfields);
			
			# Remove if already installed
			my $pkgname = $pkgitem->{package};
			$self->remove($pkgname) if $self->installed($pkgname);
			
			# Add it, and deal with the providers
			$self->{packages}{$pkgname} = $pkgitem;
			for my $provided (@{ $self->_provides($pkgname) }) {
				$self->{provides}{$provided}{$pkgname} = 1;
			}
			$self->_made_change(added => $pkgname);
			
			# Remove anything that's replaced/conflicted
			$self->_remove_replaced_conflicts($pkgname);
		}
		
		$self->_stop_changing;
	}

=item add_pkgversion

	$state->add_pkgversion(@pvs);

Adds one or more packages to this system state, getting the information about
them from Fink::PkgVersion objects.

If a package with the same name as one of those added already exists in the
state, it will be removed and replaced. An exception will be thrown on
other errors.

=cut

	sub add_pkgversion {
		my $self = shift;
		$self->_start_changing();
		
		require Fink::PkgVersion;
		for my $pv (@_) {
			my $hash = {
				package => $pv->get_name(),
				version => $pv->get_fullversion(),
			};
			for my $field (@fields_pkglist) {
				$hash->{$field} = $pv->pkglist($field)
					if $pv->has_pkglist($field);
			}
			$self->add($hash);
		}
		
		$self->_stop_changing();
	}

} # my block for fields_*

=item remove

	$state->remove(@pkgnames);

Removes one or more packages from this system state.

If one of the package names requested does not exist in the state, a
warning will be emitted. An exception will be thrown on other errors.

=cut

sub remove {
	my $self = shift;
	$self->_start_changing();
	
	for my $pkgname (@_) {
		# Remove any provides
		for my $provided (@{ $self->_provides($pkgname) }) {
			delete $self->{provides}{$provided}{$pkgname};
			delete $self->{provides}{$provided}
				unless %{ $self->{provides}{$provided} };
		}
		
		if (defined $self->installed($pkgname)) {
			$self->_made_change(removed => $self->_package($pkgname));
			delete $self->{packages}{$pkgname};
		} else {
			carp "Fink::SysState: No such package: $pkgname";
		}
	}
	
	$self->_stop_changing();
}

=item change

	my $changes = {
		add				=> [ @hashes	],
		add_pkversion	=> [ @pvs		],
		remove			=> [ @pkgnames	],
	};

	$state->change($changes, $changes2, ...);

Make different changes to the system state all at once.

The keys in the changes hash should be: 'add' for package-item hashes to add,
'add_pkgversion' for Fink::PkgVersion objects to add, and 'remove' for names
of packages to remove.

=cut

sub change {
	my $self = shift;
	$self->_start_changing();
	
	for my $changes (@_) { # Remove FIRST
		$self->remove(			@{ $changes->{remove}			});
		$self->add(				@{ $changes->{add}				});
		$self->add_pkgversion(	@{ $changes->{add_pkgversion}	});
	}

	$self->_stop_changing();
}

=item checkpoint

	$state->checkpoint($checkpoint_name);

Set a checkpoint, which can be reverted to later.

=cut

sub checkpoint {
	my ($self, $name) = @_;
	$self->{history}[-1]{checkpoints}{$name} = 1;
}

=item undo

	$state->undo();
	$state->undo($checkpoint_name);

Revert the last change made, or move to a checkpoint. Returns an array-ref
which can be passed to the &change method to revert the reversion.

WARNING: Once you undo, you can't redo except by using the return value. All
checkpoints that are reverted past are lost.

=cut

sub undo {
	my ($self, $name) = @_;
	$self->_start_changing();
	
	while (1) {
		# Stop if we're there
		last if defined $name
			&& defined $self->{history}[-1]{checkpoints}{$name};
		
		# Check if we can continue
		unless (scalar(@{$self->{history}}) > 1) {
			carp "Fink::SysState: Nothing to undo";
			last;
		}
		
		# Do the changes
		for my $change (@{$self->{history}[-1]{changes}}) {
			$self->change($change);
		}
		
		# Move back
		pop @{$self->{history}};
		
		last unless defined $name; # We're just going once
	}
	
	$self->_stop_changing();
	my $changes_made = pop @{$self->{history}};
	return $changes_made->{changes};
}

=back

=head2 Dealing with dependency problems

=over 4

=cut

# my @problems = $self->_check_depends($opts, $pkgname);
#
# Check if a package has a problem with a dependency
sub _check_depends {
	my ($self, $opts, $pkgname) = @_;
	my @probs;
	
	REQ: for my $req (@{ $self->_depends($pkgname) }) { # next if match 
		for my $alt (@$req) {
			my @sat = $self->_satisfiers($alt);
			next REQ if @sat;
		}
		
		# Nothing found to satisfy us.
		my $desc = "Unsatisfied dependency in $pkgname: "
			. join(' | ', map { spec2string($_) } @$req);
		
		push @probs, {
			package	=> $pkgname,
			field	=> 'depends',
			spec	=> $req,
			desc	=> $desc,
		};
		
		print_breaking_stderr("Fink::SysState: $desc") if $opts->{verbose};
		return @probs if $opts->{detail} <= $DETAIL_PACKAGE;
	}
	
	return @probs;
}

# my @problems = $self->_check_conflicts($opts, $pkgname);
#
# Check if a package has a problem with a conflicts
sub _check_conflicts {
	my ($self, $opts, $pkgname) = @_;
	my @probs;
	
	for my $con (@{ $self->_conflicts($pkgname) }) { # next if no match
		my @sat = $self->_satisfiers($con);
		
		# It's ok for something to conflict on what it provides
		@sat = grep { $_ ne $pkgname } @sat;
		
		# Found some conflicts (one per conflictor!)
		for my $sat (@sat) {
			my $desc = "$pkgname conflicts with " . spec2string($con)
				. ", but $sat is installed";
			
			push @probs, {
				package	=> $pkgname,
				field	=> 'conflicts',
				spec	=> $con,
				desc	=> $desc,
				conflictor => $sat,
			};
			
			print_breaking_stderr("Fink::SysState: $desc") if $opts->{verbose};
			return @probs if $opts->{detail} <= $DETAIL_PACKAGE;
		}
	}
	
	return @probs;
}

=item check

	my @problems = $state->check();
	@problems = $state->check($options);
	@problems = $state->check($options, @pkgnames);

Check for unsatisfied dependencies or conflicts. If passed package names, only
checks those packages, otherwise checks all packages.

A list of dependency problems encountered is returned. If the list is empty,
no problems were found. Each item in the list returned is a hash-ref,
containing the following keys:

=over 4

=item package

The package with the unsatisfied dependency or conflict.

=item field

The field which is unsatisfied, either 'depends' or 'conflicts'.

=item spec

The package specification which is unsatisfied. For a 'depends' field, this is
an array-ref of alternative specifications. For a 'conflicts' field, this is
a single specification. See B<spec2struct> for the format of specification
structures.

=item desc

A textual description that can be shown to a user to describe the failed
dependency.

=item conflictor

If the field is conflicts, then this is the name of the package causing the
conflict.

=back

The $options hash-ref can contain the following keys:

=over 4

=item verbose

If true, print detailed messages to stderr when a dependency problem is found.
Defaults to false.

=item detail

The level of detail desired, one of $DETAIL_FIRST, $DETAIL_PACKAGE or
$DETAIL_ALL. With $DETAIL_ALL, every problem will be returned. To speed up the
check, use $DETAIL_PACKAGE to find just one problem per package with unsatisfied 
dependencies or conflicts. For the fastest check, use $DETAIL_FIRST to return
only the first problem found.

In array context $DETAIL_ALL is the default, in scalar context $DETAIL_FIRST
is the default.

=back

=cut

sub check {
	my $self = shift;
	my $optref = shift || { };
	my %opts = (
		verbose => 0,
		detail => wantarray ? $DETAIL_ALL : $DETAIL_FIRST,
		%$optref
	);
	
	my @probs;
	PKG: for my $pkgname (@_ ? @_ : $self->list_packages()) {
		my @pkgprobs = $self->_check_depends(\%opts, $pkgname);
		push @pkgprobs, $self->_check_conflicts(\%opts, $pkgname)
			unless @pkgprobs && $opts{detail} <= $DETAIL_PACKAGE;
		
		push @probs, @pkgprobs;
		return @probs if @probs && $opts{detail} <= $DETAIL_FIRST;		
	}

	return @probs;
}

# my @pvs = $state->_satisfied_versions($pkgname, $ignore);
#
# Get PkgVersions of the given package name that would individually be
# satisfied.
sub _satisfied_versions {
	my ($self, $pkgname, $ignore) = @_;
	
	require Fink::Package;
	my $po = Fink::Package->package_by_name($pkgname);
	return () unless $po;
	
	# Higher version candidates are preferred, so they go first
	my @cands = map { $po->get_version($_) }
		reverse sort_versions $po->list_versions();
	
	# Don't want to build, so alternatives must already have deb
	@cands = grep { $_->is_present() } @cands;
	
	# Narrow down to ones that would be satisfied, individually
	my @finalcands;
	foreach my $cand (@cands) {
		$self->add_pkgversion($cand);
		my $nok = grep { $_->{package} eq $pkgname }
			$self->_check_ignoring($ignore);
		$self->undo();
		push @finalcands, $cand unless $nok;
	}
	
	return @finalcands;
}	

# my @extras = $self->_satisfied_combo($altern_lol, $install_pvs, $ignore)
#
# Find a combination of alternatives which satisfies everything, return the
# list of alternatives on success or an empty list on failure.
sub _satisfied_combo {
	my ($self, $alterns, $install_pvs, $ignore, $chosen) = @_;
	$chosen = [] unless $chosen; # What's already been chosen?
	
	unless (@$alterns) { # We're at a final state, is it ok?
		return () if $self->_check_ignoring($ignore);
		
		# Make sure all the packages are still here (unreplaced)
		for my $pv (@$install_pvs) {
			my $vers = $self->installed($pv->get_name);
			return () unless defined($vers) && $vers eq $pv->get_fullversion;
		}
		return @$chosen;
	}
	
	# Try all the candidates for one unsatisfied package
	my $cands = pop @$alterns;
	foreach my $cand (@$cands) {
		push @$chosen, $cand;	# Try it
		$self->add_pkgversion($cand);
		
		# Recurse through the next package
		my @ok = $self->_satisfied_combo($alterns, $install_pvs,
			$ignore, $chosen);
		return @ok if @ok;
		
		pop @$chosen;			# Undo the attempt
		$self->undo();
	}
	
	return ();	# Options exhausted
}

# my $uid = $self->_problem_uid($problem);
#
# Get a unique identifier for the given problem.
sub _problem_uid {
	my ($self, $problem) = @_;
	
	local $Storable::canonical = 1; # temporary
	return freeze($problem);
}

# my @probs = $self->_check_ignoring($ignore);
#
# Get all problems whose uids aren't in $ignore.
sub _check_ignoring {
	my ($self, $ignore) = @_;
	
	return grep { !$ignore->{$self->_problem_uid($_)} } $self->check();	
}

# $self->_resolve_install_failure($probs, $install_pvs);
#
# Handle failure to resolve an inconsistent state on installation.
sub _resolve_install_failure {
	my ($self, $probs, $install_pvs) = @_;
	
	print_breaking_stderr("Could not resolve inconsistent dependencies!");
	my @bls = map { $_->{package} =~ /^fink-buildlock-(.*)/ ? $1 : () } @$probs;
	if (@bls) {
		print_breaking_stderr("It looks like some of the problems encountered"
			. " involve buildlocks for the following packages:");
		print_breaking_stderr("  $_") for sort @bls;
		print STDERR "\n";
		print_breaking_stderr("This probably means you should wait for those"
			. " packages to finish building, and then try again");
	} else {
		print STDERR "\n";
		print_breaking_stderr("Fink isn't sure how to install the above"
			. " packages safely. You may be able to fix things by running:");
	
		my $aptpkgs = join (' ', map {
			$_->get_name() . "=" . $_->get_fullversion()
		} @$install_pvs );
		print_breaking_stderr(<<FAIL);

  fink scanpackages
  sudo apt-get update
  sudo apt-get install $aptpkgs

FAIL
	}
	
	die "Fink::SysState: Could not resolve inconsistent dependencies\n";
}

=item resolve_install

  my @extra_pvs = $state->resolve_install(@install_pvs);

Dpkg has a known bug, which can lead to an inconsistent system state when
installing packages which no longer satisfy another package's versioned
dependency.

This method attempts to resolve this situation. Pass in a list of PkgVersion
objects which should be installed to the given state, and the return value will
be a list of additional PkgVersion objects which must be installed at the same 
time to preserve consistency.

On return, the state object will reflect the installation of all the necessary 
packages.

If no acceptable resolution can be found, an exception will be thrown.

=cut

sub resolve_install {
	my ($self, @install_pvs) = @_;
	my $verbose = ($config->verbosity_level() > 1);
	
	# Ignore pre-existing problems
	my $ignore = { map { $self->_problem_uid($_) => 1 } $self->check() };
	
	# Add the packages
	$self->add_pkgversion(@install_pvs);
	my @probs = $self->_check_ignoring($ignore);
	return () unless @probs; # We're ok!
	
	# We need to resolve some deps, let the user know
	if ($verbose) {
		print STDERR "\n";
		print_breaking_stderr("While trying to install:");
		print_breaking_stderr("  $_")
			for sort map { $_->get_fullname } @install_pvs;
		print STDERR "\n";
		print_breaking_stderr("The following inconsistencies found:");
		print_breaking_stderr('  ' . $_->{desc}) for @probs;
		print STDERR "\n";
		print_breaking_stderr("Trying to resolve dependencies...");
	}	
	
	# For each unsatisfied package, find alternative versions
	my %unsat = map { $_->{package} => 1 } @probs;
	my %alterns = map {
		$_ => [ $self->_satisfied_versions($_, $ignore) ]
	} keys %unsat;
	
	# If there's at least one alternative for each unsat, try to find a combo
	# that will satisfy all.
	my @extras = $self->_satisfied_combo([ values %alterns ],
		\@install_pvs, $ignore);
	
	if (@extras) {	# Found a solution!
		if ($verbose) {
			print STDERR "\n";
			print_breaking_stderr("Solution found. Will install extra "
				. "packages:");
			print_breaking_stderr("  $_")
				for sort map { $_->get_fullname } @extras;
		}
		return @extras;
	} else {		# Failure
		$self->_resolve_install_failure(\@probs, \@install_pvs);
	}
}

=back

=cut

1;
