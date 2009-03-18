# this script should only be installed when Architecture is i386
if [ $osMajorVer -gt 9 ]; then
  VERSIONER_PERL_PREFER_32_BIT=yes
  export VERSIONER_PERL_PREFER_32_BIT
fi
