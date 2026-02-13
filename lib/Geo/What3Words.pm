# ABSTRACT: turn WGS84 coordinates into three word addresses and vice-versa using what3words.com HTTPS API

package Geo::What3Words;

use strict;
use warnings;
use Cpanel::JSON::XS;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Encode qw( decode_utf8 );
use HTTP::Tiny;
use Net::Ping;
use Net::Ping::External;
use Ref::Util qw( is_hashref is_coderef );
use URI;
use utf8;
# DO NOT TRY TO USE URI::XS IT JUST LEADS TO PROBLEMS

my $JSONXS = Cpanel::JSON::XS->new->allow_nonref(1);


=encoding utf8

=head1 SYNOPSIS

  my $w3w = Geo::What3Words->new( key => 'your-api-key' );

  $w3w->pos2words('51.484463,-0.195405');
  # returns 'prom.cape.pump'

  $w3w->pos2words('51.484463,-0.195405', 'ru');
  # returns 'питомец.шутить.намеренно'

  $w3w->words2pos('prom.cape.pump');
  # returns '51.484463,-0.195405' (latitude,longitude)

=head1 DESCRIPTION

what3words (L<https://what3words.com/>) divides the world into 57 trillion
squares of 3 metres x 3 metres. Each square has been given a 3 word address
comprised of 3 words from the dictionary.

This module calls API version 3 (L<https://docs.what3words.com/public-api/>)
to convert coordinates into 3 word addresses (forward) and 3
words into coordinates (reverse).

Versions 1 and 2 are deprecated and are no longer supported.

You need to sign up at L<https://what3words.com/login> and then register for
an API key at L<https://developer.what3words.com>

=head1 METHODS

=cut

=head2 new

Creates a new instance. The C<key> parameter is required.

  my $w3w = Geo::What3Words->new( key => 'your-api-key' );
  my $w3w = Geo::What3Words->new( key => 'your-api-key', language => 'ru' );

Options:

=over 4

=item key (required)

Your what3words API key.

=item language

Default language for 3 word addresses (e.g. C<'ru'>, C<'de'>). Can be
overridden per request.

=item api_endpoint

Override the API URL. Defaults to C<https://api.what3words.com/v3/>.

=item ua

Provide your own L<HTTP::Tiny> instance, e.g. for proxy configuration
or testing.

=item logging

For debugging you can either set logging to a true value or provide a
callback.

  my $w3w = Geo::What3Words->new( key => 'your-api-key', logging => 1 );
  # will print debugging output to STDOUT

  my $callback = sub { my $msg = shift; $my_log4perl_logger->info($msg) };
  my $w3w = Geo::What3Words->new( key => 'your-api-key', logging => $callback );
  # will log with log4perl

=back

=cut

sub new {
    my ($class, %params) = @_;

    my $self = {};
    $self->{api_endpoint} = $params{api_endpoint} || 'https://api.what3words.com/v3/';
    $self->{key}          = $params{key}          || die "API key not set";
    $self->{language}     = $params{language};
    $self->{logging}      = $params{logging};

    ## _ua is used for testing. But could also be used to
    ## set proxies or such
    $self->{ua} = $params{ua} || HTTP::Tiny->new;

    my $version = $Geo::What3Words::VERSION || '';
    $self->{ua}->agent("Perl Geo::What3Words $version");

    return bless($self, $class);
}

=head2 ping

Check if the remote server is available. This is helpful for debugging or
testing, but too slow to run for every conversion.

  $w3w->ping();

=cut

sub ping {
    my $self = shift;

    ## http://example.com/some/path => example.com
    ## also works with IP addresses
    my $host = URI->new($self->{api_endpoint})->host;

    $self->_log("pinging $host...");

    my $netping = Net::Ping->new('external');
    my $res     = $netping->ping($host);

    $self->_log($res ? 'available' : 'unavailable');

    return $res;
}

=head2 words2pos

Convenience wrapper around C<words_to_position>. Takes a 3 word address
string, returns a string C<'latitude,longitude'> or C<undef> on failure.

  $w3w->words2pos('prom.cape.pump');
  # returns '51.484463,-0.195405'

  $w3w->words2pos('does.not.exist');
  # returns undef

=cut

sub words2pos {
    my ($self, @params) = @_;

    my $res = $self->words_to_position(@params);
    if ($res && is_hashref($res) && exists($res->{coordinates})) {
        return $res->{coordinates}->{lat} . ',' . $res->{coordinates}->{lng};
    }
    return;
}


=head2 pos2words

Convenience wrapper around C<position_to_words>. Takes a string
C<'latitude,longitude'> and an optional language code. Returns a 3 word
address string or C<undef> on failure.

  $w3w->pos2words('51.484463,-0.195405');
  # returns 'prom.cape.pump'

  $w3w->pos2words('51.484463,-0.195405', 'ru');
  # returns 'питомец.шутить.намеренно'

  $w3w->pos2words('invalid,coords');
  # returns undef

=cut

sub pos2words {
    my ($self, @params) = @_;
    my $res = $self->position_to_words(@params);
    if ($res && is_hashref($res) && exists($res->{words})) {
        return $res->{words};
    }
    return;
}

=head2 valid_words_format

Returns 1 if the string looks like three dot-separated words, 0 otherwise.
Supports Unicode (e.g. Cyrillic, Turkish). Does not call the remote API.

  $w3w->valid_words_format('prom.cape.pump');
  # returns 1

  $w3w->valid_words_format('диета.новшество.компаньон');
  # returns 1

  $w3w->valid_words_format('Not.Valid.Format');
  # returns 0 (uppercase letters)

=cut

sub valid_words_format {
    my $self  = shift;
    my $words = shift;

    ## Translating the PHP regular expression w3w uses in their
    ## documentation
    ## http://perldoc.perl.org/perlunicode.html#Unicode-Character-Properties
    ## http://php.net/manual/en/reference.pcre.pattern.differences.php
    return 0 unless $words;
    return 1 if ($words =~ m/^(\p{Lower}+)\.(\p{Lower}+)\.(\p{Lower}+)$/);
    return 0;
}

=head2 words_to_position

Takes a 3 word address string and returns a hashref with coordinates,
country, language, map link, nearest place, and bounding square.
Returns C<undef> on failure.

  $w3w->words_to_position('prom.cape.pump');
  # {
  #        'coordinates' => {
  #                           'lat' => '51.484463',
  #                           'lng' => '-0.195405'
  #                         },
  #        'country' => 'GB',
  #        'language' => 'en',
  #        'map' => 'https://w3w.co/prom.cape.pump',
  #        'nearestPlace' => 'Kensington, London',
  #        'square' => {
  #                      'northeast' => {
  #                                       'lat' => '51.484476',
  #                                       'lng' => '-0.195383'
  #                                     },
  #                      'southwest' => {
  #                                       'lat' => '51.484449',
  #                                       'lng' => '-0.195426'
  #                                     }
  #                    },
  #        'words' => 'prom.cape.pump'
  #      };

=cut

sub words_to_position {
    my $self  = shift;
    my $words = shift;

    return $self->_query_remote_api('convert-to-coordinates', {words => $words});

}

=head2 position_to_words

Takes a string C<'latitude,longitude'> and an optional language code.
Returns a hashref with coordinates, country, language, map link, nearest
place, and bounding square. Returns C<undef> on failure.

  $w3w->position_to_words('51.484463,-0.195405');
  $w3w->position_to_words('51.484463,-0.195405', 'ru');

  # {
  #        'coordinates' => {
  #                           'lat' => '51.484463',
  #                           'lng' => '-0.195405'
  #                         },
  #        'country' => 'GB',
  #        'language' => 'en',
  #        'map' => 'https://w3w.co/prom.cape.pump',
  #        'nearestPlace' => 'Kensington, London',
  #        'square' => {
  #                      'northeast' => {
  #                                       'lat' => '51.484476',
  #                                       'lng' => '-0.195383'
  #                                     },
  #                      'southwest' => {
  #                                       'lat' => '51.484449',
  #                                       'lng' => '-0.195426'
  #                                     }
  #                    },
  #        'words' => 'prom.cape.pump'
  #      };

=cut

sub position_to_words {
    my $self     = shift;
    my $position = shift;
    my $language = shift || $self->{language};

    # https://developer.what3words.com/public-api/docs#convert-to-3wa
    return $self->_query_remote_api(
        'convert-to-3wa',
        {   coordinates => $position,
            language    => $language
        }
    );
}

=head2 get_languages

Returns a hashref containing a list of supported language codes and names.

  $w3w->get_languages();
  # {
  #     'languages' => [
  #                      {
  #                        'name' => 'German',
  #                        'nativeName' => 'Deutsch',
  #                        'code' => 'de'
  #                      },
  #                      {
  #                        'name' => 'English',
  #                        'nativeName' => 'English',
  #                        'code' => 'en'
  #                      },
  #                      {
  #                        'name' => "Spanish",
  #                        'nativeName' => "Español",
  #                        'code' => 'es'
  #                      },
  # ...

=cut

sub get_languages {
    my $self     = shift;
    my $position = shift;
    return $self->_query_remote_api('available-languages');
}

=head2 oneword_available

Deprecated. Calling this method will emit a warning and return C<undef>.

=cut

sub oneword_available {
    warn 'deprecated method: oneword_available';
    return;
}

sub _query_remote_api {
    my $self        = shift;
    my $method_name = shift;
    my $rh_params   = shift || {};

    my $rh_fields = {
        #a      => 1,
        key    => $self->{key},
        format => 'json',
        %$rh_params
    };

    foreach my $key (keys %$rh_fields) {
        delete $rh_fields->{$key} if (!defined($rh_fields->{$key}));
    }

    my $uri = URI->new($self->{api_endpoint} . $method_name);
    $uri->query_form($rh_fields);
    my $url = $uri->as_string;

    $self->_log("GET $url");
    my $response = $self->{ua}->get($url);

    if (!$response->{success}) {
        warn "got failed response from $url: " . $response->{status};
        $self->_log("got failed response from $url: " . $response->{status});
        return;
    }

    my $json = $response->{content};
    $json = decode_utf8($json);
    $self->_log($json);

    return $JSONXS->decode($json);
}

sub _log {
    my $self    = shift;
    my $message = shift;
    return unless $self->{logging};

    if (is_coderef($self->{logging})) {
        my $lc = $self->{logging};
        &$lc("Geo::What3Words -- " . $message);
    } else {
        print "Geo::What3Words -- " . $message . "\n";
    }
    return;
}

=head1 ERROR HANDLING

On HTTP errors or invalid input the convenience methods (C<pos2words>,
C<words2pos>) return C<undef>. The verbose methods (C<position_to_words>,
C<words_to_position>, C<get_languages>) also return C<undef> on failure.

In all cases a warning is emitted via C<warn> with the HTTP status code.
You can catch these with C<$SIG{__WARN__}> or L<Test::Warn> in tests.

=head1 TESTING

The test suite uses pre-recorded API responses. If you suspect something
changed in the API you can force the test suite to use live requests with
your API key:

    W3W_API_KEY=<your key> prove -l t/base.t

=head1 SEE ALSO

L<https://what3words.com/> - what3words website

L<https://developer.what3words.com> - API documentation and key registration

L<https://developer.what3words.com/public-api/docs> - API v3 reference

=cut

1;
