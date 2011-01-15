# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Mirror module
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

package Fink::Mirror;

use Fink::Services qw(&read_properties &read_properties_multival_var &read_properties_multival);
use Fink::CLI qw(&prompt_selection);
use Fink::Config qw($config $libpath);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	%EXPORT_TAGS = ( );			# eg: TAG => [ qw!name1 name2! ],

	# your exported package globals go here,
	# as well as any optionally exported functions
	@EXPORT_OK	 = qw();
}
our @EXPORT_OK;

our $MAX_MIRROR_FAILURE = 2;
our $failed_mirrors = {};
my %named_mirrors = ();

END { }				# module clean-up code here (global destructor)


### get mirror by name (class method, caches objects)

sub get_by_name {
	shift;	# class method
	my $name = shift;
	my ($mirror);

	if (exists $named_mirrors{$name}) {
		return $named_mirrors{$name};
	}
	$mirror = Fink::Mirror->new_from_name($name);
	$named_mirrors{$name} = $mirror;
	return $mirror;
}

### constructor from name (for configurable mirrors)

sub new_from_name {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $name = shift;

	my $self = {};
	bless($self, $class);

	$self->{name} = $name;

	my $mirrorfile = "$libpath/mirror/$name";
	# set default values for critical mirrors, in case mirror directory
	# is not present
	my %mirrordefaults = (
		"master" => "Primary: http://distfiles.master.finkmirrors.net/",
		"rsync" => "Primary: rsync://master.us.finkmirrors.net/finkinfo/",
		"sourceforge" => "Primary: http://west.dl.sourceforge.net/sourceforge/",
		);
	my ($key, $mirrordefault);
	if (not -f $mirrorfile) {
		foreach $key ( keys %mirrordefaults ) {
			if ($name eq $key) {
				$mirrordefault = $mirrordefaults{$key}."\n";
				$self->{data} = &read_properties_multival_var("",$mirrordefault);
				$self->initialize();
				return $self;
			}
		}
		die "No mirror site list file found for mirror '$name'.\n";
	}
	$self->{data} = &read_properties_multival($mirrorfile);

	# Extract the timestamp, and delete it from the hash.
	$self->{timestamp} = $self->{data}->{timestamp};
	delete $self->{data}->{timestamp};

	$self->initialize();

	return $self;
}

### construct from field contents (for inline custom mirrors)

sub new_from_field {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $field = shift;
	my $package = shift || "unknown package";

	my $self = {};
	bless($self, $class);

	$self->{name} = "Custom (package-defined) servers";
	$self->{package} = $package;

	my ($key, $url);
	$self->{data} = {};
	foreach (split /^/m, $field) {
		next if /^\s*\#/;		# skip comments
		if (/^\s*([0-9A-Za-z_.\-]+)\:\s*(\S.*?)\s*$/) {
			$key = lc $1;
			$url = $2;
#		 } elsif (/^\s+(\S.*?)\s*$/) {
#			 $key = "primary";
#			 $url = $1;
		} else {
			next;
		}

		if (exists $self->{data}->{$key}) {
			push @{$self->{data}->{$key}}, $url;
		} else {
			$self->{data}->{$key} = [ $url ];
		}
	}

	$self->initialize();

	return $self;
}
### construct from single url (for sites without mirrors, to use master mirrors also)

sub new_from_url {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my $url = shift;
  my $package = shift || "unknown package";

  my $self = {};
  bless($self, $class);

  $self->{name} = "Original URL";
  $self->{package} = $package;

  $self->{data}->{"primary"} = [ $url ];

  $self->initialize();

  return $self;

}

### merge master mirror set into this one (used for master 'ClosestFirst' mirror)

sub merge_master_mirror {
	my $self = shift;
	my $mirror = shift;
	my ($key, $list, $url);
	$DB::single = 1;	

	foreach $key (keys %{$mirror->{data}}){	
		if (exists $self->{data}->{$key}) {
			for $url (@{ $mirror->{data}->{$key} }) {
				(my $masterurl = $url) =~ s/^/master:/;
				push @{$self->{data}->{$key}}, $masterurl;
			}
		} else {
			@{ $self->{data}->{$key} } = @{ $mirror->{data}->{$key} };
			s/^/master:/ for (@{ $self->{data}->{$key} });
		}
	}
 	
  	delete $self->{data}->{timestamp};
}

### self-initialization

sub initialize {
	my $self = shift;

	$self->{lastused} = "";
	$self->{failed} = {};
	$self->{tries} = 0;
}

### get a url (no previous tries)

sub get_site {
	my $self = shift;
	my ($name, $url, $level, @list);

	if ($self->{lastused}) {
		$url = $self->{lastused};
		$url .= "/" unless $url =~ /\/$/;
		return $url;
	}

	$name = $self->{name};
	if ($name !~ /Custom|Original/) {
		# check the configuration for named mirrors
		if ($Fink::Config::config->has_param("mirror-$name")) {
			$self->{lastused} = $url = $Fink::Config::config->param("mirror-$name");
			$url .= "/" unless $url =~ /\/$/;
			return $url;
		}
	}

	# pick one at random
	for ($level = 1; $level <= 3; $level++) {
		@list = $self->list_by_level($level);
		next if $#list < 0;

		$self->{lastused} = $url = $list[int(rand(scalar(@list)))];
		$url .= "/" unless $url =~ /\/$/;
		return $url;
	}

	# nothing found, not even primaries
	if ($name =~ /Custom/) {
		$name = "custom mirror of ".$self->{package};
	} else {
		$name = "mirror '$name'";
	}
	die "Can't find a site for $name, not even a primary one\n";
}

