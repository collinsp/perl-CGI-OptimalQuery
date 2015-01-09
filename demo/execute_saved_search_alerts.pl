#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/../lib"; # include project lib

use DBI();
use CGI::OptimalQuery::SaveSearchTool();

$DEMO::dbh ||= DBI->connect("dbi:SQLite:dbname=db/dat.db","","", { RaiseError => 1, PrintError => 1 });

# load/create a coderef of the given perl script
# not needed if you use perl modules
my %FUNCS;
sub getFunc {
  my ($fn) = @_;
  if (! exists $FUNCS{$fn}) {
    open my $fh, "<", $fn or die "can't read file $fn; $!";
    local $/=undef;
    my $code = 'sub { '.scalar(<$fh>). ' }';
    $FUNCS{$fn} = eval $code;
    die "could not compile $fn; $@" if $@;
  }
  return $FUNCS{$fn};
}

CGI::OptimalQuery::SaveSearchTool::execute_saved_search_alerts(
  # default is shown
  # error_handler => sub { print STDERR @_; },

  # if debug is true, no email is sent, emails will be logged to the error_handler
  debug => 1,

  # database handle
  dbh => $DEMO::dbh,

  # define a handler which is called for each possible alert
  # alerts aren't actually sent until the very end where they are batched
  # and one email is sent for each email address containing one or more alerts
  handler => sub {
    # $o contains all the fields defined in the oq_saved_search rec
    my ($o) = @_;

    # you must set the email address for the $$o{USER_ID} 
    $$o{EMAIL} = 'pmc2@sr.unh.edu';

    # You may need to login this user first
    # MyApp::login($$o{USERID})

    # somehow, execute your OptimalQuery
    # MyApp::Request::handler()
    if ($$o{URI} =~ /(\w+\.pl)$/) {
      getFunc("$Bin/cgi-bin/$1")->(); 
    }
  }
);
