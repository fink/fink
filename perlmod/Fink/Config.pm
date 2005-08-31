# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Config class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2005 The Fink Package Manager Team
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

package Fink::Config;
use Fink::Base;
use Fink::Command qw(cp);
use Fink::Services;


use strict;
use warnings;

require Exporter;

our @ISA	 = qw(Exporter Fink::Base);
our @EXPORT_OK	 = qw($config $basepath $libpath $debarch $buildpath $dbpath
                      $distribution $ignore_errors
                      get_option set_options
                     );
our $VERSION	 = 1.00;


our ($config, $basepath, $libpath, $dbpath, $distribution, $buildpath, $ignore_errors);
my $_arch = Fink::Services::get_arch();
our $debarch = "darwin-$_arch";

my %options = ();



=head1 NAME

Fink::Config - Read/write the fink configuration

=head1 SYNOPSIS

  use Fink::Config;
  my $config = Fink::Config->new_with_path($config_file);

  # General configuration file parameters
  my $value = $config->param($key);
  $config->set_param($key, $value);
  $config->save;

  # Configuration flags
  my $bool		= $config->has_flag($flag);
  $config->set_flag($flag);
  $config->clear_flag($flag);

  # Specific configuration options
  my $path		= $config->get_path;
  my @trees		= $config->get_treelist;
  my $verbosity	= $config->verbosity_level;
  my $use_apt	= $config->binary_requested;

  # Command-line parameters
  my $value = $config->get_option($key, $default);
  $config->set_options({ $key => $value, $key2 => ... });

=head1 DESCRIPTION

A class representing the fink configuration file as well as any command
line options.  Fink::Config inherits from Fink::Base.

Fink::Config will not work without a Fink::Config object having been made
that contains a basepath.  The fink program typically does this for you.
Since the variables Fink::Config exports use data from the last initialized
Fink::Config object, creating a second object is not recommended.


=head2 Constructors

=over 4

=item new

=item new_from_properties

Inherited from Fink::Base.

=item new_with_path

  my $config = Fink::Config->new_with_path($config_file);
  my $config = Fink::Config->new_with_path($config_file, \%defaults);

Reads a fink.conf file into a new Fink::Config object and initializes
Fink::Config globals from it.  

If %defaults is given they will be used as defaults for any keys not in the
config file.  For example...

    my $config = Fink::Config->new_with_path($file, { Basepath => "/sw" });

=cut

sub new_with_path {
	my($proto, $path, $defaults) = @_;
	$defaults = {} unless ref $defaults eq 'HASH';
	my $class = ref($proto) || $proto;

	my $props = Fink::Services::read_properties($path);

	my $self = { _path => $path };
	@{$self}{map lc, keys %$defaults} = values %$defaults;

	while (my($key, $value) = each %$props) {
		$self->{$key} = $value unless $key =~ /^_/;
	}

	$self = bless $self, $class;
	$self->initialize();

	return $self;
}


=begin private

=item initialize

  $self->initialize;

Initialize Fink::Config globals.  To be called from any constructors.

=end private

=cut

sub initialize {
	my $self = shift;

	$self->SUPER::initialize();

	$config = $self;

	$basepath = $self->param("Basepath");
	unless (defined $basepath and $basepath) {
		my $error = 'Basepath not set';
		if( $self->{_path} ) {
			$error .= qq{ in config file "$self->{_path}"};
		}
		else {
			$error .= qq{, no config file};
		}
		$error .= "!\n";
		die $error;
	}

	$buildpath = $self->param_default("Buildpath", "$basepath/src/fink.build");

	$libpath = "$basepath/lib/fink";
	$dbpath = "$basepath/var/lib/fink";  # must sync with fink.info.in!
	$distribution = $self->param("Distribution");
	if (not defined $distribution or ($distribution =~ /^\s*$/)) {
		die "Distribution not set in config file \"".$self->{_path}."\"!\n";
	}

	$self->{_queue} = [];
}

=back

=head2 Configuration queries

=over 4

=item get_path

  my $path = $config->get_path;

Returns the path to the configuration file which $config represents.

=cut

sub get_path {
	my $self = shift;

	return $self->{_path};
}


=item get_treelist

  my @trees = $config->get_treelist;

Returns the trees which should be currently used. This depends on the
value of Trees in fink.conf, as well as any trees specified at the command
line.

=cut

sub _standard_treelist {
	my $self = shift;
	return grep !m{^(/|.*\.\./)}, split /\s+/, $self->param_default(
		"Trees", "local/main stable/main stable/bootstrap");
}

