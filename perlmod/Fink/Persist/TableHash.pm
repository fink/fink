# -*- mode: Perl; tab-width: 4; -*-
#
# Fink::Persist::TableHash class
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

package Fink::Persist::TableHash;

use Fink::Persist qw(&getdbh &exists_table &thaw $thaw_dbh);
use Fink::Tie::Watch;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(&check_version &ensure_version);
our @EXPORT_OK = qw(&all_with_prop &all &exists_id &freeze &table_name);
our %EXPORT_TAGS = ( ALL => [@EXPORT, @EXPORT_OK] );

use strict;
use warnings;

our $VERSION = 1.00;

our $SCHEMA_VERSION = 1;


END { }				# module clean-up code here (global destructor)


=head1 NAME

Fink::Persist::TableHash - a hash backed by a database table

=head1 SYNOPSIS

  use Fink::Persist::TableHash;
  
  my $data_ok = ensure_version $dbh;
  
  my $hashref = Fink::Persist::TableHash->new($dbh, $base, $id);
  
  my $val = $hashref->{foo};
  $hashref->{bar} = [ 1, 2, 3 ];
  
    
  use Fink::Persist::TableHash qw(:ALL);
  
  my @ids = all_with_prop($dbh, $base, $key, $val);
  my @ids = all($dbh, $base);
  
  
  if (Fink::Persist::TableHash::exists_id($dbh, $base, $id)) { ... }  
  my $id = (tied $hashref)->id;
  
  my $tablename = table_name $base, "recs";
  
  my $frozen = freeze $data;


=head1 DESCRIPTION

Fink::Persist::TableHash allows a hash to backed by tables in a DBI database. Arbitrary data structures can be stored in the hash and retrieved from it using Storable.

The tables will be automatically created if needed. One table stores one record per id, another stores the properties of a hash as key, value pairs.

One TableHash can easily and safely be stored as a reference in another TableHash, but the same is not always true of other complex data structures. See L</Consistency>.

=head1 CONSTRUCTORS

=over 4

=item new

  $hashref = Fink::Persist::TableHash->new($dbh, $base, $id);
  $hashref = Fink::Persist::TableHash->new($dbh, $base);
  
Creates a new hash using the given database handle C<$dbh>, backed by tables with the basename C<$base>. The parameter C<$id> is a unique integer identifying this hash--all entries in the database with C<id> equal to C<$id> are considered to belong to this hash. If C<$id> is omitted, a new id will be generated.

Base may be an array reference, in which case the actual base will be constructed based on the items in the reference.

If the hash cannot be created, false is returned.

=back

=cut

sub new {
	my $class = shift;
	
	my $hashref = {};
	eval {
		tie %$hashref, (ref($class) || $class), @_;
	};
	if ($@) {
		warn "$@";
		return 0;
	}
	
	return $hashref;
}


=head1 CLASS METHODS

=over 4

=item exists_id

  $bool = exists_id $dbh, $base, $id;

Checks if an object with the given id already exists. Returns undef if the databse version is bad.

=cut

sub exists_id {
	my ($dbh, $base, $id) = @_;
	return undef unless check_version($dbh);
	
	my $recs = table_name($base, "recs");
	
	return 0 unless exists_table $dbh, $recs;
	
	my $slct = qq{SELECT id FROM $recs WHERE id = ?};
	return scalar($dbh->selectrow_array($slct, {}, $id));
}


=item ensure_version

  $data_ok = ensure_version $dbh;

Ensure a database is using the current format for TableHash. If so, returns true. If not, deletes the out-of-date data andd returns false.

=cut

sub ensure_version {
	my $dbh = shift;
	
	return 1 if check_version($dbh);
	
	# Bad version, try to get rid of everything
	
	my $tablelist = table_name("tablelist");
	if (exists_table $dbh, $tablelist) {
		my $tbls = $dbh->selectcol_arrayref(qq{SELECT name FROM $tablelist});
		if (defined $tbls) {
			foreach my $table (@$tbls) {
				$dbh->do(qq{DROP TABLE $table});
			}
		}
		
		$dbh->do(qq{DROP TABLE $tablelist});
	}
	
	my $verstbl = table_name("version");
	if (exists_table $dbh, $verstbl) {
		$dbh->do(qq{DROP TABLE $verstbl});
	}
	
	return 0;
}


