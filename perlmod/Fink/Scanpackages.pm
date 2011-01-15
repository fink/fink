# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Scanpackages module
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2006-2011 The Fink Package Manager Team
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

package Fink::Scanpackages;
use base 'Fink::Base';

use warnings;
use strict;

use Fink::CLI qw(capture);
use Fink::Command qw(mkdir_p);
use Fink::Services qw(latest_version);

use Config;
use Cwd;
use File::Find;
use File::Temp qw(tempfile);
use Storable qw(nfreeze thaw);

# Ensure that we load a compatible DB_File
{
	my @system_INC = @Config{qw(privlib archlib)};  # perl's own hard-
													# coded defaults
	local @INC = (@system_INC, @INC);  # place ahead of any PERL5LIB
									   # or 'use lib' additions
	require DB_File;
}

=head1 NAME

Fink::Scanpackages - Pure-perl .deb scanner.

=head1 DESCRIPTION

Fink::Scanpackages is a pure-perl way to generate a Packages file for a tree of
.debs. Unlike dpkg-scanpackges, it uses modern perl and a database for caching.

It is designed to work on Fink-generated .debs. Certain obsolete features of
.debs are therefore ignored, and some features of dpkg-scanpackages and
apt-ftparchive are not implemented.

=head1 SYNOPSIS

  use Fink::Scanpackages;

  # Object oriented
  my $sp = Fink::Scanpackages->new(%options);
  $sp->scan($dir, %options);
  $sp->scan_dists($options, @dirs);
  $sp->scan_fink;

  $sp->finish; # This is usually unnecessary


  # Functions
  Fink::Scanpackages->scan($dir, %options);
  Fink::Scanpackages->scan_dists($options, @dirs);
  Fink::Scanpackages->scan_fink(%options);

  my $path = Fink::Scanpackages->default_cache;

=head1 METHODS

=over 4

=item new

  my $sp = Fink::Scanpackages->new(%options);

Create a scanner object.

Options include:

=over 4

=item db

The path to use for caching results. Defaults to no cache.

=item pdb

If true, use the Fink package database for the fields that would be defined in
dpkg-scanpackage's override file. Defaults to true.

=item restrictive

If true, do index License: Restrictive. Defaults to true.

=item verbosity

An integer. If non-zero, various messages will be printed. The default is 1.

=item prefix

The prefix where dpkg-deb can be found. This defaults to the Fink prefix, but
supplying this option explicitly may allow scanpackages to run even without
a properly configured Fink.

=back

=item scan

  $sp->scan($dir, %options);
  Fink::Scanpackages->scan($dir, %options);

Scan a directory for packages, with output going to stdout.

If called as a package function rather than as a method, options for I<new>
may be included in %options.

Options include:

=over 4

=item output

The file or filehandle to output to. Defaults to stdout.

=item basedir

The directory relative to which all paths should be considered. This includes 
the $dir passed directly to I<scan>.

=back

=cut

sub scan {
	my ($self, $dir, %opts) = @_;
	$self = $self->new(%opts) unless ref $self;
	
	my $cwd = cwd;
	chdir $opts{basedir} if defined $opts{basedir};
	my $out = $opts{output};
	my ($dummy, $tmpfile);
	
	eval {
		# Open the output
		if (defined $out) {
			if (ref($out) eq 'GLOB') { # a filehandle
				$self->{outfh} = $out;
			} else {
				($dummy, $tmpfile) = tempfile("$out.XXXXX");
				if ($out =~ /\.gz$/) {
					open $self->{outfh}, "| gzip -c > \Q$tmpfile"
						or die "ERROR: Can't open output '$out'\n";
				} else {
					open $self->{outfh}, '>', $tmpfile
						or die "ERROR: Can't open output '$out': $!\n";
				}
			}
		} else {
			$self->{outfh} = \*STDOUT;
		}
		
		# Find all the debs
		find({ no_chdir => 1, wanted => sub {
			return unless /\.deb$/ && -f;
			
			eval {
				$self->_process_deb($_);
			};
			if ($@) {
				if ($@ =~ /^SKIPPING/) { # just a warning
					warn $@;
				} else {
					die $@;
				}
			}
		}}, $dir);
		
		if (defined $out && ref($out) ne 'GLOB') {
			close $self->{outfh} or die "ERROR: Can't close output: $!\n";
			chmod 0644, $tmpfile or die "ERROR: Can't chown tmp file: $!\n";
			rename $tmpfile, $out or die "ERROR: Can't move tmp file: $!\n";
		}
	}; my $err = $@;

	# Cleanup
	unlink $tmpfile if $tmpfile;
	delete $self->{outfh};
	chdir $cwd;
	die $err if $err;
}