sub get_treelist {
	my $self = shift;
	my @avail = $self->_standard_treelist;
	
	my @cmdline = split /,/, join ',', @{get_option('trees', [])};
	return @avail unless @cmdline; # use all by default
	
	# Make filter hash using command-line options
	my %want;
	for my $filt (@cmdline) {
		my $match = ($filt =~ m,/,)
			? sub { $_ eq $filt }		# Exact match
			: sub { m,^\Q$filt\E/, };	# Partial match
		my @ok = grep { &$match() } @avail;
		print "WARNING: No tree matching \"$filt\" found!\n" unless @ok;
		@want{@ok} = (1) x @ok;
	}
	
	return grep { $want{$_} } @avail;
}

=item custom_treelist

  my $bool = $config->custom_treelist;

Returns whether or not we're using a custom list of trees specified at the
command line.

=cut

sub custom_treelist {
	my $self = shift;
	my @avail = $self->_standard_treelist;
	my @current = $self->get_treelist;
	
	# If lists are unequal (ordered!), return true
	while (@avail && @current) {
		return 1 unless (shift @avail) eq (shift @current);
	}
	return @avail || @current;
}

=item param

=item param_default

=item param_boolean

=item has_param

=item set_param

Inherited from Fink::Base.

set_param also keeps a list of params that have been change since the
$config object was originally initialized or last did $config->save()

=cut

sub set_param {
	my($self, $key, $value) = @_;
	$self->SUPER::set_param($key, $value);
	push @{$self->{_queue}}, $key;
}

=item save

  $config->save;

Saves any changes made with set_param() to the config file. Only lines
of the file that correspond to params that were changed by set_param()
are altered.

=cut

sub save {
	my $self = shift;
	my $path = $self->{_path};
	my ($key, $skip_cont, %queue, %values);

	%queue = ();
	%values = ();
	foreach $key (@{$self->{_queue}}) {
		$queue{lc $key} = $key;
		if (exists $self->{lc $key} and defined($self->{lc $key})) {
			$values{lc $key} = $self->{lc $key};
		} else {
			$values{lc $key} = "";
		}
		$values{lc $key} =~ s/\n/\n /gs;
	}

	$skip_cont = 0;
	open(IN,$path) or die "can't open configuration: $!";
	open(OUT,">$path.tmp") or die "can't write temporary file: $!";
	while (<IN>) {
		chomp;
		unless (/^\s*\#/) {		# leave comments alone
			if (/^([0-9A-Za-z_.\-]+)\:.*$/) {
				if (exists $queue{lc $1}) {
					# skip continuation lines
					$skip_cont = 1;
					# make sure we only write it once
					next unless defined($queue{lc $1});
					$key = $queue{lc $1};
					$queue{lc $1} = undef;
					# write nothing for empty values
					next if $values{lc $1} eq "";
					# else write the new setting
					$_ = $key.": ".$values{lc $1};
				} else {
					# keep this setting and its continuation lines
					$skip_cont = 0;
				}
			} elsif (/^\s+(\S.*)$/) {
				# it's a continuation line
				next if $skip_cont;
			}
		}
		print OUT "$_\n";
	}
	close(IN);
	foreach $key (sort keys %queue) {
		# get the keys we have not seen yet
		next unless defined $queue{$key};
		# write nothing for empty values
		next if $values{$key} eq "";
		# add the setting at the end of the file
		print OUT $queue{$key}.": ".$values{$key}."\n";
	}
	close(OUT);

	# put the temporary file in place
	unlink $path;
	rename "$path.tmp", $path;

	$self->{_queue} = [];

	$self->write_sources_list;
}

=item write_sources_list

  $config->write_sources_list;

Writes an appropriate $basepath/etc/apt/sources.list file, based on
configuration information.  Called automatically by $config->save.

=cut

