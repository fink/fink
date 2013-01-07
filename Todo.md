Minor
=====

* make sure the man pages are complete and up-to-date

* validator should error if a field is there more than once (done in parent, not yet in splitoffs).

* long validator wishlist in Validation.pm

* Validator should complain if %p/share/gtk-doc is not in a package which is BuildDependsOnly: true

Medium
======

* replace "`fink list --help`" by a general "`fink --help [command]`" similar to how CVS does it (e.g. try "`cvs -H update`")

* add a mirror check utility that given some testcases will verify that all mirrors do still work
  
* when Fink asks a user to choose between alternatives, it should remember the choice. (But will this ever break building?)

* when a package is very new, the source is not yet on a master. This case is very common and needs to be dealt with much better.

Major
=====
* rewrite the dependency code
  -> added Conflicts / BuildConflicts support

* it might be useful to sync the finkinfodb as a single file per-tree, via `rsync`. This way users don't have to download all the .info files. Profiling would be needed. And what about .patch?

* Spotlight might be able to notice new .info files for Fink, so updating can happen in the background.

* There should be a better way than `passwd` for packages to use new user/groups. See branch UID/GID.

* As much as possible of fink should work as non-root. Especially important that '`fink build`' should work, in case we ever want to use a build farm.
