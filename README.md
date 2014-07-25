perl-Geo-WhatThreeWords
=======================

Perl CPAN module to turn WGS84 coordinates into three words or OneWords and vice-versa using w3w.co HTTP API



DEVELOPMENT

	dzil clean

	# running the test-suite
	TEST_AUTHOR=1 PERLLIB=./lib prove -r t/

	dzil build

	# git push, upload to CPAN
	dzil release


COPYRIGHT AND LICENCE

Copyright 2014 Lokku Ltd <cpan@lokku.com>


This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10 or,
at your option, any later version of Perl 5 you may have available.
