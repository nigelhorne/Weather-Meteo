# NAME

Weather::Meteo - Interface to [https://open-meteo.com](https://open-meteo.com) for historical weather data

# VERSION

Version 0.01

# SYNOPSIS

      use Weather::Meteo

      my $meteo = Weather::Meteo->new();
      my $weather = $meteo->weather({ latitude => '0.1', longitude => '0.2', date => '2022-12-25' });

# DESCRIPTION

Weather::Meteo provides an interface to open-meteo.com
for historical weather data

# METHODS

## new

    my $meteo = Weather::Meteo->new();
    my $ua = LWP::UserAgent->new();
    $ua->env_proxy(1);
    $meteo = Weather::Meteo->new(ua => $ua);

## weather

    # Print snowfall at 1AM on Christmas morning in Ramsgate
    $weather = $meteo->weather({ latitude => 51.34, longitude => 1.42, date => '2022-12-25' });
    my @snowfall = @{$weather->{'hourly'}->{'snowfall'}};
                cmp_ok(scalar(@{$weather->{'hourly'}->{'rain'}}), '==', 24, '24 sets of hourly rainfall data');

    print 'Number of cms of snow: ', $snowfall[1], "\n";

## ua

Accessor method to get and set UserAgent object used internally. You
can call _env\_proxy_ for example, to get the proxy information from
environment variables:

    $geo_coder->ua()->env_proxy(1);

You can also set your own User-Agent object:

    my $ua = LWP::UserAgent::Throttled->new();
    $ua->throttle('geocoder.ca' => 1);
    $geo_coder->ua($ua);

# AUTHOR

Nigel Horne, `<njh@bandsman.co.uk>`

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

Lots of thanks to the folks at [https://open-meteo.com](https://open-meteo.com).

# BUGS

# SEE ALSO

# LICENSE AND COPYRIGHT

Copyright 2023 Nigel Horne.

This program is released under the following licence: GPL2
