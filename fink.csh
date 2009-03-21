# this script should only be installed when Architecture is i386
set osMajorVersion = `uname -r | cut -d. -f1`

if ( $osMajorVersion > 9 ) then
  setenv VERSIONER_PERL_PREFER_32_BIT yes
endif
