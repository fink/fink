PREFIX=/sw
ARCHITECTURE=x86_64
VERSION=`cat VERSION`
TEST_BASEPATH=$(PWD)/t/basepath
TESTS=.

all:
	@echo    "usage: $(MAKE) <target>"
	@echo    ""
	@echo -e "\tbootstrap   install a fresh fink installation"
	@echo -e "\t            PREFIX can be set, defaults to /sw"   
	@echo -e "              ARCHITECTURE can also be set, defaults to x86_64"   
	@echo -e "\tinstall     install to an existing fink installation"
	@echo -e "\ttest        perform tests on the fink code"
	@echo -e "\tclean       remove all extraneous files"
	@echo    ""

bootstrap: test
	./bootstrap $(PREFIX)

install:
	./inject.pl $(PREFIX)

test_setup:
	./setup.sh $(TEST_BASEPATH) $(ARCHITECTURE)

manifest_check:
	perl -MExtUtils::Manifest=fullcheck -e 'my($$missing, $$extra) = fullcheck;exit (@$$missing || @$$extra)'

test: manifest_check test_setup
	@# must test with same perl binary as the one to be used to run fink
	@# (which also must be coded into t/Services/execute_nonroot_okay.t)
	cd t && ./testmore.pl && find ${TESTS} -name '*.t' | sort | PREFIX="$(PREFIX)" xargs /usr/bin/perl -I`pwd`/../perlmod -MTest::Harness -e 'runtests(@ARGV)'

# remove various generated files
clean:
	rm -f compiler_wrapper 
	rm -f compiler_wrapper-10.7
	rm -f compiler_wrapper-10.9
	rm -f config*
	rm -f fink
	rm -f fink-dpkg-status-cleanup
	rm -f fink-virtual-pkgs
	rm -f fink-instscripts
	rm -f fink-scanpackages
	rm -f fink.8
	rm -f fink.conf.5
	rm -f pathsetup.command
	rm -f pathsetup.sh
	rm -f postinstall.pl
	rm -f shlibs.default
	rm -f dpkg-lockwait
	rm -f apt-get-lockwait
	rm -f g++-wrapper-3.3
	rm -f g++-wrapper-4.0
	rm -f perlmod/Fink.pm
	rm -f perlmod/Fink/FinkVersion.pm
	rm -f t/basepath/etc/apt/sources.list
	rm -f t/basepath/etc/apt/sources.list.finkbak

# maybe we should clean or ./setup.sh before this, to eliminate dups?
podcheck:
	@find . -name '.git' -prune -o \! -name '.#*' -type f -print | \
		xargs grep -l '[=]head' | xargs podchecker

.PHONY: all bootstrap install test test_setup manifest_check clean podcheck

.SUFFIXES:

# vim: ts=4 sw=4 noet