=item check_version

  $data_ok = check_version $dbh;

Check if a database is using the current format for TableHash.

=cut

{
	my %vers_ok;
	
	sub check_version {
		my $dbh = shift;
		
		# Check again if it was false before
		$vers_ok{$dbh} = real_check_version($dbh) unless $vers_ok{$dbh};
		return $vers_ok{$dbh};
	}
	
	sub real_check_version {
		my $dbh = shift;
		
		my $verstbl = table_name("version");
		
		if (not exists_table $dbh, $verstbl) {
			$dbh->do(qq{CREATE TABLE $verstbl (vers INTEGER PRIMARY KEY)});
			add_table($dbh, $verstbl);
			
			$dbh->do(qq{INSERT INTO $verstbl VALUES(?)}, {}, $SCHEMA_VERSION);
			return 1;
		}
		
		my $vers = $dbh->selectcol_arrayref(qq{SELECT vers FROM $verstbl});
		return (defined $vers && scalar(@$vers) && $vers->[0] == $SCHEMA_VERSION);
	}
}

=begin private

  add_table $dbh, $tblname;

Ensure that the database knows that a new TableHash data table has been added.

=end private

=cut

sub add_table {
	my ($dbh, $tblname) = @_;
	
	my $tablelist = table_name("tablelist");
	
	if (not exists_table $dbh, $tablelist) {
		$dbh->do(qq{CREATE TABLE $tablelist (name PRIMARY KEY)});
		add_table($dbh, $tablelist);
	}
	
	$dbh->do(qq{INSERT INTO $tablelist VALUES(?)}, {}, $tblname);
}


=begin private

  $tablename = collapse_name [ "foo", [ "bar", "iggy" ], "blah" ];
  $tablename = collapse_name "foo";

Turn a basename (as a string or an array reference) into a table name.

=end private

=cut

sub collapse_name {
	my $base = shift;
	
	if (!ref $base) {		
		# Escape with underscores
		$base =~ s/_/__/g;
		$base =~ s/::/_C/g;
		return $base;
	} else {
		my @collapsed;
		push @collapsed, collapse_name($_) foreach (@$base);
		return join '_S', @collapsed;	
	}
}


=item table_name

  $tablename = table_name $base, $type;
  $tablename = table_name $type;

Get the name of a table from the basename and the type. The second form is for global tables.

=back

=cut

sub table_name {
	return collapse_name [ __PACKAGE__, @_ ];
}


=head1 METHODS

=over 4

=item id

  $id = $table_hash->id;

Gets the identifier of a TableHash.

=back

=cut

sub id {
	my $self = shift;
	return $self->{id};
}


=begin private

  $sub = $table_hash->callback($key, $val, $op)
  
Get a callback for a modification operation (-store, -delete, etc) of a watched reference.

The callback will perform a new store of the given key and value pair, ensuring that the database is kept up-to-date with the in-memory representation.

=end private

=cut
	
sub callback {
	my ($tablehash, $key, $ptr, $op) = @_;
	(my $meth_name = $op) =~ s/-(.*)/ucfirst $1/e;
	
	return sub {
		my $self = shift;
		my $meth = $self->can($meth_name);
		my $retval = &$meth($self, @_);
		$tablehash->STORE($key, $ptr); # re-store
		return $retval;
	}
}


=begin private

  ($type, $tied_obj, $watchable, $is_watched) = watched $refval;
  
  $is_watched = watched $refval;
  
Get informaton about whether a given reference is being watched:

=over 4

=item C<$type>
	
The type of the reference? HASH, ARRAY, etc. If non-ref, undef.

=item C<$tied_obj>

The object tied to this reference. If not tied, undef.

=item C<$watchable>

Whether this reference can be watched.

=item C<$is_watched>

Whether this reference actually is watched.

=back

=end private

=cut

sub watched {
	my $ptr = shift;
	
	my $type = ref($ptr);
	my ($tieobj, $watchable, $is_watched) = (undef, 0, 0);
	
	if (defined $type && ($type eq "ARRAY" || $type eq "HASH")) {
		$watchable = 1;
		$tieobj = ($type eq "ARRAY" ? tied @$ptr : tied %$ptr);
		
		if (defined $tieobj) {
			if (ref($tieobj) =~ /^Fink::Tie::Watch::/) {
				$is_watched = 1;
			} else {
				$watchable = 0;
			}
		}
	}
	
	return ($type, $tieobj, $watchable, $is_watched);
}


