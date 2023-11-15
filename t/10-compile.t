#!perl -w

use strict;
use warnings;

eval 'use Test::Compile';

if($@) {
	plan(skip_all => 'Test::Compile needed to verify module compiles');
} else {
	my $test = Test::Compile->new();
	# https://github.com/nigelhorne/Weather-Meteo/issues/4:
	#	Don't check bin/weather
	$test->all_files_ok('lib');
	$test->done_testing();
}