sub write_sources_list {
	my $self = shift;
	my $basepath = $self->param("Basepath");
	my $path = "$basepath/etc/apt/sources.list";

# We copy any existing sources.list file to sources.list.finkbak, unless
# a fink backup already exists.  (So effectively, this is done only once.)

	if ((not -f "$path.finkbak") and (-f "$path")) {
		cp "$path", "$path.finkbak";
	}

	open(OUT,">$path.tmp") or die "can't open $path.tmp: $!";

# We separate out the top and bottom lines of the body of sources.list, to
# allow for local modifications above and below them, respectively.

	my $topline = "# Local modifications should either go above this line, or at the end.";
	my $bottomline = "# Put local modifications to this file below this line, or at the top.";

# Next, we prepare the body for writing.

	my $body = "$topline\n";
	$body .= <<EOF;
#
# Default APT sources configuration for Fink, written by the fink program

# Local package trees - packages built from source locally
# NOTE: this is automatically kept in sync with the Trees: line in 
# $basepath/etc/fink.conf
# NOTE: run 'fink scanpackages' to update the corresponding Packages.gz files
EOF

# We write a separate line for each entry in Trees, in order, so that
# apt-get searches for packages in the same order as fink does.  However,
# we do combine lines if the distribution is the same in two consecutive
# ones.

	my $trees = $self->param("Trees");
	my $prevdist = "";
	my ($tree, @prevcomp);

	foreach $tree (split(/\s+/, $trees)) {
		$tree =~ /(\w+)\/(.*)$/;
		if ($prevdist eq $1) {
			push @prevcomp, $2;
		} else {
			if ($prevdist) {
				$body .= "deb file:$basepath/fink $prevdist @prevcomp\n";
			}
			$prevdist = $1;
			@prevcomp = ($2);
		}
	}
	if ($prevdist) {
		$body .= "deb file:$basepath/fink $prevdist @prevcomp\n";
	}

	$body .= "\n";

# For transition from 10.1 installations, we include pointers to "old"
# deb files.

	if (-e "$basepath/fink/old/dists") {
		$body .= <<"EOF";
# Allow APT to find pre-10.2 deb files
deb file:$basepath/fink/old local main
deb file:$basepath/fink/old stable main crypto
EOF

if (-e "$basepath/fink/old/dists/unstable") {
	$body .= "deb file:$basepath/fink/old unstable main crypto\n";
}
		$body .= "\n";
	}

# We only include the remote debs if the $basepath is set to /sw.

	if ("$basepath" eq "/sw") {

		my $apt_mirror = "http://us.dl.sourceforge.net/fink/direct_download";

		if ($self->has_param("Mirror-apt")) {
			$apt_mirror = $self->param("Mirror-apt");
		}

		my $distribution = $self->param("Distribution");

		$body .= <<EOF;
# Official binary distribution: download location for packages
# from the latest release
EOF

	$body .= "deb $apt_mirror $distribution/release main crypto\n\n";
		$body .= <<EOF;
# Official binary distribution: download location for updated
# packages built between releases
EOF

	$body .= "deb $apt_mirror $distribution/current main crypto\n\n";

	}

	$body .= "$bottomline\n";

# Now we analyze the existing file, to see which parts we will need to copy.

	my $bodywritten = 0;

# If there is an existing source.list file, we copy the top lines to the
# new file, until we hit the expected demarcation line. 

	my $topmodification = 1;
	my $bottommodification = 0;


	if (-f "$path") {
		open(IN,"$path") or die "can't open sources.list: $!";
		while (<IN>) {
			chomp;
			if ($topmodification) {
				if ($_ eq $topline) {
					$topmodification = 0;

# We need to watch for the closing demarcation line: if we hit that before the
# opening demarcation line, then we shouldn't have copied the lines to the
# output file.  To fix this, we close the output file, discard it, and reopen 
# the file.

				} elsif ($_ eq $bottomline) {
					$topmodification = 0;
					$bottommodification = 1;
					close(OUT);
					unlink "path.tmp";
					open(OUT,">$path.tmp") or die "can't write temporary file: $!";
				} else {
					print OUT "$_\n";
				}
			} else {
				if (not $bodywritten) {
					print OUT $body;
					$bodywritten = 1;
				}
				if ($bottommodification) {
					print OUT "$_\n";
				} elsif ($_ eq $bottomline) {
					$bottommodification =1;
				}
			}
		}
	
		close(IN);
	}

# If we never saw $topline, we should discard the output file and reopen it.

	if ($topmodification) {
		close(OUT);
		unlink "path.tmp";
		open(OUT,">$path.tmp") or die "can't write temporary file: $!";
	}


# If we have failed to write the body (because sources.list didn't exist, or
# didn't contain the expected lines), write it now.

	if (not $bodywritten) {
		print OUT $body;
	}

	close(OUT);


	# put the temporary file in place
	unlink $path;
	rename "$path.tmp", $path;
}

=back

=head2 Exported Functions

These functions are exported only on request

=over 4

=item set_options

  set_options({ key1 => val1, key2 => val2, ...});

Sets global configuration options, mostly used for command line options.