=begin private
  
  $watchedref = $table_hash->watch($key, $val);
  
Ensure a reference to a complex structure is being watched for modifications.

=end private

=cut

sub watch {
	my ($tablehash, $key, $ptr) = @_;
	my ($type, $tied_obj, $watchable, $is_watched) = watched $ptr;
	
	# Only change unwatched, watcheable references 
	return $ptr if $is_watched || !$watchable;
	
	# Which operations do we care about?
	my @ops = qw(-store -clear);
	if ($type eq "ARRAY") {
		push @ops, qw(-pop -push -shift -splice -storesize -unshift);
	} else {
		push @ops, '-delete'; # Hash
	}
	
	# Watch for modifications
	Fink::Tie::Watch->new(
		-variable => $ptr,
		map { $_ => $tablehash->callback($key, $ptr, $_)  } @ops
	);
	return $ptr;
}


=begin private
  
  $frozen = freeze $refval;
  
Freeze a reference, by-passing any extra data involved in watching it.

=end private

=cut

sub freeze {
	my ($ptr) = @_;
	my ($type, $tied_obj, $watchable, $is_watched) = watched $ptr;
	
	return Fink::Persist::freeze $ptr unless $is_watched;
	
	my %vinfo = $tied_obj->Info();
	return Fink::Persist::freeze $vinfo{-ptr};
}


=begin private
  
  unwatch $refval;
  
Stop watching a reference, if it's watched.

=end private

=cut

sub unwatch {
	my ($ptr) = @_;
	my ($type, $tied_obj, $watchable, $is_watched) = watched $ptr;
	
	$tied_obj->Unwatch if $is_watched;
}


=begin private
  
  my $table_hash = tie %hash, 'Fink::Persist::TableHash', $dbh, $base, $id;

=end private

=cut

sub TIEHASH {
	my ($class, $dbh, $base, $id) = (@_, undef);
	die "Bad version" unless check_version($dbh);
	
	my $recs = table_name $base, "recs";
	my $props = table_name $base, "props";
	
	if (not exists_table $dbh, $recs) {		
		# Make the basic table
		$dbh->do(qq{CREATE TABLE $recs (id INTEGER PRIMARY KEY)});
		add_table($dbh, $recs);
	}
	if (not exists_table $dbh, $props) {
		# Make the property table
		$dbh->do(qq{CREATE TABLE $props (id, key, value)});
		add_table($dbh, $props);
	}
	
	# Make sure a record exists for this hash
	my $slct = qq{SELECT id FROM $recs WHERE id = ?};
	if (!defined $id || ! $dbh->selectrow_array($slct, {}, $id)) {	
		my $insert = qq{INSERT INTO $recs VALUES(?)};
		$insert =~ s/\?/NULL/ unless defined $id;
		$dbh->do($insert, {}, defined $id ? $id : () );
		
		if (!defined $id) {
			$id = $dbh->last_insert_id((undef) x 4);
		}
	}
	
	return bless {
		dbh => $dbh,
		recs => $recs,
		props => $props,
		id => int($id),
	}, $class;
}

=begin private
  
  my @res = $table_hash->getval($key);

Get an array holding the value of a key, or an empty list if the key doesn't exist.

=end private

=cut

sub getval {
	my ($self, $key) = @_;
	my ($dbh, $props, $id) = @$self{qw/dbh props id/};
	
	my $sql = qq{SELECT value FROM $props WHERE id = ? and key = ?};
	return $dbh->selectrow_array($sql, {}, $id, $key);
}


sub FETCH {
	my ($self, $key) = @_;
	my @res = $self->getval($key);
	
	if (@res) {
		return $self->watch($key, thaw($self->{dbh}, $res[0]));
	} else {
		return;
	}
}

sub EXISTS {
	return scalar(getval(@_));
}

sub STORE {
	my ($self, $key, $value) = @_;
	my ($dbh, $props, $id) = @$self{qw/dbh props id/};
		
	$self->DELETE($key);
	
	my $sql = qq{INSERT INTO $props VALUES(?, ?, ?)};
	$dbh->do($sql, {}, $id, $key, freeze($value));
	$self->watch($key, $value)
}