=item scan_dists

  $sp->scan_dists($options, @dirs);
  Fink::Scanpackages->scan_dists($options, @dirs);

Scan many directories at once. The output for each directory is assumed to
go in Packages.gz at that directory's root.

The option I<basedir> from I<scan> is accepted. Other options include:

=over 4

=item release

A hashref. If present, a release file will be created in each directory scanned,
with fields taken from the hashref. The Archive and Component fields will be
auto-generated where possible.

=back

=cut

sub scan_dists {
	my ($self, $options, @dirs) = @_;
	my %opts = %$options;
	$self = $self->new(%opts) unless ref $self;

	my $cwd = cwd;
	chdir $opts{basedir} if defined $opts{basedir};
	
	my $err;
	for my $dir (@dirs) {
		eval {
			mkdir_p($dir) unless -d $dir;
			
			# Write out the release
			if (defined(my $release = $opts{release})) {
				if ($dir =~ m,^(?:.*/)?dists/(.*)/binary-[^/]+$,) {
					my $tree = $1;
					if ($tree =~ m,^([^/]+)/(.+)$,) {
						@$release{qw(Archive Component)} = ($1, $2);
					} else {
						@$release{qw(Archive Component)} = ($tree, 'main');
					}
				} else {
					warn "WARNING: Can't determine archive, component for "
						. "'$dir'\n";
				}
				my $rel = "$dir/Release";
				unless (open RELEASE, ">", "$dir/Release") {
					warn "WARNING: Can't write Release: $!\n";
				} else {
					printf RELEASE "%s: %s\n", $_, $release->{$_}
						for keys %$release;
					close RELEASE;
				}
			}
			
			print STDERR "Scanning $dir\n" if $self->{verbosity};
			$self->scan($dir, %opts, output => "$dir/Packages.gz");
		};
		if ($@) {
			die $@ if $@ =~ /User interrupt/;
			warn "WARNING: Error processing '$dir':\n  $@";
			$err = $@ unless defined $err;
		}
	}
	
	chdir $cwd;
	die $err if $err;
}

=item scan_fink

  $sp->scan_fink;
  $sp->scan_fink($options);
  $sp->scan_fink($options, @trees);

  Fink::Scanpackages->scan_fink;
  Fink::Scanpackages->scan_fink($options);
  Fink::Scanpackages->scan_fink($options, @trees);

Scan packages in Fink trees. If no trees are specified, all trees are scanned.

No options exist yet.

=cut

sub scan_fink {
	my ($self, $options, @trees) = @_;
	$options = {} unless defined $options;
	$self = $self->new(%$options) unless ref $self;
	
	$self->_ensure_fink;

	my $config = $Fink::Config::config;  # stupid use() spaghetti!
	return 0 if $config->mixed_arch(message=>'scan local binaries');

	# Get the tree list
	@trees = $config->get_treelist unless @trees;
	my @dists = map { "dists/$_/binary-".$config->param('Debarch') } @trees;
	
	# Get some more params
	my $basedir = $Fink::Config::basepath . "/fink";
	my %release = (
		Origin	=> 'Fink',
		Label	=> 'Fink',
		Architecture => $config->param('Debarch'),
	);
	
	# Always use a DB 
	$self->{db} = $Fink::Config::basepath . "/var/lib/fink/scanpackages.db"
		unless defined $self->{db};
	
	$self->scan_dists({%$options, basedir => $basedir, release => \%release},
		@dists);
}

=item default_cache

  my $path = Fink::Scanpackages->default_cache;

Get the path to the file that is used by default for caching result of
scan_fink.

=cut

sub default_cache {
	my ($self) = @_;
	
	$self->_ensure_fink;
	return $Fink::Config::basepath . "/var/lib/fink/scanpackages.db";
}

# Initialize the object
sub initialize {
	my ($self, %opts) = @_;
	$self->SUPER::initialize();
	
	# Setup options
	@$self{qw(pdb restrictive verbosity)} = (1, 1, 1); # defaults
	@$self{keys %opts} = values %opts;
}

