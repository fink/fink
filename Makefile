PREFIX=/sw
VERSION=`cat VERSION`
TEST_BASEPATH=$(PWD)/t/basepath
TESTS=.

all:
	@echo    "usage: $(MAKE) <target>"
	@echo    ""
	@echo -e "\tcommit      commit your changes"
	@echo -e "\tbootstrap   install a fresh fink installation"
	@echo -e "\t            PREFIX can be set, defaults to /sw"   
	@echo -e "\tinstall     install to an existing fink installation"
	@echo -e "\ttest        perform tests on the fink code"
	@echo -e "\tclean       remove all extraneous files"
	@echo    ""

commit: test
	@cvs commit

bootstrap: test
	@sh bootstrap.sh $(PREFIX)

install:
	./inject.pl

test_setup:
	@./setup.sh $(TEST_BASEPATH)

test: test_setup
	@# must test with same perl binary as the one to be used to run fink
	@# (which also must be coded into t/Services/execute_nonroot_okay.t)
	@cd t && ./testmore.pl && find ${TESTS} -name '*.t' | sort | xargs /usr/bin/perl -I${PWD}/perlmod -MTest::Harness -e 'runtests(@ARGV)'

# remove all files that are ignored by CVS
clean:
	# BUG: this for...`find` breaks if any dirname relative to the
	# current one contains whitespace
	@for ignorefile in `find . -name .cvsignore`; do \
		echo "cleaning $$ignorefile"; \
		( cd `dirname $$ignorefile` && rm -f `cat .cvsignore` ); \
	done

.PHONY: all test install
# vim: ts=4 sw=4 noet
