# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Persist class
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

package Fink::Persist;

use Storable;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&getdbh);
our @EXPORT_OK = qw(&exists_table &tables &freeze &thaw $thaw_dbh);
our %EXPORT_TAGS = ( ALL => [@EXPORT, @EXPORT_OK] );

use strict;
use warnings;

our $VERSION = 1.00;

our $thaw_dbh;
our %dbhs;

END {				# module clean-up code here (global destructor)
	for my $dbh (values %dbhs) {
		$dbh->disconnect;
	}
}


=head1 NAME

Fink::Persist - utilities for persistence of objects

=head1 SYNOPSIS

  use Fink::Persist;
  
  my $dbh = getdbh $filename;
  
  
  use Fink::Persist qw(&exists_table &freeze &thaw);
  
  my @tbls = tables;
  if (exists_table $dbh, $tablename) { ... }
  
  my $val;
  $dbh->do(q{INSERT INTO table VALUES(?)}, {}, freeze($val));
  my @res = $dbh->selectrow_array(q{SELECT col FROM table});
  my $valcopy = thaw($res[0]);

=head1 FUNCTIONS

=over 4

=item getdbh

  $dbh = getdbh $filename;
  
Gets a database handle to a SQLite database stored in the given filehandle. If the database has been previously opened, will get the existing handle to that database. If the database cannot be loaded, returns false.

Databases will be opened in transaction mode, so changes must be committed by the caller at some point. All databases opened in this manner will be disconnected when perl exits.

=cut

sub getdbh {
	my $filename = shift;
	
	# Cache the value
	$dbhs{$filename} = getdbh_real($filename) unless exists $dbhs{$filename};
	return $dbhs{$filename};
}

sub getdbh_real {
	my $filename = shift;
	
	unless (eval { require DBI; }) {
		warn "Couldn't load database: DBI module not found";
		return 0;
	}
			
	my $dbh;
	unless ($dbh = DBI->connect("dbi:SQLite:dbname=$filename")) {
		warn "Couldn't load database: $@";
		return 0;
	}
	$dbh->{AutoCommit} = 0;  # enable transactions
	$dbh->{RaiseError} = 1;
	
	return $dbh;
}

=item exists_table

  $bool = exists_table $dbh, $tablename;

Uses database-specific commands to determine whether a table exists.

=cut

sub exists_table {
	my ($dbh, $tablename) = @_;
	
	eval {
		# FIXME: get table_info working
		
		# Assume it's SQLite
		my $sql = q{SELECT name FROM sqlite_master WHERE type='table' and name=?};
		return defined $dbh->selectrow_arrayref($sql, {}, $tablename);
	} or return 0;
}


=item tables

  @tbls = tables $dbh;

Get a list of all tables.

=cut

sub tables {
	my ($dbh) = @_;
	
	eval {
		# FIXME: get table_info working
		
		# Assume it's SQLite
		my $sql = q{SELECT name FROM sqlite_master WHERE type='table'};
		return @{$dbh->selectcol_arrayref($sql)};
	} or return ();
}


=item freeze

  $frozen = freeze($val);

Uses Storable to freeze a data structure into something that can be stored in a
database.

=cut

sub freeze {
	my $val = shift;
	
	my $frozen = Storable::freeze(\$val);
	
	# Deal with chr(0)
	$frozen =~ s,\\,\\\\,g;
	$frozen =~ s,\0,\\0,g;
	
	return $frozen;
}

=item thaw

  $val = thaw($dbh, $frozen);

Gets a value that was frozen using freeze, using the given $dbh.

=cut

sub thaw {
	my ($dbh, $frozen) = @_;
	
	$frozen =~ s,\\0,\0,g;
	$frozen =~ s,\\\\,\\,g;
	
	local $thaw_dbh = $dbh;
	return ${Storable::thaw($frozen)};
}

=back

=head1 ATTRIBUTES

=over 4

=item $thaw_dbh

  sub STORABLE_thaw {
      $dbh = $thaw_dbh;
  }
  
Allows a thawing object to determine the database handle it can use to help
itself thaw.

=back

=head1 CAVEATS

=head2 Use of table_info

It should be possible to find which tables exist using table_info, but that doesn't seem to work with SQLite.

=head2 Disconnecting

There's no obvious way to re-connect after a disconnect. 

=cut

1;
