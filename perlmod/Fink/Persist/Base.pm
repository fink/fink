# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Persist::Base class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2005 The Fink Package Manager Team
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

package Fink::Persist::Base;

use Fink::Persist qw(&exists_object &getdbh);
use Fink::Persist::TableHash qw(&check_version &freeze &all_with_props);
use Fink::Base;
use Fink::Config qw($basepath &get_option);

require Exporter;
our @ISA = qw(Exporter Fink::Base);
our @EXPORT_OK = qw(&fink_dbh &fink_db);
our %EXPORT_TAGS = ( ALL => [@EXPORT, @EXPORT_OK] );

use strict;
use warnings;

our $VERSION = 1.00;

END {	}			# module clean-up code here (global destructor)


=head1 NAME

Fink::Persist::Base - Fink::Base optionally backed by a database

=head1 SYNOPSIS

  package My::FinkBacked;
  require Fink::Base;
  @ISA = qw(Fink::Base);
  
  my $filename = fink_db;
  my $dbh = fink_dbh;  
  
  my $obj = My::FinkBacked->new_from_properties({ key1 => val1, ...});
  my $val = $obj->param($param);
  $obj->set_param($param, $val);
  
  
  # On a subsequent run
  my @objs = My::FinkBacked->select_by_params(key1 => val1, ...);

=head1 DESCRIPTION

Fink::Persist::Base and classes that inherit from it act almost exactly like regular Fink::Base descendents--except that they are backed by a database.

=head2 Class methods

=over 4

=item fink_db

  $filename = fink_db;

Get the database file which may be used to store Fink::Persist::Base and
subclasses thereof.

=cut 

sub fink_db {
	return "$basepath/var/db/fink.sqlite";
}


=item fink_dbh

  $dbh = fink_dbh;

Get the database handle which will be used to store Fink::Persist::Base and
subclasses thereof. If no database will be used, a false value is returned.

=cut 

sub fink_dbh {
	return (get_option("persistence", "sqlite") eq "sqlite")
		&& getdbh fink_db;
}


=begin private

  $base = Fink::Persist::Base->table_base;
  
Get the basename for tables for this class.

=end private

=cut

sub table_base {
	my $proto = shift;
	my $class = (ref($proto) || $proto);
	
	return [ __PACKAGE__, $class ];
}


=item select_by_params

  @objs = Fink::Persist::Base->select_by_params(key1 => val1, ...);
  
Get all known objects of this class with the matching parameters. Returns undef
if the DB is not being used.

=cut

sub select_by_params {
	return undef unless fink_dbh; # && check_version fink_dbh;
	
	my $proto = shift;
	my $class = ref($proto) || $proto;
	
	my %params = @_;
	my $base = $class->table_base;
	
	return map { bless $_, $class } all_with_props(fink_dbh, $base, \%params);
}


=back

=head2 Constructors

=over 4

=item new_no_init

  my $obj = Fink::Base->new_no_init;

I<Protected method, do not call directly>.

Create a new fink object but don't initialize it. All other constructors should
use this method.

=cut

sub new_no_init {
	my $proto = shift;
	
	if (fink_dbh && check_version fink_dbh) {
		my $class = ref($proto) || $proto;
		my $self = Fink::Persist::TableHash->new(fink_dbh, table_base($class));
		return bless($self, $class);
	} else {
		return $proto->SUPER::new_no_init($proto);
	}
}


=back

=head1 CAVEATS

All issues that apply to Fink::Persist::TableHash apply to this class and it's descendants, as well.

=cut
	
1;