=cut

sub set_options {
	my $hashref = shift;

	my ($key, $value);
	while (($key, $value) = each %$hashref) {
		$options{lc $key} = $value;
	}
}

=item get_option

  my $value = get_option($key);
  my $value = get_option($key, $default_value);

Gets a global configuration option.  If the $key was never set,
$default_value is returned.

=cut

sub get_option {
	my $option = shift;
	my $default = shift || 0;

	if (exists $options{lc $option}) {
		return $options{lc $option};
	}
	return $default;
}

=item verbosity_level

  my $level = $config->verbosity_level();

Return the current verbosity level as a value 0-3, where 0 is the
quietest. This is affected by the --verbose and --quiet command line
options as well as by the "Verbose" setting in fink.conf. A --quiet
always takes precedence; otherwise the more verbose of the fink.conf
and cmdline values is used. The former documentation here described
the values as:

=over 4

=item 3

full

=item 2

download and tarballs

=item 1

download

=item 0

none

=back

=cut

{

my %verb_names = (
	true   => 3,
	high   => 3,
	medium => 2,
	low    => 1,
);

sub verbosity_level {
	my $self = shift;

	# fink.conf field (see Configure.pm)
	my $verbosity = $self->param_default("Verbose", 1);

	# cmdline flags (see fink.in)
	my $runtime = get_option("verbosity");

	return 0 if $runtime == -1;

	# convert keywords to values (or 0 if keyword is bogus)
	if ($verbosity =~ /\D/) {
		$verbosity = exists $verb_names{lc $verbosity} ? $verb_names{lc $verbosity} : 0;
	}

	# take higher value (== more verbose) of fink.conf and cmdline
	$verbosity = $runtime if $runtime > $verbosity;

	# sanity check: don't exceed maximum known value
	$verbosity = 3 if $verbosity > 3;

	return $verbosity;
}
}

=item binary_requested

	my $boolean = $config->binary_requested();

Determine whether the binary distribution or compilation has been requested.
This is affected by the --use-binary-dist and --compile-from-source
command line options as well as by the "UseBinaryDist" setting in fink.conf.
A command-line flag takes precedence over a fink.conf setting.
Returns 1 for binary distribution, 0 for compile-from-source.

=cut

sub binary_requested {
	my $self = shift;

	my $runtime_request = get_option("use_binary");
	my $binary_request;

	if ($runtime_request == -1) {
		$binary_request = 0;
	} elsif ($runtime_request == 1) {
		$binary_request = 1;
	} elsif ($self->param_boolean("UseBinaryDist")) {
		$binary_request = 1;
	} else {
		$binary_request = 0;
	}
	return $binary_request;
}

=item has_flag

  my $bool = $config->has_flag($flag);

Check for the existence of a configuration flag.

=item set_flag

  $config->set_flag($flag);

Set a configuration flag. Modified configuration can be saved with save().

=item clear_flag

  $config->clear_flag($flag);

Clear a configuration flag. Modified configuration can be saved with save().

=cut

sub read_flags {
	my $self = shift;
	unless (defined $self->{_flags}) {
		my @flags = split(' ', $self->param_default('Flags', ''));
		$self->{_flags} = { map { $_ => 1 } @flags };
	}
}	

sub has_flag {
	my ($self, $flag) = @_;
	$self->read_flags;
	return exists $self->{_flags}->{$flag};
}

sub set_flag {
	my ($self, $flag) = @_;
	$self->read_flags;
	$self->{_flags}->{$flag} = 1;
	$self->set_param('Flags', join(' ', keys %{$self->{_flags}}));
}

sub clear_flag {
	my ($self, $flag) = @_;
	$self->read_flags;
	delete $self->{_flags}->{$flag};
	$self->set_param('Flags', join(' ', keys %{$self->{_flags}}));
}

=back

=head2 Exported Variables

These variables are exported on request.  They are initialized by creating
a Fink::Config object.

=over 4

=item $basepath

Path to the base of the Fink installation directory.

Typically F</sw>.

=item $buildpath

Directory where fink packages will be built.  

Typically F<$basepath/src>

=item $config

The last Fink::Config object created.

=item $debarch

Debian-style name of the current architecture.  

Typically C<darwin-powerpc>.

=item $distribution

Fink package distribution being used.

For example, C<10.2>.

=item $dbpath

Where fink stores it's database files.

=item $libpath

XXX Don't understand this one.


=back


=head1 SEE ALSO

L<Fink::Base>

=cut

1;
