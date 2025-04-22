# This code is part of distribution Mojolicious::Plugin::OpenConsole.  It is licensed under the
# same terms as Perl itself: https://spdx.org/licenses/Artistic-2.0.html

use strict;
use warnings;
use utf8;
use 5.014;

use ExtUtils::MakeMaker;

my $git_url = 'https://github.com/markov2/perl5-Mojolicious-Plugin-OpenConsole';

WriteMakefile(
    NAME             => 'Mojolicious::Plugin::OpenConsole',
    VERSION          => '0.10',
    AUTHOR           => 'Mark Overmeer <markov@cpan.org>',
    PREREQ_PM        => {
		'DateTime::Format::ISO8601' => 0,
		'DateTime'        => 0,
		'HTTP::Status'    => 0,
        'Log::Report'     => 1.32,
		'Mojolicious'     => 0,
		'Mojo::UserAgent' => 0,
		'Net::Domain'     => 0,
        'Scalar::Util'    => 0,
		'Session::Token'  => 0,
    },
    test             => { TESTS         => 't/*.t' },
    clean            => { FILES         => '*.bak' },
    MIN_PERL_VERSION => '5.014000',
    META_MERGE       => {
        dynamic_config => 0,
        'meta-spec'    => { version   => 2 },
        no_index       => { directory => [ 't', 'xt', ] },
        prereqs        => { runtime   => {requires => {perl => '5.020000'}} },
        resources      => {
            bugtracker => { web => "$git_url/issues" },
            homepage   => 'http://perl.overmeer.net',
            license    => [ 'http://dev.perl.org/licenses/'],
            repository => {
                type => 'git',
                url => "$git_url.git",
                web => $git_url,
            },
        },
    },
);

sub MY::postamble { <<'__DIST' }
# for DIST
RAWDIR          = ../public_html/mojolicious-plugin-openconsole/raw
DISTDIR         = ../public_html/mojolicious-plugin-openconsole/source
LICENSE         = perl

# for POD
FIRST_YEAR      = 2025
EMAIL           = markov@cpan.org
WEBSITE         = http://perl.overmeer.net/CPAN/

__DIST
