use 5.006000;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME         => 'RPC::ExtDirect::Client',
    VERSION_FROM => 'lib/RPC/ExtDirect/Client.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.55
        ? ( BUILD_REQUIRES => {
                'RPC::ExtDirect::Server' => '1.0',
            },
            PREREQ_PM => {
                'RPC::ExtDirect'         => '3.0',
                'HTTP::Tiny'             => '0.014',
                'JSON'                   => '2.0',
            },
        )
        : ( PREREQ_PM => {
                'RPC::ExtDirect::Server' => '1.0',
                'RPC::ExtDirect'         => '3.0',
                'HTTP::Tiny'             => '0.014',
                'JSON'                   => '2.0',
            },
        )
    ),

    ABSTRACT => 'Ext.Direct client in Perl',
    AUTHOR   => 'Alex Tokarev <tokarev@cpan.org>',
    LICENSE  => 'perl',

    ($ExtUtils::MakeMaker::VERSION >= 6.46
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

