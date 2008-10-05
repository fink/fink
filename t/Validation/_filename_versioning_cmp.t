# -*- mode: Perl; tab-width: 4; -*-

use warnings;
use strict;

use Test::More 'no_plan';
#use Data::Dumper;


# this is a private function, not exported
require_ok('Fink::Validation');
can_ok('Fink::Validation', '_filename_versioning_cmp');

# save a lot of typing
sub _f {
    &Fink::Validation::_filename_versioning_cmp(@_);
}

# check $ext handling
ok( !defined &_f('foo', 'foo.1.dylib', 'dylib'), 'undef if f1 no ext');
ok( !defined &_f('foo.dylib', 'foo.1', 'dylib'), 'undef if f2 no ext');
ok( defined &_f('foo.dylib', 'foo.1.dylib', 'dylib'), 'def if both ext');
ok( defined &_f('foo', 'foo.1'), 'def if no ext given');
ok( !defined &_f('foodylib', 'foodylib', 'dylib'), 'remember period before ext');
ok( !defined &_f('foo.dylib', 'foo.dylib', 'd.lib'), 'not fooled by metachars in ext for f1');
ok( !defined &_f('foo.d.lib', 'foo.dylib', 'd.lib'), 'not fooled by metachars in ext for f2');

# check use of pathnames
cmp_ok( &_f('/foo', '/foo'), '==', 0, 'same paths');
ok( !defined &_f('/foo', '/x/foo'), 'same filename, different path');
ok( !defined &_f('foo', '/foo'), 'filename vs absolute path to same filename');
ok( !defined &_f('foo', 'foo/foo'), 'filename vs relative path to same filename');
ok( !defined &_f('libfoo.dylib', 'libbar.dylib'), 'different filenames');
ok( !defined &_f('libfoo.1.dylib', 'libfoo.11.dylib', 'dylib'), 'respects version atoms');

# make sure we're really doing substring tests
ok( !defined &_f('libf.ot', 'libfoot.1'), 'not fooled by metachars in f1 substr');
ok( !defined &_f('libfoot.1', 'libf.ot'), 'not fooled by metachars in f2 substr');

# comparison tests
cmp_ok( &_f('libfoo.1.dylib', 'libfoo.dylib', 'dylib'), '==', 1, 'first more versioned than second');
ok( defined &_f('libfoo.1.dylib', 'libfoo.1.dylib', 'dylib'), 'first same versioned than second is defined');
cmp_ok( &_f('libfoo.1.dylib', 'libfoo.1.dylib', 'dylib'), '==', 0, 'first same versioned than second');
cmp_ok( &_f('libfoo.dylib', 'libfoo.1.dylib', 'dylib'), '==', -1, 'first less versioned than second');
