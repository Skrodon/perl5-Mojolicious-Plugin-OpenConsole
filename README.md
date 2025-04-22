# Mojolicious::Plugin::OpenConsole

This plugin for the Mojolicious website framework for Perl, provides
a "Login via Open Console" button to authenticate users via the
Open Console infrastructure.  Open Console (<https://open-console.eu>)
provides OpenID-like features, but far extended in detail and fully
open: you are in full control of your personal facts and very strict
privacy by design.

The module is the reference implementation, because the Open Console
website is also build with Mojolicious.  It suggests how you can implement
your connector: in your framework and your preferred programming language.
Please consider to contribute your implementation.  Either as a full grown
and maintained module, or as code fragments: any contribution is welcomed.

## References

  * My extended documentation: <http://perl.overmeer.net/CPAN/>
  * Development via GitHub: <https://github.com/markov2/perl5-Mojolicious-Plugin-OpenConsole>
  * Download from CPAN: <ftp://ftp.cpan.org/pub/CPAN/authors/id/M/MA/MARKOV/>
  * Indexed from CPAN: <https://metacpan.org/release/Mojolicious-Plugin-OpenConsole>

## Development &rarr; Release

Important to know, is that I use an extension on POD to write the manuals.
The "raw" unprocessed version is visible on GitHub.  It will run without
problems, but does not contain manual-pages.

Releases to CPAN are different: "raw" documentation gets removed from
the code and translated into real POD and clean HTML.  This reformatting
is implemented with the OODoc distribution (A name I chose before OpenOffice
existed, sorry for the confusion)

Clone from github for the "raw" version.  For instance, when you want
to contribute a new feature.

On github, you can find the processed version for each release.  But the
better source is CPAN.  Simply:
```sh
   cpan -i Mojolicious::Plugin::OpenConsole
```

## Contributing

When you want to contribute to this module, you do not need to provide
a perfect patch... actually: it is nearly impossible to create a patch
which I will merge without modification.  Usually, I need to adapt the
style of code and documentation to my own strict rules.

When you submit an extension, please contribute a set with

1. code

2. code documentation

3. regression tests in t/

**Please note:**
When you contribute in any way, you agree to transfer the copyrights to
Mark Overmeer (you will get the honors in the code and/or ChangeLog).
You also automatically agree that your contribution is released under
the same license as this project: licensed as perl itself.

## Copyright and License

This project is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.
See <http://dev.perl.org/licenses/>
