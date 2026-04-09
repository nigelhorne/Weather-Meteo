# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.6.2';

requires 'CHI';
requires 'Encode';
requires 'ExtUtils::MakeMaker', '6.64';
requires 'JSON::MaybeXS';
requires 'LWP::Protocol::https';
requires 'LWP::UserAgent';
requires 'Object::Configure';
requires 'Params::Get', '0.13';
requires 'Params::Validate::Strict';
requires 'Return::Set';
requires 'Scalar::Util';
requires 'Time::HiRes';
requires 'URI';
requires 'constant';

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