sub DELETE {
	my ($self, $key) = @_;
	my ($dbh, $props, $id) = @$self{qw/dbh props id/};
	
	my $sql = qq{DELETE FROM $props WHERE id = ? and key = ?};
	$dbh->do($sql, {}, $id, $key);
}

sub CLEAR {
	my ($self) = @_;
	my ($dbh, $props, $id) = @$self{qw/dbh props id/};
	
	$dbh->do(qq{DELETE FROM $props WHERE id = ?}, {}, $id);
}

sub FIRSTKEY {
	my ($self) = @_;
	my ($dbh, $props, $id) = @$self{qw/dbh props id/};
	
	# Get the keys
	my $sql = qq{SELECT DISTINCT key FROM $props WHERE id = ?};
	my $ks = $dbh->selectcol_arrayref($sql, {}, $id);
	$self->{ks} = { map { $_ => 1 } @$ks };
	
	return scalar each %{$self->{ks}};
}

sub NEXTKEY {
	my ($self) = @_;
	return scalar each %{$self->{ks}};
}


=begin private

To allow storing these objects as references in the database, we need custom hooks for Storable.

=end private

=cut

{
	# Version of serialized format
	my $serialize_vers = 0;
	
	sub STORABLE_freeze {
		my ($self, $cloning) = @_;
		return if $cloning;
		
		my %info = %$self;
		delete $info{dbh};
		
		return ( $serialize_vers, \%info);
	}
	
	sub STORABLE_thaw {
		my ($self, $cloning, $serialized, $info) = @_;
		return if $cloning;
		
		while (my ($k, $v) = each %$info) {
			$self->{$k} = $v;
		}
		$self->{id} = int($self->{id});
		$self->{dbh} = $Fink::Persist::thaw_dbh;
	}
}			


=head1 FUNCTIONS

=over 4

=item all_with_prop

  @ids = all_with_prop($dbh, $base, $key, $val);
  
Gets all ids whose hashes have a given key set to a given value. Returns undef if the database is not the proper version.

=cut

sub all_with_prop {
	my ($dbh, $base, $key, $val) = @_;
	return undef unless check_version($dbh);

	my $props = table_name $base, "props";
	
	return () unless (exists_table $dbh, $props);
	
	my $sql = qq{SELECT DISTINCT id FROM $props WHERE key = ? AND value = ?};
	my $results = $dbh->selectcol_arrayref($sql, {}, $key, freeze($val));
	return @$results;
}


=item all

  @ids = all($dbh, $base);
  
Gets all ids in a table. Returns undef if the database is not the proper version.

=back

=cut

sub all {
	my ($dbh, $base) = @_;
	return undef unless check_version($dbh);

	my $recs = table_name $base, "recs";
	
	return () unless (exists_table $dbh, $recs);
	
	my $sql = qq{SELECT DISTINCT id FROM $recs};
	my $results = $dbh->selectcol_arrayref($sql, {});
	return @$results;
}


=head1 CAVEATS

=head2 Locking

No explicit locking at either the file or table level is performed at this time. The caller is responsible for any locking and transaction management. Locking may occur automatically, however.

=head2 Garbage collection

These hashes are never automatically garbage collected. They'll stay in the database forever unless the caller does something about it.

=head2 Consistency 

Complex structures can be stored as values, and changes to them will not necessarily be propagated to the database. Through use of Fink::Tie::Watch, changes to the top-level only will be propagated correctly:

  $complex = { foo => 1, bar => 2, both => [ 1, 2 ] };
  $h->{complex} = $complex;
  
  $complex->{foo} = 2; # Top-level, will be propagated to database
  
  push @{$complex->{both}}, 3; # Second level, will not be reflected in database

Such top-level references have restrictions on their use. They (and their referents) should not be serialized to any other location, including within other TableHashes or other keys within the same TableHash. One should also refrain from making changes to them (and their referents) after they have been removed from the hash or replaced with another value. In all these cases, prefer making a copy of the referent.

=head2 Database structure

The database is very unstructured. Hooks will be added at a later time to allow
better normalization.

=head2 Read-only access

There is no way to specify that changes to the hash should not be propagated. Workaround is to simply not commit changes.

=head2 Indexing

Tables are currently created without any indices, so access may not be very fast.

=head2 Caching

No results are cached at this time.

=cut

1;
