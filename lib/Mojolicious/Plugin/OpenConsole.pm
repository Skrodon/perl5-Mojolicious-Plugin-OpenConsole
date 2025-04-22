package Mojolicious::Plugin::OpenConsole;
use Mojo::Base 'Mojolicious::Plugin';

use Log::Report  'mojo-plugin-oc';

use DateTime        ();
use Mojo::UserAgent ();
use Mojo::URL       ();
use Net::Domain     qw(hostfqdn);
use HTTP::Status    qw(HTTP_OK);
use Scalar::Util    qw(blessed);

use Data::Dumper;    # For debugging

# See https://github.com/Skrodon/open-console-connect/wiki/API-versioning
use constant MY_API_VERSION => '1.0.0';

sub now();
sub random_token();
sub timestamp2dt($);
sub url($);
my $logo_svg;

=chapter NAME

Mojolicious::Plugin::OpenConsole - provide "login via OpenConsole"

=chapter SYNOPSIS

  use Mojolicious::Lite;
  plugin OpenConsole => %options, model => $db;
  plugin OpenConsole => { %options, model => $db };

  # or

  use Mojolicious;
  sub startup(...) {
    ...
    # For available %options see register()
    $self->plugin('OpenConsole', %options, model => $db);
	$self->OpenConsole->appLogin(...);
  }

  # Then, in your templates, put:
  % my %button = $c->OpenConsole->buttonSetup;
  %# insert the template of your choice here

  # You also need to add a route to receive the user, and collect
  # the related grant with details.

=chapter DESCRIPTION

The Open Console infrastructure simplifies the way you can give access
to your services.  Especially when you need to know more about the user
than a name and email-address, you get large advantages over the OpenID
login.  See F<https://open-console.eu>.

This module implements everything you need to use Open Console
for logging-in to your website, when your website is based on
the Mojolicious framework, F<https://metacpan.org/pod/Mojolicious>

See the demo implementation in
F<https://github.com/Skrodon/open-console-connect-owner/lib/OwnerConsole/Controller/Client.pm>
and
F<https://github.com/Skrodon/open-console-connect-owner/lib/OwnerConsole/Model/Client.pm>
for a full example how to connect this plugin to your logic.

=chapter METHODS

=section Constructors

=c_method new %options
This will use the M<Mojo::Base::new()> to instantiate the object.
New is for internal use only.

=method register $app, %options|\%options
This method is called automatically when the plugin gets loaded by the
Mojolicious framework.  Do not call this yourself.  However: You do need
a list of parameters.  They can be passed as LIST of PAIRS or as HASH.

The C<model> is a runtime object, but B<all other> values can also be
set via a HASH under C<OpenConsole> in your Mojolicious configuration file.
In (the rare case) that you support multiple separate services in one
application, you will need to call M<appLogin()> with the right parameters
multiple times yourself.

=requires model OBJECT
This model (MVC term) is the connection to a database which
stores and retreived the objects we need.  See the L</DETAILS>
chapter about this interface.

=option  connect URL
=default connect 'https://connect.open-console.eu'
Which server will handle the connect.  The default is the global Open
Console production server.  But this could also point to a development
or test instance of the software.

=option  secret STRING
=default secret C<undef>
Used as a password, to log the server instance in on Open Console.  The
secret is set in the configuration of the Service in Open Console.

=option  instance NAME
=default instance $fqdn
Give this instance a symbolic name, so the Open Console infrastructure
can refer to it when it feels the need, for instance in case of errors.
This defaults to the autodetected fully qualified domain-name of your
server.

=option  service TOKEN
=default service C<undef>
Specifies the token which Open Console has assigned to this service, when
you registered it.

=option  website URL
=default website 'https://open-console.eu'

=option  user_agent M<Mojo::UserAgent>-object
=default user_agent default created
We need a user agent to talk to OpenConsole ourselves.  When you need something
special, then you create this object yourself.  Often, the default will do.
=cut

sub register($$)
{	my ($self, $app) = (shift, shift);
	my $args     = @_==1 ? shift : { @_ };
	my $applconf = $app->config->{OpenConsole} || {};
	my %conf     = (%$applconf, %$args);

	$self->{MPO_model}   = $conf{model} or panic "No model (db) given";
	$self->{MPO_host}    = url($conf{connect}  || 'https://connect.open-console.eu'); 
	$self->{MPO_web}     = url($conf{website}  || 'https://open-console.eu');
	$self->{MPO_inst}    = $conf{instance}     || hostfqdn;
	$self->{MPO_secret}  = $conf{secret}       or panic;
	$self->{MPO_service} = $conf{service}      or panic;
	$self->{MPO_ua}      = $args->{user_agent} || Mojo::UserAgent->new;
	$self->{MPO_appses}  = {};  # session info cache, appsession and service as mixed keys

	$app->helper(OpenConsole => sub { $self });
	$self;
}

