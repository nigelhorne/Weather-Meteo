package Weather::Meteo;

use strict;
use warnings;

use Carp;
use Encode;
use JSON::MaybeXS;
use HTTP::Request;
use LWP::UserAgent;
use LWP::Protocol::https;
use URI;

=head1 NAME

Weather::Meteo - Interface to L<https://open-meteo.com> for historical weather data

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

      use Weather::Meteo

      my $meteo = Weather::Meteo->new();
      my $weather = $meteo->weather({ latitude => '0.1', longitude => '0.2', date => '2022-12-25' });

=head1 DESCRIPTION

Geo::Coder::CA provides an interface to geocoder.ca.

=head1 METHODS

=head2 new

    $geo_coder = Geo::Coder::CA->new();
    my $ua = LWP::UserAgent->new();
    $ua->env_proxy(1);
    $geo_coder = Geo::Coder::CA->new(ua => $ua);

=cut

sub new {
	my($class, %args) = @_;

	if(!defined($class)) {
		# Geo::Coder::CA::new() used rather than Geo::Coder::CA->new()
		$class = __PACKAGE__;
	} elsif(ref($class)) {
		# clone the given object
		return bless { %{$class}, %args }, ref($class);
	}

	my $ua = $args{ua};
	if(!defined($ua)) {
		$ua = LWP::UserAgent->new(agent => __PACKAGE__ . "/$VERSION");
		$ua->default_header(accept_encoding => 'gzip,deflate');
	}
	my $host = $args{host} || 'archive-api.open-meteo.com';

	return bless { ua => $ua, host => $host }, $class;
}

=head2 weather

    $location = $geo_coder->geocode(location => $location);
    # @location = $geo_coder->geocode(location => $location);

    print 'Latitude: ', $location->{'latt'}, "\n";
    print 'Longitude: ', $location->{'longt'}, "\n";

=cut

sub weather {
	my $self = shift;
	my %param;

	if(ref($_[0]) eq 'HASH') {
		%param = %{$_[0]};
	} elsif(ref($_[0])) {
		Carp::croak('Usage: weather(latitude => $latitude, longitude => $logitude, date => "YYYY-MM-DD")');
		return;
	} elsif(@_ % 2 == 0) {
		%param = @_;
	}

	my $latitude = $param{latitude};
	my $longitude = $param{longitude};
	my $date = $param{'date'};

	if(!defined($latitude)) {
		Carp::croak('Usage: weather(latitude => $latitude, longitude => $logitude, date => "YYYY-MM-DD")');
		return;
	}

	my $uri = URI->new("https://$self->{host}/v1/archive");
	my %query_parameters = (
		'latitude' => $latitude,
		'longitude' => $longitude,
		'start_date' => $date,
		'end_date' => $date,
		'hourly' => 'temperature_2m,rain,snowfall,weathercode',
		'timezone' => 'Europe/London',
		'windspeed_unit' => 'mph',
		'precipitation_unit' => 'inch'
	);
	$uri->query_form(%query_parameters);
	my $url = $uri->as_string();

	$url =~ s/%2C/,/g;

	my $res = $self->{ua}->get($url);

	if($res->is_error()) {
		Carp::croak("$url API returned error: ", $res->status_line());
		return;
	}
	# $res->content_type('text/plain');	# May be needed to decode correctly

	my $json = JSON::MaybeXS->new()->utf8();
	if(my $rc = $json->decode($res->decoded_content())) {
		if($rc->{'error'}) {
			# Sorry - you lose the error code, but HTML::GoogleMaps::V3 relies on this
			# TODO - send patch to the H:G:V3 author
			return;
		}
		if(defined($rc->{'hourly'})) {
			return $rc;	# No support for list context, yet
		}
	}

	# my @results = @{ $data || [] };
	# wantarray ? @results : $results[0];
}

=head2 ua

Accessor method to get and set UserAgent object used internally. You
can call I<env_proxy> for example, to get the proxy information from
environment variables:

    $geo_coder->ua()->env_proxy(1);

You can also set your own User-Agent object:

    my $ua = LWP::UserAgent::Throttled->new();
    $ua->throttle('geocoder.ca' => 1);
    $geo_coder->ua($ua);

=cut

sub ua {
	my $self = shift;
	if (@_) {
		$self->{ua} = shift;
	}
	$self->{ua};
}

=head2 run

You can also run this module from the command line:

    perl CA.pm 1600 Pennsylvania Avenue NW, Washington DC

=cut

__PACKAGE__->run(@ARGV) unless caller();

sub run {
	require Data::Dumper;

	my $class = shift;

	my $location = join(' ', @_);

	my @rc = $class->new()->geocode($location);

	if(scalar(@rc)) {
		print Data::Dumper->new([\@rc])->Dump();
	} else {
		die "$0: geo-coding failed";
	}
}

=head1 AUTHOR

Nigel Horne, C<< <njh@bandsman.co.uk> >>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at open-meteo.com.

=head1 BUGS

Should be called Geo::Coder::NA for North America.

=head1 SEE ALSO

=head1 LICENSE AND COPYRIGHT

Copyright 2023 Nigel Horne.

This program is released under the following licence: GPL2

=cut

1;
