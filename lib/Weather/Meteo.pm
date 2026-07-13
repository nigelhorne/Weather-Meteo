package Weather::Meteo;

use strict;
use warnings;

use Carp;
use CHI;
use JSON::MaybeXS;
use LWP::UserAgent;
use Object::Configure;
use Params::Get 0.13;
use Params::Validate::Strict;
use Return::Set;
use Scalar::Util;
use Time::HiRes;
use URI;

use constant FIRST_YEAR     => 1940;
use constant EXPIRES_IN     => '1 hour';
use constant MIN_INTERVAL   => 0;	# default: no rate-limiting delay
use constant FORECAST_HOST  => 'api.open-meteo.com';

=head1 NAME

Weather::Meteo - Interface to L<https://open-meteo.com> for historical and forecast weather data

=head1 VERSION

Version 0.14

=cut

our $VERSION = '0.14';

=head1 SYNOPSIS

The C<Weather::Meteo> module provides an interface to the Open-Meteo API for retrieving
historical weather data from 1940 and weather forecasts up to 16 days ahead.
It allows users to fetch weather information by specifying latitude, longitude, and a date.
The module supports object-oriented usage and allows customization of the HTTP user agent.

      use Weather::Meteo;

      my $meteo = Weather::Meteo->new();

      # Historical weather
      my $weather = $meteo->weather({ latitude => 0.1, longitude => 0.2, date => '2022-12-25' });

      # Forecast (default 7 days)
      my $forecast = $meteo->forecast({ latitude => 51.34, longitude => 1.42 });

      # Sunrise and sunset for a specific date
      my $times = $meteo->sunrise_sunset({ latitude => 51.34, longitude => 1.42, date => '2025-06-21' });
      print "Sunrise: $times->{sunrise}\n";

=over 4

=item * Caching

Identical requests are cached (using L<CHI> or a user-supplied caching object),
reducing the number of HTTP requests to the API and speeding up repeated queries.

This module leverages L<CHI> for caching geocoding responses.
When a geocode request is made,
a cache key is constructed from the request.
If a cached response exists,
it is returned immediately,
avoiding unnecessary API calls.

=item * Rate-Limiting

A minimum interval between successive API calls can be enforced to ensure that the API is not overwhelmed and to comply with any request throttling requirements.

Rate-limiting is implemented using L<Time::HiRes>.
A minimum interval between API
calls can be specified via the C<min_interval> parameter in the constructor.
Before making an API call,
the module checks how much time has elapsed since the
last request and,
if necessary,
sleeps for the remaining time.

=back

=head1 METHODS

=head2 new

    my $meteo = Weather::Meteo->new();
    my $ua = LWP::UserAgent->new();
    $ua->env_proxy(1);
    $meteo = Weather::Meteo->new(ua => $ua);

    my $weather = $meteo->weather({ latitude => 51.34, longitude => 1.42, date => '2022-12-25' });
    my @snowfall = @{$weather->{'hourly'}->{'snowfall'}};

    print 'Number of cms of snow: ', $snowfall[1], "\n";

Creates a new instance. Acceptable options include:

=over 4

=item * C<cache>

A caching object.
If not provided,
an in-memory cache is created with a default expiration of one hour.

=item * C<host>

The API host endpoint.
Defaults to L<https://archive-api.open-meteo.com>.

=item * C<min_interval>

Minimum number of seconds to wait between API requests.
Defaults to C<0> (no delay).
Use this option to enforce rate-limiting.

=item * C<ua>

An object to use for HTTP requests.
If not provided, a default user agent is created.

=back

The class can be configured at runtime using environments and configuration files,
for example,
setting C<$ENV{'WEATHER__METEO__carp_on_warn'}> causes warnings to use L<Carp>.
For more information about runtime configuration,
see L<Object::Configure>.

=head3 API specification

=head4 Input

All parameters are optional.
They may be supplied as a hashref or a flat key/value list.
When C<$class> is an existing C<Weather::Meteo> object the call clones it,
merging any supplied parameters.

    {
        ua           => { type => 'object', can => 'get', optional => 1 },
        cache        => { type => 'object',               optional => 1 },
        host         => { type => 'scalar',               optional => 1 },
        min_interval => { type => 'scalar',               optional => 1 },
    }

=head4 Output

    { type => 'object', isa => 'Weather::Meteo' }

