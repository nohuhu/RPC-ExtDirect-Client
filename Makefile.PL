use 5.006000;
use ExtUtils::MakeMaker;

# Add the `devtest` target to run regression and POD tests in one go
sub MY::postamble {
    return <<'END';
devtest :
	REGRESSION_TESTS=1 POD_TESTS=1 $(MAKE) test

END
}

# Override `disttest` so it would behave as `devtest`
sub MY::dist_test {
    return <<'END';
disttest : distdir
	cd $(DISTVNAME) && $(ABSPERLRUN) Makefile.PL
	cd $(DISTVNAME) && $(MAKE) $(PASTHRU)
	cd $(DISTVNAME) && $(MAKE) devtest $(PASTHRU)

END
}

my $mm_version = $ExtUtils::MakeMaker::VERSION;

WriteMakefile(
    NAME         => 'RPC::ExtDirect::Client',
    VERSION_FROM => 'lib/RPC/ExtDirect/Client.pm',

    ($mm_version >= 6.55
        ? ( BUILD_REQUIRES => {
                'RPC::ExtDirect::Server' => '1.0',
                'Test::More'             => 0,
            },
            PREREQ_PM => {
                'RPC::ExtDirect'         => '3.0',
                'HTTP::Tiny'             => '0.014',
            },
        )
        : ( PREREQ_PM => {
                'RPC::ExtDirect::Server' => '1.0',
                'RPC::ExtDirect'         => '3.0',
                'HTTP::Tiny'             => '0.014',
                'Test::More'             => 0,
            },
        )
    ),

    ABSTRACT => 'Ext.Direct client in Perl',
    AUTHOR   => 'Alex Tokarev <tokarev@cpan.org>',
    LICENSE  => 'perl',

    ($mm_version >= 6.46
        ? ( META_MERGE => {
                resources => {
                    bugtracker => 'http://github.com/nohuhu/RPC-ExtDirect-Client/issues',
                    repository => 'http://github.com/nohuhu/RPC-ExtDirect-Client',
                },
            },
        )
        : ()
    ),
);