### get a url for retries after the previous failed
# returns "" when the user chooses to give up

sub get_site_retry {
	my $self = shift;
	my $next_set = shift || "";
	my $printmode = shift || 0;
	my ($result, $level, @choice_list, $default, $url, $last_set);
	my (@list_country, @list_continent, @list_world);

	# hmm, someone called us without calling get_site() on the initial try
	if (not $self->{lastused}) {
		return $self->get_site();
	}

	# record the failure
	$self->{tries}++;
	$self->{failed}->{$self->{lastused}} = 1;

	# if this hits $MAX_MIRROR_FAILURE, that mirror will be skipped in subsequent downloads
	$failed_mirrors->{$self->{lastused}}++;

	# get lists of remaining mirrors
	@list_country   = $self->list_not_failed_by_level(1);
	@list_continent = $self->list_not_failed_by_level(2);
	@list_world     = $self->list_not_failed_by_level(3);

	# assemble choices
	@choice_list = ( "error", "retry" );
	$default = 2;
	if ($#list_country >= 0) {
		push @choice_list, "retry-country";
		$default = 3;
	}
	if ($#list_continent > $#list_country) {
		push @choice_list, "retry-continent";
		$default = 3;
	}
	if ($#list_world > $#list_continent) {
		push @choice_list, "retry-world";
		$default = 3;
		if ($self->{tries} >= 3) {
			$default = $#choice_list + 1;
		}
	}
	if (!$printmode && $self->{tries} >= 5) {
		$default = 1;
	}
	if ($next_set ne "") {
		push @choice_list, "retry-next";
		
		# If two masters fail, and the masters come first, assume it's a new
		# file that hasn't yet reached the masters rather than going through
		# every single master.
		my $finish_master = $self->{name} eq 'master'
			&& $config->param_default('MirrorOrder', '') eq 'MasterFirst'
			&& $self->{tries} >= 2;
		
		# No more mirrors in this set or finished master, default to next
		if($#choice_list == 2 || $finish_master) {
			$default = $#choice_list + 1;
		}
	}
	# ask the user
	if($printmode) {
		# just printing URLs, never ask, never retry same mirror
		if($default == 2) {
			$default = 1;
		}
		$result = $choice_list[$default - 1];
	} else {
		my $nexttext;
		if($next_set eq "Original URL") {
			$nexttext = "Retry using original source URL";
		} else {
			$nexttext = "Retry using next mirror set \"$next_set\"";
		}
		my %choices = (
			"error" => "Give up",
			"retry" => "Retry the same mirror",
			"retry-country" => "Retry another mirror from your country",
			"retry-continent" => "Retry another mirror from your continent",
			"retry-world" => "Retry another mirror",
			"retry-next" => $nexttext,
		);
		my @choices = map { ( $choices{$_} => $_ ) } @choice_list;
		$result =
		&prompt_selection(
			"How do you want to proceed?",
			default  => [ number => $default ],
			choices  => \@choices,
			category => 'fetch',
			timeout  => 120,
		);
	}
	$url = $self->{lastused};
	if ($result eq "error") {
		return "";
	} elsif ($result eq "retry") {
		# nothing to do
	} elsif ($result eq "retry-country") {
		if ($#list_country >= 0) {
			$url = $list_country[int(rand(scalar(@list_country)))];
		}
	} elsif ($result eq "retry-continent") {
		if ($#list_continent >= 0) {
			$url = $list_continent[int(rand(scalar(@list_continent)))];
		}
	} elsif ($result eq "retry-world") {
		if ($#list_world >= 0) {
			$url = $list_world[int(rand(scalar(@list_world)))];
		}
	} elsif ($result eq "retry-next") {
		return $result;
	}
	$self->{lastused} = $url;
	$url .= "/" unless $url =~ /\/$/;
	return $url;
}

### get a list of primary sites

sub list_primary {
	my $self = shift;
	my ($site, @list);

	@list = ();
	foreach $site (@{$self->{data}->{primary}}) {
		push @list, $site;
	}

	return @list;
}

### get a list of geographical sites by level
# level: 0 - configured (-> empty list)
#				 1 - country
#				 2 - continent
#				 3 - world (includes primaries)

### list mirrors by level which have not
# a) failed for this particular download and
# b) failed at least $MAX_MIRROR_FAILURE times on any download

sub list_not_failed_by_level {
	my $self  = shift;
	my $level = shift;

	return grep {
		not exists $self->{failed}->{$_} and
		(
			not exists $failed_mirrors->{$_} or
			$failed_mirrors->{$_} < $MAX_MIRROR_FAILURE
		)
	} $self->list_by_level($level);
}

sub list_by_level {
	my $self = shift;
	my $level = shift;
	my ($site, @list, $key, $match);

	@list = ();
	if ($level <= 0) {
		return @list;
	} elsif ($level == 1) {
		$match = lc $config->param_default("MirrorCountry", "nam-us");
	} elsif ($level == 2) {
		$match = lc $config->param_default("MirrorContinent", "nam");
	} else {
		$match = "";
	}

	foreach $key (keys %{$self->{data}}) {
		if ($key =~ /^$match/) {
			foreach $site (@{$self->{data}->{$key}}) {
				push @list, $site;
			}
		}
	}

	return @list;
}


### EOF
1;
# vim: ts=4 sw=4 noet