=head3 FORMAL SPECIFICATION

    ___ NEW ___________________________________________________
    | class?        : PACKAGE | Weather::Meteo               |
    | params?       : NAME |--> VALUE                         |
    |___________________________________________________________|
    | result!       : Weather::Meteo                          |
    |                                                          |
    | blessed(result!) = 'Weather::Meteo'                     |
    |                                                          |
    | params?.ua?    => result!.ua    = params?.ua             |
    | ~params?.ua    => result!.ua    : LWP::UserAgent         |
    | params?.cache? => result!.cache = params?.cache          |
    | ~params?.cache => result!.cache : CHI(Memory, global)    |
    | params?.host?  => result!.host  = params?.host           |
    | ~params?.host  => result!.host  = 'archive-api.open-meteo.com' |
    | params?.min_interval? => result!.min_interval = params?.min_interval |
    | ~params?.min_interval => result!.min_interval = 0        |
    | result!.last_request  = 0                                |
    |___________________________________________________________|
    |                                                          |
    | PRE:  class? is PACKAGE name or blessed Weather::Meteo  |
    | POST: blessed(result!) = 'Weather::Meteo'               |
    |       forall k in params? . result!.k = params?.k       |
    |___________________________________________________________|

=cut

sub new {
	my $class = shift;
	my $params = Params::Get::get_params(undef, \@_) || {};

	if(!defined($class)) {
		# Weather::Meteo::new() used rather than Weather::Meteo->new()
		$class = __PACKAGE__;
	} elsif(Scalar::Util::blessed($class)) {
		# If $class is an object, clone it with new arguments
		# Clone path: merge new params over the existing object's fields.
		if(exists($params->{ua})) {
			if(!defined($params->{ua})) {
				# ua=>undef means "keep the original" -- silently drop it
				delete $params->{ua};
			} elsif(!Scalar::Util::blessed($params->{ua}) || !$params->{ua}->can('get')) {
				# A defined ua must be a proper object with a get() method
				Carp::croak("'ua' argument must be an object with a get() method");
			}
		}
		return bless { %{$class}, %{$params} }, ref($class);
	}

	$params = Object::Configure::configure($class, $params);

	my $ua = $params->{ua};
	if(!defined($ua)) {
		$ua = LWP::UserAgent->new(agent => __PACKAGE__ . "/$VERSION");
		$ua->default_header(accept_encoding => 'gzip,deflate');
	}
	my $host = $params->{host} || 'archive-api.open-meteo.com';

	# Set up caching (default to an in-memory cache if none provided)
	my $cache = $params->{cache} || CHI->new(
		driver => 'Memory',
		global => 1,
		expires_in => EXPIRES_IN,
	);

	# Set up rate-limiting: minimum interval between requests (in seconds)
	my $min_interval = $params->{min_interval} || MIN_INTERVAL;

	return bless {
		min_interval => $min_interval,
		last_request => 0,	# Initialize last_request timestamp
		%{$params},
		cache => $cache,
		host => $host,
		ua => $ua
	}, $class;
}

=head2 weather

    use Geo::Location::Point;

    my $ramsgate = Geo::Location::Point->new({ latitude => 51.34, longitude => 1.42 });
    # Print snowfall at 1AM on Christmas morning in Ramsgate
    $weather = $meteo->weather($ramsgate, '2022-12-25');
    @snowfall = @{$weather->{'hourly'}->{'snowfall'}};

    print 'Number of cms of snow: ', $snowfall[1], "\n";

    use DateTime;
    my $dt = DateTime->new(year => 2024, month => 2, day => 1);
    $weather = $meteo->weather({ location => $ramsgate, date => $dt });

The date argument can be an ISO-8601 formatted string (C<YYYY-MM-DD>),
or any object that supports C<strftime>.

Takes an optional C<tz> argument containing the time zone.
If not given, the module tries to derive it from the location object;
set C<TIMEZONEDB_KEY> to your API key from L<https://timezonedb.com> to enable that.
If all else fails, the module falls back to C<Europe/London>.

Dates before 1940 return C<undef> silently.
Invalid date strings cause a C<carp> and return C<undef>.
Missing required arguments or non-numeric coordinates cause a C<croak>.

On success returns a hashref with at minimum an C<hourly> key.
The C<daily> key includes C<sunrise> and C<sunset> as ISO-8601 datetime strings
(e.g. C<2022-12-25T08:09>), as well as temperature, precipitation, and wind fields.
Returns C<undef> if the API returns an error, if the JSON cannot be
parsed, or if the response contains no C<hourly> key.

=head3 API specification

=head4 Input

Three call forms are accepted.

    # Form 1 and 2 -- hashref or flat list
    {
        latitude  => { type => 'scalar' },
        longitude => { type => 'scalar' },
        date      => { type => 'scalar | object' },
        tz        => { type => 'scalar', optional => 1 },
        location  => { type => 'object', can => 'latitude', optional => 1 },
    }

    # Form 3 -- positional: ($location_obj, $date)
    # $location_obj must respond to latitude() and longitude()

