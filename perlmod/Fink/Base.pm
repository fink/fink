#
# Fink::Base class
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

package Fink::Base;

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

END { }				# module clean-up code here (global destructor)

### empty constructor

sub new {
	my $proto = shift;
	my $class = ref($proto) || $proto;

	my $self = {};
	bless($self, $class);

	$self->initialize();

	return $self;
}

### contruct from hashref

sub new_from_properties {
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $properties = shift;

	my $self = {};
	bless($self, $class);

	my ($key, $value);
	while (($key, $value) = each %$properties) {
		$self->{$key} = $value
			unless substr($key,0,1) eq "_";
	}

	$self->initialize();

	return $self;
}

### self-initialization

sub initialize {
}

### retrieve parameter, returns undef if not found

sub param {
	my $self = shift;
	my $param_name = lc shift || "";

	if (exists $self->{$param_name}) {
		return $self->{$param_name};
	}
	return undef;
}

### retreive parameter, return default value if not found

sub param_default {
	my $self = shift;
	my $param_name = lc shift || "";
	my $default_value = shift;
	if (not defined $default_value) {
		$default_value = "";
	}

	if (exists $self->{$param_name}) {
		return $self->{$param_name};
	}
	return $default_value;
}

### retreive boolean parameter, false if not found

sub param_boolean {
	my $self = shift;
	my $param_name = lc shift || "";
	my $param_value;

	if (exists $self->{$param_name}) {
		$param_value = lc $self->{$param_name};
		if ($param_value =~ /^\s*(true|yes|on|1)\s*$/) {
			return 1;
		}
	}
	return 0;
}

### check if parameter exists

sub has_param {
	my $self = shift;
	my $param_name = lc shift || "";

	if (exists $self->{$param_name}) {
		return 1;
	}
	return 0;
}



### EOF
1;
