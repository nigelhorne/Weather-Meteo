#!perl -wT

use strict;

use lib 'lib';
use Test::Most tests => 3;
use Weather::Meteo;

isa_ok(Weather::Meteo->new(), 'Weather::Meteo', 'Creating Weather::Meteo object');
isa_ok(Weather::Meteo::new(), 'Weather::Meteo', 'Creating Weather::Meteo object');
isa_ok(Weather::Meteo->new()->new(), 'Weather::Meteo', 'Cloning Weather::Meteo object');
# ok(!defined(Weather::Meteo::new()));