#----------------
=section Attributes

=method model
=method host
=method secret
=method instance
=method service
=method website
=method userAgent
=cut

sub model()    { $_[0]->{MPO_model} }
sub host()     { $_[0]->{MPO_host} }
sub secret()   { $_[0]->{MPO_secret} }
sub service()  { $_[0]->{MPO_service} }
sub instance() { $_[0]->{MPO_inst} }
sub website()  { $_[0]->{MPO_web} }
sub userAgent(){ $_[0]->{MPO_ua} }

#----------------
=section Actions
The methods which are called by your logic.  See the demo implementation.

=method appLogin %options
Used by M<appSession()> to create a login on Open Console, even when there
already exists one.  Use M<Log::Report::try()> if you want to catch errors.

You may pass a C<service> and C<secret> value, to overrule the global
setting.
=cut

sub appLogin(%)
{	my ($self, %args) = @_;
	my $service = $args{service} || $self->service or panic;
	my $secret  = $args{secret}  || $self->secret  or panic;

	# Only the application login uses the long-lived service identifier:
	# all other messages use the temporary session id.
	my %headers = (
		Authorization => "Bearer $service",
	);

	# The login is the only path this is hard-coded: the location of all
	# other endpoints is listed in the appsession reply.
	my $endpoint = $self->host->path('/application/login');

	my $tx      = $self->userAgent->post($endpoint, \%headers, json => {
    	instance    => $self->instance,
    	secret      => $secret,
		api_version => MY_API_VERSION,
	});

	if(my $err = $tx->error)
	{	error __x"Open Console Connect cannot be reached: {err}", err => $err->{message};
	}

	my $resp = $tx->res;

	$resp->code eq HTTP_OK
		or error __x"Application '{name}' cannot login to '{oc}': {msg}",
			name => $self->instance, oc => "$endpoint", msg => $resp->message, _errno => $resp->code;

	my $login   = $resp->json;
warn "***APP LOGIN ", Dumper $login;

	my $session  = $login->{session};   # session control info

	my $bearer   = $session->{bearer};
	$self->model->OpenConsoleSave(appsession => $login,
		id         => $bearer,
		deprecates => $session->{deprecates}, # when to stop using
		expires    => $session->{expires},    # when the server forgets
		service    => $login->{service}{id},  # for search
    );

	$self->{MPO_appses}{$bearer} = $self->{MPO_appses}{$service} = +{
		login   => $login,
		params  => { service => $service, secret => $secret },
	};
}

=method buttonSetup [$session]
Returns a HASH of parameters which you need to produce the login button.
=cut

sub buttonSetup(;$)
{	my ($self, $service) = @_;
	my $session = $self->appSession($service ||= $self->service) or return;
warn "**SERVICE=$service, ", Dumper $session;

	 +{	session  => $session->{session}{bearer},
		logo_svg => $logo_svg,
	  };
}

=method buttonClick $collector, %options
Call this method when the user has hit the "login via OpenConsole"
button.  The user will then get redirected to the Authencation server
via an OAuth2 protocol.

=option  state TOKEN
=default state <strong random roken>
The OAuth2 'state' has been reassigned to avoid replay attacks.
Read the L</DETAILS> chapter, below.

=option  scope TOKEN
=default scope C<undef>
The scope is not used for OpenConsole at the moment, but you may feel
a need for it.
=cut

sub buttonClick($%)
{	my ($self, $coll, %args) = @_;

	my $session_id = $coll->req->param('session')
		or return $self->reportError($coll, 'E10');

	my $session = $self->appSession($session_id)
		or return $self->reportError($coll, 'E11', $session_id);

	my $state = $args{state} // random_token;
	$self->rememberState($coll, $state, $session);

	# We have to, somehow, remember the state we assigned to
	my %form = (
		response_type => 'code',
		state         => $state,
		client_id     => $session_id,
	);

	if(my $scope = $args{scope})
	{	$form{scope} = $scope;
	}

	$self->host->clone->path('/user/login')->query(%form);
}

