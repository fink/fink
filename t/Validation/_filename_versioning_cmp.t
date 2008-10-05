# -*- mode: Perl; tab-width: 4; -*-

use warnings;
use strict;

use Test::More tests => 34;


# this is a private function, not exported
require_ok('Fink::Validation');
can_ok('Fink::Validation', '_filename_versioning_cmp');

# save a lot of typing
sub _f {
    &Fink::Validation::_filename_versioning_cmp(@_);
}

# check $ext handling (tests 3-14)
ok( defined &_f('foo', 'foo.1.dylib', 'dylib'), 'f1 no ext (def)');
ok( ! &_f('foo', 'foo.1.dylib', 'dylib'), 'f1 no ext (bool)');
ok( defined &_f('foo.dylib', 'foo.1', 'dylib'), 'f2 no ext (def)');
ok( ! &_f('foo.dylib', 'foo.1', 'dylib'), 'f2 no ext (bool)');

ok( &_f('foo.dylib', 'foo.1.dylib', 'dylib'), 'true if both ext');
ok( &_f('foo', 'foo.1'), 'true if no ext given');
ok( defined &_f('foodylib', 'foodylib', 'dylib'), 'remember period before ext (def)');
ok( ! &_f('foodylib', 'foodylib', 'dylib'), 'remember period before ext (bool)');
ok( defined &_f('foo.dylib', 'foo.dylib', 'd.lib'), 'not fooled by metachars in ext for f1 (def)');
ok( ! &_f('foo.dylib', 'foo.dylib', 'd.lib'), 'not fooled by metachars in ext for f1 (bool)');
ok( defined &_f('foo.d.lib', 'foo.dylib', 'd.lib'), 'not fooled by metachars in ext for f2 (def)');
ok( ! &_f('foo.d.lib', 'foo.dylib', 'd.lib'), 'not fooled by metachars in ext for f2 (bool)');

# check use of full pathnames not just filename (tests 15-26)
ok( &_f('/foo', '/foo'), 'same paths (bool)');
cmp_ok( &_f('/foo', '/foo'), '==', 0, 'same paths (val)');
ok( defined &_f('/foo', '/x/foo'), 'same filename, different path (def)');
ok( ! &_f('/foo', '/x/foo'), 'same filename, different path (bool)');
ok( defined &_f('foo', '/foo'), 'filename vs absolute path to same filename (def)');
ok( ! &_f('foo', '/foo'), 'filename vs absolute path to same filename (bool)');
ok( defined &_f('foo', 'foo/foo'), 'filename vs relative path to same filename (def)');
ok( ! &_f('foo', 'foo/foo'), 'filename vs relative path to same filename (bool)');
ok( defined &_f('libfoo.dylib', 'libbar.dylib'), 'different filenames (def)');
ok( ! &_f('libfoo.dylib', 'libbar.dylib'), 'different filenames (bool)');
ok( defined &_f('libfoo.1.dylib', 'libfoo.11.dylib', 'dylib'), 'respects version atoms (def)');
ok( ! &_f('libfoo.1.dylib', 'libfoo.11.dylib', 'dylib'), 'respects version atoms (bool)');

# make sure we're really doing substring tests (tests 27-30)
ok( defined &_f('libf.ot', 'libfoot.1'), 'not fooled by metachars in f1 substr (def)');
ok( ! &_f('libf.ot', 'libfoot.1'), 'not fooled by metachars in f1 substr (bool)');
ok( defined &_f('libfoot.1', 'libf.ot'), 'not fooled by metachars in f2 substr (def)');
ok( ! &_f('libfoot.1', 'libf.ot'), 'not fooled by metachars in f2 substr (bool)');

# normal comparison tests (tests 31-34)
cmp_ok( &_f('libfoo.1.dylib', 'libfoo.dylib', 'dylib'), '==', 1, 'first more versioned than second');
ok( &_f('libfoo.1.dylib', 'libfoo.1.dylib', 'dylib'), 'first same versioned as second (bool)');
cmp_ok( &_f('libfoo.1.dylib', 'libfoo.1.dylib', 'dylib'), '==', 0, 'first same versioned as second (val)');
cmp_ok( &_f('libfoo.dylib', 'libfoo.1.dylib', 'dylib'), '==', -1, 'first less versioned than second');
