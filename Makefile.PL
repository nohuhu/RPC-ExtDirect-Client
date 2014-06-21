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

my $MM_VERSION = $ExtUtils::MakeMaker::VERSION;
my $github_uri = 'https://github.com/nohuhu/RPC-ExtDirect-Client';

WriteMakefile(
    NAME         => 'RPC::ExtDirect::Client',
    VERSION_FROM => 'lib/RPC/ExtDirect/Client.pm',
    
    ($MM_VERSION >= 6.46
        ? (
            TEST_REQUIRES => {
                'RPC::ExtDirect::Server'     => '1.01',
                'Test::More'                 => '0.82', # for explain()
            },
            PREREQ_PM => {
                'RPC::ExtDirect'             => '3.01',
                'HTTP::Tiny'                 => '0.014',
            },
        )
        : ($MM_VERSION >= 6.55
            ? ( BUILD_REQUIRES => {
                    'RPC::ExtDirect::Server' => '1.01',
                    'Test::More'             => '0.82',
                },
                PREREQ_PM => {
                    'RPC::ExtDirect'         => '3.01',
                    'HTTP::Tiny'             => '0.014',
                },
            )
            : ( PREREQ_PM => {
                    'RPC::ExtDirect::Server' => '1.01',
                    'Test::More'             => '0.82',
                    'RPC::ExtDirect'         => '3.01',
                    'HTTP::Tiny'             => '0.014',
                },
            )
        )
    ),

    ABSTRACT => 'Ext.Direct client in Perl',
    AUTHOR   => 'Alex Tokarev <tokarev@cpan.org>',
    LICENSE  => 'perl',

    ($MM_VERSION >= 6.48
        ? ( MIN_PERL_VERSION => 5.006000, )
        : ()
    ),

    ($MM_VERSION >= 6.46
        ? ( META_MERGE => {
                resources => {
                    bugtracker => "$github_uri/issues",
                    repository => $github_uri,
                },
            },
        )
        : ()
    ),
);