=method acceptUser $collector
Only used when the user started the login process via a "login via
OpenConsole" button on the application website.  It uses the OAuth2
process.

The user got authenticated by Open Console, and now arrives back at
your service.  Some checks need to be performed.  When successfull, the
user token, the state, and the related AppSession object will be returned.
=cut

sub acceptUser($%)
{	my ($self, $coll, %args) = @_;
	my $req = $coll->req;

	my $session_id = $req->param('client_id')
		or return $self->reportError($coll, 'E01');

 	my $session    = $self->appSession($session_id)
		or return $self->reportError($coll, 'E02', $session_id);

	my $state      = $req->param('state')
		or return $self->reportError($coll, 'E03', $session);

	$self->checkState($coll, $state, $session)
		or return $self->reportError($coll, 'E04', $session);

	my $user  = $req->param('code')
		or return $self->reportError($coll, 'E05', $session);

	($user, $state, $session);
}

=method userGrant $app, $user, %options
Collect the user's details via the back-channel.

=option  on_error CODE
=default on_error <produce warning>
=cut

sub userGrant($$%)
{	my ($self, $app, $user, %args) = @_;

	# All app-session (you may be in session transition or use multiple
	# application instances) can ask the details of the grant.
	$app = $self->appSession($app) if ref $app ne 'HASH';
	$app or panic;

	# The endpoint is in the app-session login.
	my $where  = $self->endpoint($app, 'user_grant');

	# The session-id is our security token.
	my $auth   = $app->{id};

	# Call OpenConsole to give the details about the $user.
	my $resp   = $self->userAgent->get(
		"$where?code=$user",
		{ Authorization => "Bearer $auth" },
	);

	my $rc = $resp->code;
	if($rc != HTTP_OK)
	{	my $on_error = $args{on_error} ||
			sub { warning "Failed to get grant for $user: $rc", _errno => $rc };
		$on_error->($self, $app, $user, $resp);
		return undef;
	}

	$resp->result->json;
}

#--------------
=section Supporting methods

=method appSession $bearer, %options
Start or continue an application session.  Returned is the HASH as
described in F<https://github.com/Skrodon/open-console-connect/wiki/Application-Session>

When the connection data has expired, it will be collected again.  That
may fail, so you may receive C<undef> as answer.

=option  fresh BOOLEAN
=default fresh <false>
A login/grant process may use an expired session, but when a new button
is generated, the session must be fresh.
=cut

sub _oldSession($)
{	my ($self, $id) = @_;
	my $login = $self->model->OpenConsoleLoad(appsession => $id);
	unless($login)
	{	warning __x"Session {id} cannot be found", id => $id;
		return undef;
	}

	  +{ login => $login };
}

sub appSession($%)
{	my ($self, $id, %args) = @_;
	my $fresh = delete $args{fresh};

	my $sessions = $self->{MPO_appses};
	my $conn     = $sessions->{$id} ||= $self->_oldSession($id);
use Data::Dumper;
warn "SESSION($id) ", Dumper $conn;

	unless($fresh)
	{	# Avoid loading the same appsession from the db by accident
		my $login   = $conn->{login};
		my $expires = timestamp2dt($login->{session}{expires});
warn "COMPARE $expires, ".now ."#";
		return $login if DateTime->compare($expires, now) >= 0;
	}

	# Refresh session
	$conn = $self->appLogin(%{$conn->{params}}) or return undef;
warn "NEWSESS ", Dumper $conn;
	$conn->{appsess};
}

=method appSessionForService $service, %options
Returns the latest appsession definition for the given service.  If there is none,
then apparently the M<appLogin()> has not been run, which is an error.
=cut

sub appSessionForService($%)
{	my ($self, $service_id, %args) = @_;

	# Don't trust the cache
	my $session = $self->model->OpenConsoleServiceSession($service_id)
		or error __x"Service $service_id has never logged-in";

	$self->{MPO_appses}{$session->{id}} = $session;
	$session;
}

=method rememberState $coll, $state, $session
When the user comes back to the service, after being authenticated, we
need to check the $state parameter to avoid certain kinds of attacks.  The
user must not be able to set or modify the expected state.
=cut

sub rememberState($$$)
{	my ($self, $coll, $state, $session) = @_;

	# In Mojo, this is simple: we do not need to use a database (provided
	# via the model), because the session cookie fulfills the requirements:
	# the payload of the cookie is encrypted so the user cannot temper with
	# it.

	$coll->session(connect_state => $state);
	$self;
}

