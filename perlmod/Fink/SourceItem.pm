#
# Fink::SourceItem class
#
# Fink - a package manager that downloads source and installs it
# Copyright (c) 2001 Christoph Pfisterer
# Copyright (c) 2001-2004 The Fink Package Manager Team
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

package Fink::SourceItem;
use Fink::Config qw($basepath);
use Fink::NetAccess qw(&fetch_url_to_file);
use Fink::Services qw(&expand_percent &filename);

use strict;
use warnings;

BEGIN {
	use Exporter ();
	our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);
	$VERSION	 = 1.00;
	@ISA		 = qw(Exporter);
	@EXPORT		 = qw();
	@EXPORT_OK	 = qw(&items_from_pkg &delete_fields_from_hash);
	%EXPORT_TAGS = ( );
}

END { }

# The Fink::SourceItem object is implemented as a blessed array using
# the following named constants:
use constant _PRIVATE        => 0;
use constant SOURCE          => 1;
use constant SOURCE_MD5      => 2;
use constant SOURCE_RENAME   => 3;
use constant TARFILES_RENAME => 4;
use constant EXTRACTDIR      => 5;
use constant CUSTOM_MIRRORS  => 6;
# The package database is simply a flattened version of the whole data
# structure so no need to bloat it with many copies of the keynames.
# But you should be using the accessor methods, not touching the
# actual instance data.

=item items_from_pkg

    my @items = Fink::SourceItem->items_from_pkg($pkg,\%expand);

Returns a list of Fink::SourceItem objects created using the .info
file stored in the $pkg. The list is ordered (but not indexed) by the
source field number. This function performs percent expansion (using
the hash %expand). The given $pkg is probably a Fink::PkgVersion, and
must be some sort of Fink::Base. It must contain (at least) the lines
of a .info file hashed by (case-insensitive) field.

=cut

sub items_from_pkg {
	my $namespace = shift;
	my $pkg = shift;

	my $expand = $pkg->get_expand_map;
	$expand = {} unless ref $expand;

	my @item_list = ();  # what we'll return

	# Build list of all source URLs. There's an implicit default
	# for Source so the field might not be present.
	# Schwartzian Transform to sort sourceN in "numerical" order.
	# It's harder to code and less efficient to sort if N="" is in
	# the list at this point.
	my @source_fields = $pkg->params_matching('source\d+');
	@source_fields = map { $_->[0] } sort { $a->[1] <=> $b->[1] }
		map { [$_, /source(\d*)/] } @source_fields;
	# But Source must always be considered
	unshift @source_fields, "source";

	# Loop through the Source and SourceN fields and assemble
	# array of associated data for each
	foreach my $source_field ("source", @source_fields) {
		$source_field =~ /source(\d*)/;
		my $number = $1;  # .info fields are source$number, etc.

		my $field; # convenience

		my $source_item = []; # the nascent object

		# there are some special behaviors for Source only
		if ($number eq "") {
			my $source = $pkg->param_default("Source", "\%n-\%v.tar.gz");
			if ($source eq "gnu") {
				$source = "mirror:gnu:\%n/\%n-\%v.tar.gz";
			} elsif ($source eq "gnome") {
				$pkg->get_version =~ /(^[0-9]+\.[0-9]+)\.*/;
				$source = "mirror:gnome:sources/\%n/$1/\%n-\%v.tar.gz";
			}
			$source_item->[SOURCE] = $source;
		} else {
			$source_item->[SOURCE] = $pkg->param($source_field);
		}
		$source_item->[SOURCE] = &expand_percent($source_item->[SOURCE], $expand);
		next if $source_item->[SOURCE] eq "none";

		if ($pkg->has_param("SourceRename".$number)) {
			$source_item->[SOURCE_RENAME] = &expand_percent($pkg->param("SourceRename".$number), $expand);
		}

		if ($pkg->has_param("Source".$number."-MD5")) {
			$source_item->[SOURCE_MD5] = $pkg->param("Source".$number."-MD5");
		}

		if ($pkg->has_param("Tar".$number."FilesRename")) {
			$source_item->[TARFILES_RENAME] = &expand_percent($pkg->param("Tar".$number."FilesRename"), $expand);
		}

		# ExtractDir doesn't make sense for main tarball
		if ($number ne "") {
			if ($pkg->has_param("Source".$number."ExtractDir")) {
				$source_item->[EXTRACTDIR] = &expand_percent($pkg->param("Source".$number."ExtractDir"), $expand);
			}
		}

		if ($pkg->has_param("CustomMirror")) {
			$source_item->[CUSTOM_MIRRORS] = &expand_percent($pkg->param("CustomMirror"), $expand);
		}

		bless $source_item, $namespace;
		push @item_list, $source_item;
	}

	return @item_list;
}

=item delete_fields_from_hash

    delete_fields_from_hash $pkg;

Deletes the keys from the package $pkg that are used to construct
items_from_hash. You probably want to store the objects returned by
items_from_hash before calling this function. The given $pkg is
probably a Fink::PkgVersion, and must be some sort of Fink::Base. It
must contain (at least) the lines of a .info file hashed by
(case-insensitive) field.

=cut

