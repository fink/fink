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

use Fink::Command qw(&mkdir_p);
use Storable;
use File::Basename;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&getdbh);
our @EXPORT_OK = qw(&exists_object &all_objects &freeze &thaw $thaw_dbh
	&writeable &clear &set_read_only);
our %EXPORT_TAGS = ( ALL => [@EXPORT, @EXPORT_OK] );

use strict;
use warnings;

our $VERSION = 1.00;

our $thaw_dbh;
our %dbhs;
our %writeable_dbh;

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
  my $bool = writeable $dbh;
  clear $dbh;
  
  use Fink::Persist qw(:ALL);
  
  my @tbls = all_objects $dbh, 'table';
  if (exists_object $dbh, $tablename) { ... }
  
  my $val;
  $dbh->do(q{INSERT INTO table VALUES(?)}, {}, freeze($val));
  my @res = $dbh->selectrow_array(q{SELECT col FROM table});
  my $valcopy = thaw($res[0]);
  
  set_read_only $dbh;

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
			
	# Try to make any necessary directories
	my $dir = dirname($filename);
	mkdir_p($dir) unless -d $dir;
	
	my $dbh;
	# AutoCommit = 0 -> enable transactions
	unless ( $dbh = DBI->connect("dbi:SQLite:dbname=$filename", "", "",
			{ AutoCommit => 0, RaiseError =>1 }) ) {
		warn "Couldn't load database: $@";
		return 0;
	}
	$writeable_dbh{$dbh} = -w $filename;
	
	return $dbh;
}


=begin private

  $sql = perm_and_temp;
  
Get the SQL representing a table of both the permanent and temporary table lists.

=end private

=cut

sub perm_and_temp {
	return "(SELECT * FROM sqlite_master UNION ALL SELECT * FROM " .
		"sqlite_temp_master)";
}


=item exists_object

  $bool = exists_object $dbh, $tablename, $type;

Uses database-specific commands to determine whether a DB object exists. Type can be "table", "view" or "index".

=cut

sub exists_object {
	my ($dbh, $tablename, $type) = @_;
	
	eval {
		# FIXME: get table_info working
		
		# Assume it's SQLite
		my $sql = sprintf(q{SELECT name FROM %s WHERE type = ? and name = ?},
			perm_and_temp);
		return defined $dbh->selectrow_arrayref($sql, {}, $type, $tablename);
	} or return 0;
}


=item clear

  clear $dbh;

Get rid of everything in the database.

=cut

sub clear {
	my ($dbh) = @_;
	
	$dbh->do(qq{DROP VIEW $_}) foreach (all_objects($dbh, 'view'));
	$dbh->do(qq{DROP TABLE $_}) foreach (all_objects($dbh, 'table'));
}


=item writeable

  $bool = writeable $dbh;

Check if a database is writeable.

=cut

sub writeable {
	my ($dbh) = @_;
	
	return $writeable_dbh{$dbh};
}


=item set_read_only

  set_read_only $dbh;

Set a database to be read-only.

=cut

sub set_read_only {
	my ($dbh) = @_;
	
	$writeable_dbh{$dbh} = 0;
}


=item all_objects

  @tbls = all_objects $dbh, $type;
  @tbls = all_objects $dbh;

Get a list of all database objects of the given type (all types if no type given).

=cut

sub all_objects {
	my ($dbh, $type) = @_;
	
	my @objs = eval {
		# FIXME: get table_info working
		
		# Assume it's SQLite
		my $sql = q{SELECT name FROM } . perm_and_temp;
		$sql = $sql . q{ WHERE type = ?} if defined $type;
		
		my $objs = $dbh->selectcol_arrayref($sql, {},
			( defined $type ? ($type) : () ));
		return @$objs;
	};
	return ($@ ? () : @objs);
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
