PREFIX=/sw

all:
	@echo "usage: $(MAKE) <target>" && \
		echo "" && \
		echo -e "\tcommit         commit your changes" && \
		echo -e "\tbootstrap      install a fresh fink installation" && \
		echo -e "\tinstall        install to an existing fink installation" && \
		echo -e "\ttest           perform tests on the fink code" && \
		echo ""

	@echo "This is a dummy Makefile - only useful think is 'make test'"

commit: test
	@cvs commit

bootstrap: test
	@sh bootstrap.sh $(PREFIX)

install:
	./inject.pl

test:
	@cd t && find . -name '*.t' -not -iregex '.*\/Command\/.*' | xargs perl -I../perlmod -MTest::Harness -e 'runtests(@ARGV)'

.PHONY: all test install