sub delete_fields_from_hash {
	my $pkg = shift;

	my @fields = ( $pkg->params_matching('source\d*'),
		       $pkg->params_matching('source\d*-md5'),
		       $pkg->params_matching('source\d*rename'),
		       $pkg->params_matching('tar\d*filesrename'),
		       $pkg->params_matching('source\d+extractdir'),
		       "CustomMirror"
		       );
	map { delete $pkg->{$_} } @fields;
}

=item get_source

    my $source = $item->get_source;

Returns the SourceN field.

=cut

sub get_source {
	my $self = shift;
	return $self->[SOURCE];
}

=item get_tarball

    my $filename = $item->get_tarball;

Returns filename of a Fink::SourceItem tarball. No directory hierarchy
is included. This is the actual local filename, taking into account
SourceRename.

=cut

sub get_tarball {
	my $self = shift;

	if (defined $self->[SOURCE_RENAME]) {
		return $self->[SOURCE_RENAME];
	} else {
		return &filename($self->[SOURCE]);
	}
}

=item get_checksum

    $md5 = $item->get_checksum;

Returns the expected MD5 checksum for the Source item. This is the
value taken from the SourceN-MD5 field, not the one calculated for the
downloaded file. If none was specified, a "-" is returned.

=cut

sub get_checksum {
	my $self = shift;
	if (defined $self->[SOURCE_MD5]) {
		return $self->[SOURCE_MD5];
	} else {
		return "-";
	}
}

=item have_tarfilesrename

    $need_BSD_tar = $item->have_tarfilesrename;

Returns a boolean indicating whether there is a TarFilesNRename field.

=cut

sub have_tarfilesrename {
	my $self = shift;
	return defined $self->[TARFILES_RENAME];
}

=item get_tarfilesrename_map

    while ( my($old,$new) = each %{$item->get_tarfilesrename_map} ) {
	$tar_args .= " -s,$old,$new,";
    }

Returns a ref to a hash mapping of files to be renamed from the tarball.

=cut

sub get_tarfilesrename_map {
	my $self = shift;
    
	return {} unless $self->have_tarfilesrename;

	my %map;
	my @renamefiles = split(/\s+/, $self->[TARFILES_RENAME]);
	foreach my $renamefile (@renamefiles) {
		if ($renamefile =~ /^(.+)\:(.+)$/) {
			$map{$1} = $2;
		} else {
			$map{$renamefile} = $renamefile."_tmp";
		}
	}
	return \%map;
}

=item get_extractdir

    my $destdir = $item->get_extractdir;

Returns the valuer of SourceNExtractDir (or undef if none was given).

=cut

sub get_extractdir {
	my $self = shift;
	return $self->[EXTRACTDIR];
}

=item fetch_source

    $item->fetch_source($pkg);
    $item->fetch_source($pkg, $tries);
    $item->fetch_source($pkg, $tries, $continue);
    $item->fetch_source($pkg, $tries, $continue, $nomirror);
    $item->fetch_source($pkg, $tries, $continue, $nomirror, $dryrun);

Downloads the source. The Fink::PkgVersion object for the package is
passed as $pkg. The parameters $tries, $continue, and $dryrun (which
default to zero or false if not given or not defined) do things, but I
don't know what. FIXME

If $nomirror is true, will not attempt to use any mirrors for downloading.

=cut

sub fetch_source {
	my $self = shift;
	my $pkg = shift;
	my $tries = shift || 0;
	my $continue = shift || 0;
	my $nomirror = shift || 0;
	my $dryrun = shift || 0;

	if($pkg->has_param("license")) {
		if($pkg->param("license") =~ /Restrictive\s*$/) {
			$nomirror = 1;
		} 
	}

	chdir "$basepath/src";

	my $url = $self->get_source;
	my $file = $self->get_tarball;

	if($dryrun) {
		return if $url eq $file; # just a simple filename
		print "$file ".$self->get_checksum;
	} else {
		if($self->get_checksum eq '-') {	
			print "WARNING: No MD5 specified for Source ".$url.
							" of package ".$pkg->get_fullname()."\n";
			if ($pkg->has_param("Maintainer")) {
				print 'Maintainer: '.$pkg->param("Maintainer")."\n";
			}		
		}
	}
	
	if (&fetch_url_to_file($url, $file, $self->[CUSTOM_MIRRORS], 
						   $tries, $continue, $nomirror, $dryrun)) {
		if (0) {
		print "\n";
		&print_breaking("Downloading '$file' from the URL '$url' failed. ".
						"There can be several reasons for this:");
		&print_breaking("The server is too busy to let you in or ".
						"is temporarily down. Try again later.",
						1, "- ", "	");
		&print_breaking("There is a network problem. If you are ".
						"behind a firewall you may want to check ".
						"the proxy and passive mode FTP ".
						"settings. Then try again.",
						1, "- ", "	");
		&print_breaking("The file was removed from the server or ".
						"moved to another directory. The package ".
						"description must be updated.",
						1, "- ", "	");
		&print_breaking("In any case, you can download '$file' manually and ".
						"put it in '$basepath/src', then run fink again with ".
						"the same command.");
		print "\n";
		}
		if($dryrun) {
			if ($pkg->has_param("Maintainer")) {
				print ' "'.$pkg->param("Maintainer") . "\"\n";
			}
		} else {
			die "file download failed for $file of package ".$pkg->get_fullname()."\n";
		}
	}
}

1;