=head4 Output

    { type => 'hashref', min => 1 }   # success -- contains 'hourly' key
    undef                              # pre-1940 date, bad input, or API error

=head3 FORMAL SPECIFICATION

    ___ WEATHER _______________________________________________
    | self?      : Weather::Meteo                            |
    | latitude?  : REAL                                       |
    | longitude? : REAL                                       |
    | date?      : DATE_STRING | strftime_OBJECT              |
    | tz?        : STRING  (optional, default 'Europe/London')|
    |____________________________________________________________|
    | result!    : HASHREF | undef                            |
    |____________________________________________________________|
    |                                                          |
    | PRE (~latitude? v ~longitude? v ~date?)                 |
    |   => croak /Usage: weather\(latitude/                   |
    |                                                          |
    | PRE lat? or lon? not matching /^-?\d+(\.\d+)?$/         |
    |   (after leading-decimal normalisation)                  |
    |   => croak /Invalid latitude\/longitude format/          |
    |                                                          |
    | PRE date? blessed ^ date?.can('strftime')               |
    |   => date? := date?.strftime('%F')                       |
    |   PRE date? !~ /^\d{4}-\d{2}-\d{2}$/                   |
    |     => croak /Invalid date format. Expected YYYY-MM-DD/ |
    |                                                          |
    | PRE year(date?) < 1940                                   |
    |   => result! = undef                                     |
    |                                                          |
    | POST cache hit for (lat, lon, date, tz)                 |
    |   => result! = cached_value                              |
    |                                                          |
    | POST HTTP error response                                 |
    |   => carp msg ^ result! = undef                          |
    |                                                          |
    | POST JSON parse failure                                  |
    |   => carp /Failed to parse JSON response/ ^ result! = undef |
    |                                                          |
    | POST response.error = true                               |
    |   => result! = undef                                     |
    |                                                          |
    | POST ~response.hourly                                    |
    |   => result! = undef                                     |
    |                                                          |
    | POST otherwise                                           |
    |   => result! = { hourly => HOURLY, daily => DAILY }     |
    |      cache.set(key, result!)                             |
    |____________________________________________________________|

=cut

sub weather
{
	my $self = shift;
	my $params;

	if((scalar(@_) == 2) && Scalar::Util::blessed($_[0]) && ($_[0]->can('latitude'))) {
		# Two arguments - a location object and a date
		my $location = $_[0];
		$params->{latitude} = $location->latitude();
		$params->{longitude} = $location->longitude();
		$params->{'date'} = $_[1];
		if($_[0]->can('tz') && $ENV{'TIMEZONEDB_KEY'}) {
			$params->{'tz'} = $_[0]->tz();
		}
	} else {
		$params = Params::Get::get_params(undef, \@_);
	}

	my $latitude = $params->{latitude};
	my $longitude = $params->{longitude};
	my $location = $params->{'location'};
	my $date = $params->{'date'};
	my $tz = $params->{'tz'} || 'Europe/London';

	if((!defined($latitude)) && defined($location) &&
	   Scalar::Util::blessed($location) && $location->can('latitude')) {
		$latitude = $location->latitude();
		$longitude = $location->longitude();
	}
	if((!defined($latitude)) || (!defined($longitude)) || (!defined($date))) {
		if(my $logger = $self->{'logger'}) {
			$logger->error('Usage: weather(latitude => $latitude, longitude => $longitude, date => "YYYY-MM-DD")');
		}
		Carp::croak('Usage: weather(latitude => $latitude, longitude => $longitude, date => "YYYY-MM-DD")');
		return;
	}

	# Handle numbers starting with a decimal point
	if($latitude =~ /^\./) {
		$latitude = "0$latitude";
	}
	if($latitude =~ /^\-\.(\d+)$/) {
		$latitude = "-0.$1";
	}
	if($longitude =~ /^\./) {
		$longitude = "0$longitude";
	}
	if($longitude =~ /^\-\.(\d+)$/) {
		$longitude = "-0.$1";
	}

	if(($latitude !~ /^-?\d+(\.\d+)?$/) || ($longitude !~ /^-?\d+(\.\d+)?$/)) {
		if(my $logger = $self->{'logger'}) {
			$logger->error(__PACKAGE__ . ": Invalid latitude/longitude format ($latitude, $longitude)");
		}
		Carp::croak(__PACKAGE__, ": Invalid latitude/longitude format ($latitude, $longitude)");
	}

	if(Scalar::Util::blessed($date) && $date->can('strftime')) {
		$date = $date->strftime('%F');
	} elsif($date =~ /^(\d{4})-/) {
		return if($1 < FIRST_YEAR);
	} else {
		Carp::carp("'$date' is not a valid date");
		return;
	}

	unless($date =~ /^\d{4}-\d{2}-\d{2}$/) {
		if(my $logger = $self->{'logger'}) {
			$logger->error('Invalid date format. Expected YYYY-MM-DD');
		}
		croak('Invalid date format. Expected YYYY-MM-DD');
	}

	my $uri = URI->new("https://$self->{host}/v1/archive");
	my %query_parameters = (
		'latitude' => $latitude,
		'longitude' => $longitude,
		'start_date' => $date,
		'end_date' => $date,
		'hourly' => 'temperature_2m,rain,snowfall,weathercode',
		'daily' => 'weathercode,temperature_2m_max,temperature_2m_min,rain_sum,snowfall_sum,precipitation_hours,windspeed_10m_max,windgusts_10m_max,sunrise,sunset',
		'timezone' => $tz,
			# https://stackoverflow.com/questions/16086962/how-to-get-a-time-zone-from-a-location-using-latitude-and-longitude-coordinates
		'windspeed_unit' => 'mph',
		'precipitation_unit' => 'inch'
	);

	$uri->query_form(%query_parameters);
	my $url = $uri->as_string();

	$url =~ s/%2C/,/g;

	# Create a cache key based on the location, date and time zone (might want to use a stronger hash function if needed)
	my $cache_key = "weather:$latitude:$longitude:$date:$tz";
	if(my $cached = $self->{cache}->get($cache_key)) {
		return $cached;
	}

	# Enforce rate-limiting: ensure at least min_interval seconds between requests
	my $now = time();
	my $elapsed = $now - $self->{last_request};
	if($elapsed < $self->{min_interval}) {
		Time::HiRes::sleep($self->{min_interval} - $elapsed);
	}

	my $res = $self->{ua}->get($url);

	# Update last_request timestamp
	$self->{last_request} = time();

	unless(defined($res) && ref($res) && $res->can('is_error')) {
		Carp::carp(ref($self) . ': UA->get did not return a valid HTTP response');
		return;
	}

	if($res->is_error()) {
		Carp::carp(ref($self), ": $url API returned error: ", $res->status_line());
		return;
	}
	# $res->content_type('text/plain');	# May be needed to decode correctly

	my $rc;
	eval { $rc = JSON::MaybeXS->new()->utf8()->decode($res->decoded_content()) };
	if($@) {
		Carp::carp("Failed to parse JSON response: $@");
		return;
	}

	if($rc && (ref($rc) eq 'HASH')) {
		if($rc->{'error'}) {
			# TODO: print error code
			return;
		}
		if(defined($rc->{'hourly'})) {
			# Cache the result before returning it
			$self->{'cache'}->set($cache_key, $rc);

			return Return::Set::set_return($rc, { type => 'hashref', min => 1 });	# No support for list context, yet
		}
	}

	return;
}

=head2 forecast

    my $meteo    = Weather::Meteo->new();
    my $forecast = $meteo->forecast({ latitude => 51.34, longitude => 1.42 });
    my @temps    = @{$forecast->{'hourly'}->{'temperature_2m'}};

    # Request 3 days of forecast
    $forecast = $meteo->forecast({ latitude => 51.34, longitude => 1.42, days => 3 });

    use Geo::Location::Point;
    my $ramsgate = Geo::Location::Point->new({ latitude => 51.34, longitude => 1.42 });
    $forecast = $meteo->forecast($ramsgate);
    $forecast = $meteo->forecast($ramsgate, 5);

Fetches weather forecast data from L<https://api.open-meteo.com>.
Returns up to 16 days of hourly and daily data.
The C<daily> key of the response includes C<sunrise> and C<sunset> ISO-8601 datetime strings.

Takes an optional C<days> argument (integer 1-16, default 7).
Takes an optional C<tz> argument for the time zone; defaults to C<Europe/London>.

On success returns a hashref containing at minimum the key C<hourly>.
Returns C<undef> if the API returns an error, if the JSON cannot be parsed,
or if the response contains no C<hourly> key.

=head3 API specification

=head4 Input

Three call forms are accepted.

    # Form 1 and 2 -- hashref or flat list
    {
        latitude  => { type => 'scalar' },
        longitude => { type => 'scalar' },
        days      => { type => 'scalar',               optional => 1 },
        tz        => { type => 'scalar',               optional => 1 },
        location  => { type => 'object', can => 'latitude', optional => 1 },
    }

    # Form 3 -- positional: ($location_obj) or ($location_obj, $days)
    # $location_obj must respond to latitude() and longitude()

=head4 Output

    { type => 'hashref', min => 1 }   # success -- contains 'hourly' key
    undef                              # bad input or API error

=head3 FORMAL SPECIFICATION

    ___ FORECAST ______________________________________________
    | self?      : Weather::Meteo                            |
    | latitude?  : REAL                                       |
    | longitude? : REAL                                       |
    | days?      : INTEGER [1..16]  (optional, default 7)    |
    | tz?        : STRING  (optional, default 'Europe/London')|
    |____________________________________________________________|
    | result!    : HASHREF | undef                            |
    |____________________________________________________________|
    |                                                          |
    | PRE (~latitude? v ~longitude?)                           |
    |   => croak /Usage: forecast\(latitude/                  |
    |                                                          |
    | PRE lat? or lon? not matching /^-?\d+(\.\d+)?$/         |
    |   => croak /Invalid latitude\/longitude format/          |
    |                                                          |
    | PRE days? defined ^ (days? < 1 v days? > 16)            |
    |   => carp /days must be between 1 and 16/               |
    |      days? := 7                                          |
    |                                                          |
    | POST cache hit for (lat, lon, days, tz)                 |
    |   => result! = cached_value                              |
    |                                                          |
    | POST HTTP error response                                 |
    |   => carp msg ^ result! = undef                          |
    |                                                          |
    | POST JSON parse failure                                  |
    |   => carp /Failed to parse JSON response/ ^ result! = undef |
    |                                                          |
    | POST response.error = true                               |
    |   => result! = undef                                     |
    |                                                          |
    | POST ~response.hourly                                    |
    |   => result! = undef                                     |
    |                                                          |
    | POST otherwise                                           |
    |   => result! = { hourly => HOURLY, daily => DAILY }     |
    |      cache.set(key, result!)                             |
    |____________________________________________________________|

=cut

sub forecast
{
	my $self = shift;
	my $params;

	if(scalar(@_) >= 1 && Scalar::Util::blessed($_[0]) && $_[0]->can('latitude')) {
		my $location = $_[0];
		$params->{latitude}  = $location->latitude();
		$params->{longitude} = $location->longitude();
		$params->{days}      = $_[1] if defined($_[1]);
		if($location->can('tz') && $ENV{'TIMEZONEDB_KEY'}) {
			$params->{tz} = $location->tz();
		}
	} else {
		$params = Params::Get::get_params(undef, \@_);
	}

	my $latitude  = $params->{latitude};
	my $longitude = $params->{longitude};
	my $location  = $params->{location};
	my $days      = $params->{days} // 7;
	my $tz        = $params->{tz} || 'Europe/London';

	if((!defined($latitude)) && defined($location) &&
	   Scalar::Util::blessed($location) && $location->can('latitude')) {
		$latitude  = $location->latitude();
		$longitude = $location->longitude();
	}
	if((!defined($latitude)) || (!defined($longitude))) {
		if(my $logger = $self->{'logger'}) {
			$logger->error('Usage: forecast(latitude => $latitude, longitude => $longitude)');
		}
		Carp::croak('Usage: forecast(latitude => $latitude, longitude => $longitude)');
		return;
	}

	# Handle numbers starting with a decimal point
	if($latitude =~ /^\./) {
		$latitude = "0$latitude";
	}
	if($latitude =~ /^\-\.(\d+)$/) {
		$latitude = "-0.$1";
	}
	if($longitude =~ /^\./) {
		$longitude = "0$longitude";
	}
	if($longitude =~ /^\-\.(\d+)$/) {
		$longitude = "-0.$1";
	}

	if(($latitude !~ /^-?\d+(\.\d+)?$/) || ($longitude !~ /^-?\d+(\.\d+)?$/)) {
		if(my $logger = $self->{'logger'}) {
			$logger->error(__PACKAGE__ . ": Invalid latitude/longitude format ($latitude, $longitude)");
		}
		Carp::croak(__PACKAGE__, ": Invalid latitude/longitude format ($latitude, $longitude)");
	}

	if(($days !~ /^\d+$/) || ($days < 1) || ($days > 16)) {
		Carp::carp('days must be between 1 and 16; defaulting to 7');
		$days = 7;
	}

	my $cache_key = "forecast:$latitude:$longitude:$days:$tz";
	if(my $cached = $self->{cache}->get($cache_key)) {
		return $cached;
	}

	my $elapsed = time() - $self->{last_request};
	if($elapsed < $self->{min_interval}) {
		Time::HiRes::sleep($self->{min_interval} - $elapsed);
	}

	my $uri = URI->new('https://' . FORECAST_HOST . '/v1/forecast');
	my %query_parameters = (
		'latitude'           => $latitude,
		'longitude'          => $longitude,
		'forecast_days'      => $days,
		'hourly'             => 'temperature_2m,rain,snowfall,weathercode',
		'daily'              => 'weathercode,temperature_2m_max,temperature_2m_min,rain_sum,snowfall_sum,precipitation_hours,windspeed_10m_max,windgusts_10m_max,sunrise,sunset',
		'timezone'           => $tz,
		'windspeed_unit'     => 'mph',
		'precipitation_unit' => 'inch',
	);

	$uri->query_form(%query_parameters);
	my $url = $uri->as_string();
	$url =~ s/%2C/,/g;

	my $res = $self->{ua}->get($url);
	$self->{last_request} = time();

	unless(defined($res) && ref($res) && $res->can('is_error')) {
		Carp::carp(ref($self) . ': UA->get did not return a valid HTTP response');
		return;
	}

	if($res->is_error()) {
		Carp::carp(ref($self), ": $url API returned error: ", $res->status_line());
		return;
	}

	my $rc;
	eval { $rc = JSON::MaybeXS->new()->utf8()->decode($res->decoded_content()) };
	if($@) {
		Carp::carp("Failed to parse JSON response: $@");
		return;
	}

	if($rc && (ref($rc) eq 'HASH')) {
		if($rc->{'error'}) {
			return;
		}
		if(defined($rc->{'hourly'})) {
			$self->{'cache'}->set($cache_key, $rc);
			return Return::Set::set_return($rc, { type => 'hashref', min => 1 });
		}
	}

	return;
}

=head2 sunrise_sunset

    my $meteo = Weather::Meteo->new();

    # Historical date
    my $times = $meteo->sunrise_sunset({ latitude => 51.34, longitude => 1.42, date => '2022-12-25' });
    print "Sunrise: $times->{sunrise}\n";
    print "Sunset:  $times->{sunset}\n";

    # Today (no date given -- uses forecast endpoint)
    $times = $meteo->sunrise_sunset({ latitude => 51.34, longitude => 1.42 });

    use Geo::Location::Point;
    my $ramsgate = Geo::Location::Point->new({ latitude => 51.34, longitude => 1.42 });
    $times = $meteo->sunrise_sunset($ramsgate, '2022-12-25');

Returns a hashref with C<sunrise> and C<sunset> ISO-8601 datetime strings
(e.g. C<2022-12-25T08:09>) for the given location and date.

If no date is supplied, today is used and the forecast endpoint is queried.
For historical dates (strictly before today) the archive endpoint is used.
For today and future dates the forecast endpoint (L<https://api.open-meteo.com>) is used.

Takes an optional C<tz> argument for the time zone; defaults to C<Europe/London>.

Returns C<undef> if the API returns an error or if the response does not contain
sunrise/sunset data.

=head3 API specification

=head4 Input

Three call forms are accepted.

    # Form 1 and 2 -- hashref or flat list
    {
        latitude  => { type => 'scalar' },
        longitude => { type => 'scalar' },
        date      => { type => 'scalar | object', optional => 1 },
        tz        => { type => 'scalar',           optional => 1 },
        location  => { type => 'object', can => 'latitude', optional => 1 },
    }

    # Form 3 -- positional: ($location_obj) or ($location_obj, $date)
    # $location_obj must respond to latitude() and longitude()

=head4 Output

    { type => 'hashref' }   # { sunrise => STRING, sunset => STRING }
    undef                    # bad input or API error

=head3 FORMAL SPECIFICATION

    ___ SUNRISE_SUNSET ________________________________________
    | self?      : Weather::Meteo                            |
    | latitude?  : REAL                                       |
    | longitude? : REAL                                       |
    | date?      : DATE_STRING  (optional, default today)     |
    | tz?        : STRING  (optional, default 'Europe/London')|
    |____________________________________________________________|
    | result!    : HASHREF | undef                            |
    |____________________________________________________________|
    |                                                          |
    | PRE (~latitude? v ~longitude?)                           |
    |   => croak /Usage: sunrise_sunset\(latitude/            |
    |                                                          |
    | PRE lat? or lon? not matching /^-?\d+(\.\d+)?$/         |
    |   => croak /Invalid latitude\/longitude format/          |
    |                                                          |
    | PRE date? defined ^ date? !~ /^\d{4}-\d{2}-\d{2}$/     |
    |   => carp /not a valid date/ ^ result! = undef           |
    |                                                          |
    | POST ~date? v date? >= today                             |
    |   => uses forecast endpoint (api.open-meteo.com)        |
    |                                                          |
    | POST date? < today                                       |
    |   => uses archive endpoint (archive-api.open-meteo.com) |
    |                                                          |
    | POST cache hit for (lat, lon, date, tz)                 |
    |   => result! = cached_value                              |
    |                                                          |
    | POST HTTP error or JSON failure or ~daily.sunrise        |
    |   => result! = undef                                     |
    |                                                          |
    | POST otherwise                                           |
    |   => result! = { sunrise => ISO8601, sunset => ISO8601 } |
    |      cache.set(key, result!)                             |
    |____________________________________________________________|

=cut

sub sunrise_sunset
{
	my $self = shift;
	my $params;

	if(scalar(@_) >= 1 && Scalar::Util::blessed($_[0]) && $_[0]->can('latitude')) {
		my $location = $_[0];
		$params->{latitude}  = $location->latitude();
		$params->{longitude} = $location->longitude();
		$params->{date}      = $_[1] if defined($_[1]);
		if($location->can('tz') && $ENV{'TIMEZONEDB_KEY'}) {
			$params->{tz} = $location->tz();
		}
	} else {
		$params = Params::Get::get_params(undef, \@_);
	}

	my $latitude  = $params->{latitude};
	my $longitude = $params->{longitude};
	my $location  = $params->{location};
	my $tz        = $params->{tz} || 'Europe/London';

	if((!defined($latitude)) && defined($location) &&
	   Scalar::Util::blessed($location) && $location->can('latitude')) {
		$latitude  = $location->latitude();
		$longitude = $location->longitude();
	}
	if((!defined($latitude)) || (!defined($longitude))) {
		if(my $logger = $self->{'logger'}) {
			$logger->error('Usage: sunrise_sunset(latitude => $latitude, longitude => $longitude)');
		}
		Carp::croak('Usage: sunrise_sunset(latitude => $latitude, longitude => $longitude)');
		return;
	}

	# Handle numbers starting with a decimal point
	if($latitude =~ /^\./) {
		$latitude = "0$latitude";
	}
	if($latitude =~ /^\-\.(\d+)$/) {
		$latitude = "-0.$1";
	}
	if($longitude =~ /^\./) {
		$longitude = "0$longitude";
	}
	if($longitude =~ /^\-\.(\d+)$/) {
		$longitude = "-0.$1";
	}

	if(($latitude !~ /^-?\d+(\.\d+)?$/) || ($longitude !~ /^-?\d+(\.\d+)?$/)) {
		if(my $logger = $self->{'logger'}) {
			$logger->error(__PACKAGE__ . ": Invalid latitude/longitude format ($latitude, $longitude)");
		}
		Carp::croak(__PACKAGE__, ": Invalid latitude/longitude format ($latitude, $longitude)");
	}

	my @t = localtime(time());
	my $today = sprintf('%04d-%02d-%02d', $t[5] + 1900, $t[4] + 1, $t[3]);
	my $date  = $params->{date};

	if(defined($date) && Scalar::Util::blessed($date) && $date->can('strftime')) {
		$date = $date->strftime('%F');
	}

	if(defined($date) && ($date !~ /^\d{4}-\d{2}-\d{2}$/)) {
		Carp::carp("'$date' is not a valid date");
		return;
	}

	my $use_forecast = !defined($date) || ($date ge $today);
	$date //= $today;

	my $cache_key = "sunrise_sunset:$latitude:$longitude:$date:$tz";
	if(my $cached = $self->{cache}->get($cache_key)) {
		return $cached;
	}

	my $elapsed = time() - $self->{last_request};
	if($elapsed < $self->{min_interval}) {
		Time::HiRes::sleep($self->{min_interval} - $elapsed);
	}

	my ($endpoint_host, $endpoint_path);
	if($use_forecast) {
		$endpoint_host = FORECAST_HOST;
		$endpoint_path = '/v1/forecast';
	} else {
		$endpoint_host = $self->{host};
		$endpoint_path = '/v1/archive';
	}

	my $uri = URI->new("https://$endpoint_host$endpoint_path");
	$uri->query_form(
		'latitude'   => $latitude,
		'longitude'  => $longitude,
		'start_date' => $date,
		'end_date'   => $date,
		'daily'      => 'sunrise,sunset',
		'timezone'   => $tz,
	);

	my $res = $self->{ua}->get($uri->as_string());
	$self->{last_request} = time();

	unless(defined($res) && ref($res) && $res->can('is_error')) {
		Carp::carp(ref($self) . ': UA->get did not return a valid HTTP response');
		return;
	}

	if($res->is_error()) {
		Carp::carp(ref($self), ': sunrise_sunset API returned error: ', $res->status_line());
		return;
	}

	my $rc;
	eval { $rc = JSON::MaybeXS->new()->utf8()->decode($res->decoded_content()) };
	if($@) {
		Carp::carp("Failed to parse JSON response: $@");
		return;
	}

	if($rc && (ref($rc) eq 'HASH') && !$rc->{'error'}) {
		my $daily = $rc->{'daily'};
		if(ref($daily) eq 'HASH') {
			my $sr = ref($daily->{'sunrise'}) eq 'ARRAY' ? $daily->{'sunrise'}[0] : undef;
			my $ss = ref($daily->{'sunset'})  eq 'ARRAY' ? $daily->{'sunset'}[0]  : undef;
			if(defined($sr) && defined($ss)) {
				my $result = { sunrise => $sr, sunset => $ss };
				$self->{'cache'}->set($cache_key, $result);
				return $result;
			}
		}
	}

	return;
}

=head2 ua

Accessor method to get and set UserAgent object used internally.
You can call I<env_proxy> for example, to get the proxy information from
environment variables:

    $meteo->ua()->env_proxy(1);

You can also set your own User-Agent object:

    use LWP::UserAgent::Throttled;

    my $ua = LWP::UserAgent::Throttled->new();
    $ua->throttle('open-meteo.com' => 1);
    $meteo->ua($ua);

=head3 API specification

=head4 Input

When called with no arguments acts as a getter; the input schema is empty.
When called with an argument the argument must be an object that responds to C<get>:

    { ua => { type => 'object', can => 'get' } }

=head4 Output

    { type => 'object', can => 'get' }

=head3 FORMAL SPECIFICATION

    ___ UA ____________________________________________________
    | self?   : Weather::Meteo                               |
    | ua?     : OBJECT [can 'get']   (optional)              |
    |____________________________________________________________|
    | result! : OBJECT [can 'get']                            |
    |____________________________________________________________|
    |                                                          |
    | PRE ua? defined ^ ~ua?.can('get')                       |
    |   => croak /must be an object that understands the get method/ |
    |                                                          |
    | POST ua? defined                                         |
    |   => self?.ua = ua? ^ result! = ua?                     |
    |                                                          |
    | POST ~ua?                                                |
    |   => result! = self?.ua  (no state change)              |
    |____________________________________________________________|

=cut

sub ua {
	my $self = shift;

	if (@_) {
		my $params = Params::Validate::Strict::validate_strict({
			args => Params::Get::get_params('ua', \@_),
			schema => {
				ua => {
					type => 'object',
					can => 'get'
				}
			}
		});
		# Reject undef explicitly before it silently corrupts $self->{ua}
		if(!defined($params->{ua})) {
			if(my $logger = $self->{'logger'}) {
				$logger->error('ua() requires a defined value')
			}
			Carp::croak('ua() requires a defined value')
		}
		$self->{ua} = $params->{ua};
	}
	return $self->{ua};
}

=head1 AUTHOR

Nigel Horne, C<< <njh@nigelhorne.com> >>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at L<https://open-meteo.com>.

=head1 BUGS

Please report any bugs or feature requests to C<bug-weather-meteo at rt.cpan.org>,
or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Weather-Meteo>.
I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

=head1 SEE ALSO

=over 4

=item * L<Test Dashboard|https://nigelhorne.github.io/Weather-Meteo/coverage/>

=item * Open Meteo API: L<https://open-meteo.com/en/docs#api_form>

=item * L<Object::Configure>

=back

=head1 SUPPORT

This module is provided as-is without any warranty.

You can find documentation for this module with the perldoc command.

    perldoc Weather::Meteo

You can also look for information at:

=over 4

=item * MetaCPAN

L<https://metacpan.org/release/Weather-Meteo>

=item * RT: CPAN's request tracker

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=Weather-Meteo>

=item * CPANTS

L<http://cpants.cpanauthors.org/dist/Weather-Meteo>

=item * CPAN Testers' Matrix

L<http://matrix.cpantesters.org/?dist=Weather-Meteo>

=item * CPAN Testers Dependencies

L<http://deps.cpantesters.org/?module=Weather-Meteo>

=back

=head1 LICENSE AND COPYRIGHT

Copyright 2023-2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it,
please let me know.

=cut

1;