=method checkState $coll, $state, $session
Check whether the received $state is the same as remembered (via M<rememberState()>)
Returns a boolean.
=cut

sub checkState($$$)
{	my ($self, $coll, $state, $session) = @_;
	my $expect = $coll->session('connect_state') // '';
	$expect eq $state;
}

=method reportError $coll, $code|$message, [$session|$session_id]
Redirect the user to the Owner Console website, to display the error.

When this error is not a standard error (when you implement your own
client, but the message you want to bring is not used in this example
implementation), then you may pass a (translated) $message to be
displayed.
=cut

sub reportError($$;$)
{	my ($self, $coll, $code, $session) = @_;
	my $url  = $self->website->clone->path('comply/error');
	my %form = $code =~ m/^[A-Z][0-9][0-9]$/ ? (error => $code) : (error => 'E00', message => $code);

	$form{session} = ref $session ? $session->id : $session
		if $session;
	
	$coll->redirect_to($url->query(%form));
	();
}

=method endpoint $session, $which
Returns the URL for a named endpoint, as received in the login answere.
=cut

sub endpoint($$)
{	my ($self, $session, $name) = @_;
	$session = $self->appSession($session) if ref $session ne 'HASH';
	$session ? $session->{endpoints}{$name} : undef;
}

###
### also in OpenConsole::Util, but that module is not distributed via CPAN
###

use DateTime::Format::ISO8601 ();
use DateTime::Format::Duration::ISO8601 ();
use Session::Token ();

my $token_generator = Session::Token->new;

