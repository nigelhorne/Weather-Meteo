# NAME

Weather::Meteo - Interface to [https://open-meteo.com](https://open-meteo.com) for historical and forecast weather data

# VERSION

Version 0.14

# SYNOPSIS

The `Weather::Meteo` module provides an interface to the Open-Meteo API for retrieving
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

- Caching

    Identical requests are cached (using [CHI](https://metacpan.org/pod/CHI) or a user-supplied caching object),
    reducing the number of HTTP requests to the API and speeding up repeated queries.

    This module leverages [CHI](https://metacpan.org/pod/CHI) for caching geocoding responses.
    When a geocode request is made,
    a cache key is constructed from the request.
    If a cached response exists,
    it is returned immediately,
    avoiding unnecessary API calls.

- Rate-Limiting

    A minimum interval between successive API calls can be enforced to ensure that the API is not overwhelmed and to comply with any request throttling requirements.

    Rate-limiting is implemented using [Time::HiRes](https://metacpan.org/pod/Time%3A%3AHiRes).
    A minimum interval between API
    calls can be specified via the `min_interval` parameter in the constructor.
    Before making an API call,
    the module checks how much time has elapsed since the
    last request and,
    if necessary,
    sleeps for the remaining time.

# METHODS

## new

    my $meteo = Weather::Meteo->new();
    my $ua = LWP::UserAgent->new();
    $ua->env_proxy(1);
    $meteo = Weather::Meteo->new(ua => $ua);

    my $weather = $meteo->weather({ latitude => 51.34, longitude => 1.42, date => '2022-12-25' });
    my @snowfall = @{$weather->{'hourly'}->{'snowfall'}};

    print 'Number of cms of snow: ', $snowfall[1], "\n";

Creates a new instance. Acceptable options include:

- `cache`

    A caching object.
    If not provided,
    an in-memory cache is created with a default expiration of one hour.

- `host`

    The API host endpoint.
    Defaults to [https://archive-api.open-meteo.com](https://archive-api.open-meteo.com).

- `min_interval`

    Minimum number of seconds to wait between API requests.
    Defaults to `0` (no delay).
    Use this option to enforce rate-limiting.

- `ua`

    An object to use for HTTP requests.
    If not provided, a default user agent is created.

The class can be configured at runtime using environments and configuration files,
for example,
setting `$ENV{'WEATHER__METEO__carp_on_warn'}` causes warnings to use [Carp](https://metacpan.org/pod/Carp).
For more information about runtime configuration,
see [Object::Configure](https://metacpan.org/pod/Object%3A%3AConfigure).

### API specification

#### Input

All parameters are optional.
They may be supplied as a hashref or a flat key/value list.
When `$class` is an existing `Weather::Meteo` object the call clones it,
merging any supplied parameters.

    {
        ua           => { type => 'object', can => 'get', optional => 1 },
        cache        => { type => 'object',               optional => 1 },
        host         => { type => 'scalar',               optional => 1 },
        min_interval => { type => 'scalar',               optional => 1 },
    }

#### Output

    { type => 'object', isa => 'Weather::Meteo' }

## weather

    use Geo::Location::Point;

    my $ramsgate = Geo::Location::Point->new({ latitude => 51.34, longitude => 1.42 });
    # Print snowfall at 1AM on Christmas morning in Ramsgate
    $weather = $meteo->weather($ramsgate, '2022-12-25');
    @snowfall = @{$weather->{'hourly'}->{'snowfall'}};

    print 'Number of cms of snow: ', $snowfall[1], "\n";

    use DateTime;
    my $dt = DateTime->new(year => 2024, month => 2, day => 1);
    $weather = $meteo->weather({ location => $ramsgate, date => $dt });

The date argument can be an ISO-8601 formatted string (`YYYY-MM-DD`),
or any object that supports `strftime`.

Takes an optional `tz` argument containing the time zone.
If not given, the module tries to derive it from the location object;
set `TIMEZONEDB_KEY` to your API key from [https://timezonedb.com](https://timezonedb.com) to enable that.
If all else fails, the module falls back to `Europe/London`.

Dates before 1940 return `undef` silently.
Invalid date strings cause a `carp` and return `undef`.
Missing required arguments or non-numeric coordinates cause a `croak`.

On success returns a hashref with at minimum an `hourly` key.
The `daily` key includes `sunrise` and `sunset` as ISO-8601 datetime strings
(e.g. `2022-12-25T08:09`), as well as temperature, precipitation, and wind fields.
Returns `undef` if the API returns an error, if the JSON cannot be
parsed, or if the response contains no `hourly` key.

### API specification

#### Input

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

#### Output

    { type => 'hashref', min => 1 }   # success -- contains 'hourly' key
    undef                              # pre-1940 date, bad input, or API error

## forecast

    my $meteo    = Weather::Meteo->new();
    my $forecast = $meteo->forecast({ latitude => 51.34, longitude => 1.42 });
    my @temps    = @{$forecast->{'hourly'}->{'temperature_2m'}};

    # Request 3 days of forecast
    $forecast = $meteo->forecast({ latitude => 51.34, longitude => 1.42, days => 3 });

    use Geo::Location::Point;
    my $ramsgate = Geo::Location::Point->new({ latitude => 51.34, longitude => 1.42 });
    $forecast = $meteo->forecast($ramsgate);
    $forecast = $meteo->forecast($ramsgate, 5);

Fetches weather forecast data from [https://api.open-meteo.com](https://api.open-meteo.com).
Returns up to 16 days of hourly and daily data.
The `daily` key of the response includes `sunrise` and `sunset` ISO-8601 datetime strings.

Takes an optional `days` argument (integer 1-16, default 7).
Takes an optional `tz` argument for the time zone; defaults to `Europe/London`.

On success returns a hashref containing at minimum the key `hourly`.
Returns `undef` if the API returns an error, if the JSON cannot be parsed,
or if the response contains no `hourly` key.

### API specification

#### Input

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

#### Output

    { type => 'hashref', min => 1 }   # success -- contains 'hourly' key
    undef                              # bad input or API error

## sunrise\_sunset

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

Returns a hashref with `sunrise` and `sunset` ISO-8601 datetime strings
(e.g. `2022-12-25T08:09`) for the given location and date.

If no date is supplied, today is used and the forecast endpoint is queried.
For historical dates (strictly before today) the archive endpoint is used.
For today and future dates the forecast endpoint ([https://api.open-meteo.com](https://api.open-meteo.com)) is used.

Takes an optional `tz` argument for the time zone; defaults to `Europe/London`.

Returns `undef` if the API returns an error or if the response does not contain
sunrise/sunset data.

### API specification

#### Input

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

#### Output

    { type => 'hashref' }   # { sunrise => STRING, sunset => STRING }
    undef                    # bad input or API error

## ua

Accessor method to get and set UserAgent object used internally.
You can call _env\_proxy_ for example, to get the proxy information from
environment variables:

    $meteo->ua()->env_proxy(1);

You can also set your own User-Agent object:

    use LWP::UserAgent::Throttled;

    my $ua = LWP::UserAgent::Throttled->new();
    $ua->throttle('open-meteo.com' => 1);
    $meteo->ua($ua);

### API specification

#### Input

When called with no arguments acts as a getter; the input schema is empty.
When called with an argument the argument must be an object that responds to `get`:

    { ua => { type => 'object', can => 'get' } }

#### Output

    { type => 'object', can => 'get' }

# AUTHOR

Nigel Horne, `<njh@nigelhorne.com>`

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at [https://open-meteo.com](https://open-meteo.com).

# BUGS

Please report any bugs or feature requests to `bug-weather-meteo at rt.cpan.org`,
or through the web interface at
[http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Weather-Meteo](http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Weather-Meteo).
I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.

# SEE ALSO

- [Test Dashboard](https://nigelhorne.github.io/Weather-Meteo/coverage/)
- Open Meteo API: [https://open-meteo.com/en/docs#api\_form](https://open-meteo.com/en/docs#api_form)
- [Object::Configure](https://metacpan.org/pod/Object%3A%3AConfigure)

# SUPPORT

This module is provided as-is without any warranty.

You can find documentation for this module with the perldoc command.

    perldoc Weather::Meteo

You can also look for information at:

- MetaCPAN

    [https://metacpan.org/release/Weather-Meteo](https://metacpan.org/release/Weather-Meteo)

- RT: CPAN's request tracker

    [https://rt.cpan.org/NoAuth/Bugs.html?Dist=Weather-Meteo](https://rt.cpan.org/NoAuth/Bugs.html?Dist=Weather-Meteo)

- CPANTS

    [http://cpants.cpanauthors.org/dist/Weather-Meteo](http://cpants.cpanauthors.org/dist/Weather-Meteo)

- CPAN Testers' Matrix

    [http://matrix.cpantesters.org/?dist=Weather-Meteo](http://matrix.cpantesters.org/?dist=Weather-Meteo)

- CPAN Testers Dependencies

    [http://deps.cpantesters.org/?module=Weather-Meteo](http://deps.cpantesters.org/?module=Weather-Meteo)

# FORMAL SPECIFICATION

## new

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

## weather

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

## forecast

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

## sunrise\_sunset

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

## ua

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

# LICENSE AND COPYRIGHT

Copyright 2023-2026 Nigel Horne.

Usage is subject to the GPL2 licence terms.
If you use it,
please let me know.