# Get the control fields from a .deb
#
# my $hashref = $sp->_control($debpath);
sub _control {
	my ($self, $path) = @_;
	
	my (%control, $field);
	my $dpkgdeb = $self->_prefix . "/bin/dpkg-deb";
	open CONTROL, '-|', $dpkgdeb, '-f', $path
		or die "SKIPPING: Can't read control for '$path': $!\n";
	eval {
		while (<CONTROL>) {
			chomp;
			if (/^(\S+)\s*:\s*(.*)$/) {
				$control{$field = $1} = $2;
			} elsif (/^\s/) {
				$control{$field} .= "\n" . $_;
			} else {
				die "SKIPPING: Can't parse control for '$path'\n";
			}
		}
	};
	close CONTROL;
	die $@ if $@;
	
	return \%control;
}

# Make sure Fink is configured
#
# $sp->_ensure_fink;
# Fink::Scanpackages->_ensure_fink;
sub _ensure_fink {
	my ($self) = @_;
	
	unless (ref($self) && $self->{_fink_loaded}) {
		require Fink::Config;
		
		# Make sure fink has a config
		&_use_fink() unless defined $Fink::Config::config;
		$self->{_fink_loaded} = 1 if ref($self);
	}
}

# Make sure the package DB is available
#
# $sp->_ensure_pdb;
sub _ensure_pdb {
	my ($self) = @_;
	
	unless ($self->{_pdb_loaded}) {
		$self->_ensure_fink;
		require Fink::Package;
		
		print STDERR "Loading Fink package database\n" if $self->{verbosity};
		my $dummy;
		capture {
			Fink::Package->require_packages;
		} \$dummy, \$dummy;
		$self->{_pdb_loaded} = 1;
	}
}

# Merge into the control any needed fields from the Fink pdb
#
# $sp->_merge_fink_fields($control);
sub _merge_fink_fields {
	my ($self, $control) = @_;
	return unless $self->{pdb};
	
	# Don't bother getting license unless we care about restrictive
	if (!exists $control->{Section} || !exists $control->{Priority}
			|| (!$self->{restrictive} && !exists $control->{'Fink-License'})) {
		$self->_ensure_pdb;
		
		my $po = Fink::Package->package_by_name($control->{Package});
		if (defined $po) {
			my $pv = $po->get_version($control->{Version});
			if (!defined $pv) { # heuristic if no exact vers
				my @vers = $po->list_versions;
				$pv = $po->get_version(latest_version(@vers)) if @vers; 
			}
			
			if (defined $pv) {
				my ($prio, $section) = &_fink_fields($pv);
				
				$control->{Priority} = $prio
					unless exists $control->{Priority};
				$control->{Section} = $section
					unless exists $control->{Section};
				$control->{'Fink-License'} = $pv->get_license
					if !exists $control->{'Fink-License'}
					&& !$self->{restrictive};
			}
		}
	}
}

# Process the data for a single .deb, returning a post-processed control hash.
#
# my $control = $sp->_process_deb($debpath);
sub _process_deb {
	my ($self, $debpath) = @_;
	
	my $control;
	
	# Try to use the DB first
	my $debtime = (stat($debpath))[9];
	my $db = $self->_db;
	my $kmtime = "mtime:$debpath";
	my $kcont = "control:$debpath";
	if (defined (my $mtime = $db->{$kmtime})) {
		if ($debtime == $mtime) {
			print STDERR "Cached package: $debpath\n"
				if $self->{verbosity} >= 2;
			$control = thaw($db->{$kcont});
		} else {
			print STDERR "Changed package: $debpath\n" if $self->{verbosity};
		}
	} else {
		print STDERR "New package: $debpath\n" if $self->{verbosity};
	}
	
	# Can't use it unless there's a license
	undef $control if !$self->{restrictive}
		&& !exists $control->{'Fink-License'};
	
	unless (defined $control) {
		# Get data from the .deb
		my $md5 = &_md5($debpath);
		$control = $self->_control($debpath);
		
		# Add some fields
		$control->{Filename} = $debpath;
		$control->{MD5sum} = $md5;
		$control->{Size} = -s $debpath;
		$self->_merge_fink_fields($control);
		
		$db->{$kmtime} = $debtime;
		$db->{$kcont} = nfreeze($control);
	}
	
	$self->_output($control);
}