sub timestamp2dt($) { defined $_[0] ? DateTime::Format::ISO8601->parse_datetime($_[0]) : undef }
sub now()           { DateTime->now(time_zone => 'Z') }
sub random_token()  { $token_generator->get }
sub url($) { my $u = shift // return undef; blessed $u && $u->isa('Mojo::URL') ? $u : Mojo::URL->new($u) }

#-----------------
=chapter DETAILS

=section Configuration

You can put the settings for this module in your Mojolicious application
configuration under the name C<OpenConsole>.  That HASH can have the
same parameters as M<register()>, except the model object (the database
connection).

Besides setting-up the database, you will need to pick a template for
the button.  There are various options to make that work.

=section The database, required

You cannot implement this interface without a database.  There are
many kinds of databases, but you make your life easier when using
a object store, like MongoDB or CouchDB.

Your database must store some JSON objects, but (probably) will never
query the content of that object.  Actually: it is a complex Perl
data-structure restricted to JSON features.  You may also store the
JSON in serialized (stringified) state.  The data which is important
is also passed in a separate HASH within the OBJECT.  Hopefully, the
following examples clarify this.

=subsection Model

Your database model MUST implement the methods described below.  Your
model object is passed as argument to the plugin instantiation, like this:

  use Mojolicious::Lite;
  plugin 'OpenConsole', model => $model;

  use Mojolicious;
  sub startup(...) {
	 $self->plugin('OpenConsole', model => $model, %config);

You may take a look how this model got implemented with MongoDB in the
demo part of the Open Console website at
F<https://github.com/Skrodon/open-console-owner/blob/main/lib/OwnerConsole/Model/Client.pm>

=subsection model objects

At the moment, there are two kinds of objects:

=over 4
=item the appsession type, which the application received when it connected to the Open Console infrastructure; and
=item the grant type, which contains knowledge of a use who logged-in.
=back

Types of both objects are pretty short lived, and probably not in
large numbers.  Both types can be stored in the same database table,
as the ids (identitiers) use separate namespaces.  But you may put
them in separate tables, if you feel the need.

=subsection model method: openConsoleLoad()

The `OpenConsoleLoad($type, $oid)` method is called when an object is needed
from the database.  You method should look like:

   package MyProject::Model::MyDB;
   use Mojo::Base -base;

   sub OpenConsoleLoad
   {   my ($self, $type, $oid, %args) = @_;
       ...
       return $data;
   }

Your implementation MUST return the Perl complex data-structure which
was previously saved under that C<$oid> or C<undef>

Argument C<type> is (currently) either 'appsession' or 'grant'
You may have implemented separate tables for different object types.

=subsection model method: OpenConsoleSave()

The `OpenConsoleSave($type, $data, %meta)` method is called when an object
needs to be kept in the database.   The C<$data> is in a JSON-compatible
Perl complex data-structure (no blessed stuff, no refs).  The C<%meta>
parameters contain information which might be useful for your maintaining
the data.

   package MyProject::Model::MyDB;
   sub OpenConsoleSave
   {  my ($self, $type, $data, %meta) = @_;
      ...
      1;
   }

The meta structure looks like this:

   $model->OpenConsoleSave($type => $data,
      oid      => $token,       # primary key, unique
      remove   => $date,        # YYYY-mm-DDTHH:MM:SSZ
   );

=subsection model method: OpenConsoleServiceSession()

The `OpenConsoleServiceSession($service_id)` method is called to find
the currently active appsession for a certain service.  Multiple session
object may be present, because one is created for each appLogin and when
the login gets deprecated.  This method is designed for the login which
creates the button.

   package MyProject::Model::MyDB;
   sub OpenConsoleServiceSession
   {  my ($self, $service_id, %args) = @_;
      ...
      \%appsession;
   }

=subsection the saved meta-data

Please read the instructions on all of the meta fields carefully!

=over 4
=item meta: id =E<lt> $token

The C<id> (object identifier) is unique, but you may received the same
id more than once (full update).   The oid is strictly shorter than 64
characters (typical length is about 32).  You should have an index on
this field.

=item meta: type =E<lt> 'appsession'|'grant'

When you wish to put different object types in different databases
or separate tables, it is easy to do base of this C<type> field.

=item meta: remove =E<lt> $date

The C<$date> is a M<DateTime> object.

It is important to implement expiration for these short-lived
objects.  The objects have an internal C<expires> field, which is
not the same and the C<remove> date: to be able to produce better
user support messages, the objects are removed (much) later than
the expiration.

There is no urgent need to remove the objects exactly on the moment
indicated, but when you never clean-up, the database will fill-up
with useless data.  Some databases support automatic removal, in
other cases, you need to write a clean-up procedure yourself.

=back

=section The "state" parameter

In OAuth2, the C<state> parameter is used by the client (by your
application) to guarantee that incoming approvals do original from your
login button, and not a fake button made by someone else on some other
website.

The state value SHOULD be random and unpredictable, and MUST be
administered related to the session cookie which the user already
received.

In Mojolicious, we can put the random value inside the cookie, because
the whole cookie content is encrypted hence immutable and unreadible by
third parties.
=cut

# Insert of open-console-owner/public/images/open-console.svg
# Remove the first <xml> line.
BEGIN { $logo_svg = <<'__LOGO_SVG' }
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<svg version="2.1" xmlns="http://www.w3.org/2000/svg" class="oc-logo"
	 viewBox="0 0 106.25485 103.84824" width="106.25484" height="103.84824">
	<defs>
		<linearGradient id="lg1"
			 spreadMethod="pad"
			 gradientTransform="matrix(19.993069,28.347853,28.347853,-19.993069,442.40588,280.52396)"
			 gradientUnits="userSpaceOnUse"
			 y2="0" x2="1" y1="0" x1="0">
			<stop offset="0" style="stop-opacity:1;stop-color:#d4e9fa" />
			<stop offset="1" style="stop-opacity:1;stop-color:#0092d9" />
		</linearGradient>
		<linearGradient id="lg2"
			 spreadMethod="pad"
			 gradientTransform="matrix(34.600109,-2.7492745,-2.7492745,-34.600109,390.10605,287.81885)"
			 gradientUnits="userSpaceOnUse"
			 y2="0" x2="1" y1="0" x1="0">
			<stop offset="0" style="stop-opacity:1;stop-color:#e1e3f3" />
			<stop offset="0.971014" style="stop-opacity:1;stop-color:#034799" />
			<stop offset="1" style="stop-opacity:1;stop-color:#0f4496" />
		</linearGradient>
		<linearGradient id="lg3"
			 spreadMethod="pad"
			 gradientTransform="matrix(19.894482,28.412266,28.412266,-19.894482,413.18866,315.41803)"
			 gradientUnits="userSpaceOnUse"
			 y2="0" x2="1" y1="0" x1="0">
			<stop offset="0" style="stop-opacity:1;stop-color:#e0e8f7" />
			<stop offset="1" style="stop-opacity:1;stop-color:#006fb9" />
		</linearGradient>
		<clipPath id="cp1" clipPathUnits="userSpaceOnUse">
			<path d="M 0,612.283 H 858.898 V 0 H 0 Z" />
		</clipPath>
		<clipPath id="cp2" clipPathUnits="userSpaceOnUse">
			<path d="M 407.408,329.621 H 452.67 V 286.443 H 407.408 Z" />
		</clipPath>
	</defs>
	<g transform="matrix(1.3333333,0,0,-1.3333333,-520.06914,462.63466)">
		<path style="fill:url(#lg1);stroke:none"
			d="M 449.689,311.627 C 440.26,309.997 433.915,301 435.545,291.572 v 0 c 1.629,-9.428 10.626,-15.773 20.054,-14.143 v 0 c 3.112,0.537 5.884,1.881 8.148,3.774 v 0 l -5.006,6.009 c -1.244,-1.04 -2.766,-1.778 -4.474,-2.073 v 0 c -5.177,-0.895 -10.117,2.589 -11.012,7.766 v 0 c -0.894,5.177 2.59,10.116 7.766,11.012 v 0 c 5.177,0.894 10.116,-2.59 11.011,-7.767 v 0 l 7.711,1.332 c -1.458,8.433 -8.809,14.399 -17.091,14.4 v 0 c -0.978,0 -1.968,-0.083 -2.963,-0.255 m -2.492,-15.096 c -1.106,-3.008 0.436,-6.343 3.444,-7.45 v 0 c 3.008,-1.106 6.343,0.435 7.449,3.443 v 0 c 1.107,3.008 -0.435,6.343 -3.442,7.45 v 0 c -0.662,0.243 -1.338,0.358 -2.004,0.358 v 0 c -2.363,0 -4.584,-1.454 -5.447,-3.801" />
		<path style="fill:url(#lg2);stroke:none"
			d="m 404.257,303.508 c -9.41,-1.737 -15.652,-10.806 -13.915,-20.214 v 0 l 7.695,1.42 c -0.954,5.166 2.474,10.145 7.64,11.099 v 0 c 5.166,0.953 10.145,-2.474 11.099,-7.641 v 0 c 0.953,-5.166 -2.475,-10.145 -7.641,-11.099 v 0 c -1.706,-0.314 -3.39,-0.149 -4.917,0.396 v 0 L 401.6,270.1 c 2.781,-0.994 5.849,-1.295 8.956,-0.721 v 0 c 9.409,1.736 15.651,10.805 13.915,20.213 v 0 c -1.542,8.349 -8.856,14.205 -17.058,14.206 v 0 c -1.042,0 -2.096,-0.095 -3.156,-0.29 m -0.615,-12.648 c -2.438,-2.08 -2.73,-5.743 -0.65,-8.181 v 0 c 2.08,-2.439 5.742,-2.73 8.181,-0.65 v 0 c 2.439,2.079 2.73,5.742 0.65,8.181 v 0 c -1.148,1.346 -2.778,2.038 -4.418,2.037 v 0 c -1.332,0 -2.67,-0.455 -3.763,-1.387" />
		<path style="fill:url(#lg3);stroke:none"
			d="m 420.123,346.711 c -9.422,-1.662 -15.737,-10.68 -14.075,-20.103 v 0 c 1.112,-6.312 5.527,-11.224 11.152,-13.284 v 0 l 2.677,7.35 c -3.088,1.13 -5.512,3.827 -6.124,7.293 v 0 c -0.912,5.173 2.556,10.125 7.729,11.038 v 0 c 5.174,0.912 10.126,-2.555 11.037,-7.729 v 0 c 0.611,-3.466 -0.745,-6.831 -3.261,-8.95 v 0 l 5.027,-5.991 c 4.583,3.859 7.053,9.986 5.94,16.3 v 0 c -1.482,8.407 -8.823,14.34 -17.081,14.341 v 0 c -0.997,0 -2.006,-0.086 -3.021,-0.265 m 2.006,-11.375 c -3.156,-0.556 -5.264,-3.566 -4.707,-6.723 v 0 c 0.556,-3.156 3.566,-5.263 6.722,-4.707 v 0 c 3.156,0.557 5.264,3.567 4.708,6.723 v 0 c -0.497,2.816 -2.945,4.797 -5.709,4.796 v 0 c -0.334,0 -0.674,-0.029 -1.014,-0.089" />
		<g clip-path="url(#cp1)">
			<g style="opacity:0.5" clip-path="url(#cp2)">
				<g transform="translate(423.1364,329.6213)">
					<path style="fill:#ffffff;fill-opacity:1;fill-rule:nonzero;stroke:none"
						d="m 0,0 29.534,-35.197 -45.262,-7.981 z" />
				</g>
			</g>
		</g>
	</g>
</svg>
__LOGO_SVG

1;
