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

use Fink::Persist;
use Fink::Persist::TableHash qw(&storable);
use Fink::Base;
use Fink::Config qw($basepath &get_option);

require Exporter;
our @ISA = qw(Exporter Fink::Base);
our @EXPORT_OK = qw(&fink_db);
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

  $dbh = fink_db;

Get the database handle which will be used to store Fink::Persist::Base and
subclasses thereof. If no database will be used, a false value is returned.

=cut 

sub fink_db {
	return (get_option("persistence", "sqlite") eq "sqlite")
		&& getdbh "$basepath/var/db/fink.sqlite";
}


=item table_prefix

  $prefix = Fink::Persist::Base->prefix;

Get the table prefix corresponding to this class.

=cut

sub table_prefix {
	my $proto = shift;
	my $prefix = ref($proto) || $proto;
	
	# Escape colons with underscores
	$prefix =~ s/_/__/g;
	$prefix =~ s/::/_c/g;
	return $prefix;
}


=item select_by_params

  @objs = Fink::Persist::Base->select_by_params(key1 => val1, ...);
  
Get all known objects of this class with the matching parameters. Returns undef
if the DB is not being used.

=cut

sub select_by_params {
	return undef unless fink_db;
	
	my $proto = shift;
	my $class = ref($proto) || $proto;
	my $prefix = $proto->table_prefix;
	my $props = "${prefix}_props";
	
	my %params = @_;
	my @ks = keys %params;
	
	my ($sql, @binds);
	
	unless (scalar(@ks)) {
		$sql = qq{SELECT id FROM $prefix};
	} else {
		$sql = qq{SELECT t1.id FROM $props AS t1};
		my @where = q{t1.key = ? AND t1.value = ?};
		
		for (my $i = 2; $i <= scalar(@ks); ++$i) {
			$sql .= qq{ JOIN $props AS t$i ON t1.id = t$i.id};
			push @where, qq{t$i.key = ? AND t$i.value = ?};
		}
		
		$sql .= q{ WHERE } . join(q{ AND }, @where);
		
		map { $_ = storable $_ } values %params;
	}
	
	return map {
		bless Fink::Persist::TableHash->new(fink_db, table_prefix($class), $_),
			$class
	} @{ fink_db->selectcol_arrayref($sql, {}, %params) };
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
	
	if (fink_db) {
		my $class = ref($proto) || $proto;
		my $self = Fink::Persist::TableHash->new(fink_db, table_prefix($class));
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