# Format and output a control hash
#
# $sp->_output($control);
sub _output {
	my ($self, $control) = @_;
	
	# Can't use if no license or restrictive license
	return if !$self->{restrictive} && (
		!exists $control->{'Fink-License'}
		|| lc $control->{'Fink-License'} eq 'restrictive'
		|| lc $control->{'Fink-License'} eq 'commercial');
	
	# Order to output fields, from apt-pkg/tagfile.cc
	my @fieldorder = qw(Package Essential Status Priority Section
		Installed-Size Maintainer Architecture Source Version Replaces Provides
		Depends Pre-Depends Recommends Suggests Conflicts Conffiles Filename
		Size MD5sum SHA1sum Description);
	
	# Output the fields
	my $out = '';
	for my $field (@fieldorder, keys %$control) {
		if (exists $control->{$field}) {
			$out .= sprintf "%s: %s\n", $field, $control->{$field};
			delete $control->{$field};
		}
	}
	$out .= "\n";
	
	print { $self->{outfh} } $out;
}

# Get the DB
#
# my $dbhash = $sp->_db;
sub _db {
	my ($self) = @_;
	if (!$self->{_db_file} && defined $self->{db}) {
		my $fh = &_lock($self->{db});
		if ($fh) {
			my $tried = 0;
			{
				if (tie my %db, 'DB_File', $self->{db}) {
					$self->{_db_file} = \%db;
					$self->{_db_fh} = $fh;
				} else {
					unless ($tried++) { # Mebbe corrupt?
						unlink $self->{db};
						redo;
					}
					warn "WARNING: Can't open DB: $!\n";
				}
			}
		} else {
			warn "WARNING: Can't lock DB: $!\n";
		}
		
		# Handle errors
		if (!$self->{_db_file}) {
			close $fh if $fh;
			$self->{_db_file} = { };
		}
	}
	return $self->{_db_file};
}

=item finish

  $sp->finish;

Explicitly releases any resources. Usually this will happen automatically when the object is destroyed.

=back

=cut

sub finish {
	my ($self) = @_;
	if ($self->{_db_fh}) {
		untie %{$self->{_db_file}};
		close $self->{_db_fh};
	}
}

# Clean up
sub DESTROY {
	my ($self) = @_;
	$self->finish;
}

# Get the prefix to find dpkg-deb
#
# my $prefix = $self->_prefix;
sub _prefix {
	my ($self) = @_;
	unless (exists $self->{_prefix}) {
		$self->_ensure_fink;
		$self->{_prefix} = $Fink::Config::basepath;
	}
	return $self->{_prefix};
}


#### Deal with different versions of Fink

# Get MD5 of a file
if (eval { require Fink::Checksum }) {
	my $chksum = Fink::Checksum->new('MD5');
	*_md5 = sub { $chksum->get_checksum($_[0]) };
} else {
	*_md5 = sub { Fink::Services::file_MD5_checksum($_[0]) };
}

# Initialize Fink
if (eval { require Fink }) {
	*_use_fink = sub { Fink->import };
} else {
	# Not so safe :-(
	*_use_fink = sub {
		(my $basepath = `which fink`) =~ s,/bin/fink\n$,,
			or die "ERROR: Can't find fink!\n";
		Fink::Config->new_with_path("$basepath/etc/fink.conf");
	};
}

# Lock a file
if (exists &Fink::Services::lock_wait) {
	*_lock = sub {
		my ($fh, $timedout) = Fink::Services::lock_wait($_[0],
			exclusive => 1, root_timeout => 600,
			desc => "another scanpackages");
		close $fh if $timedout;
		return !$timedout && $fh;
	};
} else {
	require Fcntl;
	*_lock = sub {
		open my $fh, '+>>', $_[0] or return 0;
		# OS X specific!
		my $struct_flock = pack("lllliss", (0, 0), (0, 0), 0,
			&Fcntl::F_WRLCK, &Fcntl::SEEK_SET);
		unless (fcntl($fh, &Fcntl::F_SETLK, $struct_flock)) { # No waiting
			close $fh;
			return 0;
		} else {
			return $fh;
		}
	};
}

# Get priority and section
if (exists &Fink::PkgVersion::get_priority) {
	*_fink_fields = sub {
		($_[0]->get_priority, $_[0]->get_control_section);
	};
} else {
	*_fink_fields = sub {
		my $section = $_[0]->get_section();
		$section = 'base' if $section eq 'bootstrap';
		
		my $prio = 'optional';
		$prio = 'important'
			if $_[0]->get_name eq 'apt' || $_[0]->get_name eq 'apt-shlibs';
		$prio = 'required' if $_[0]->param_boolean("Essential");
		
		return ($prio, $section);
	};
}

=head1 BUGS

It can be hazardous to change the 'pdb' option but use the same database.

=cut

1;
