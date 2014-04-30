# -*- perl -*-

# t/001_load.t - check module loading and create testing directory
use Test::More tests => 10;

use warnings;
no warnings qw( uninitialized );

use_ok('CGI::OptimalQuery');
use_ok('CGI::OptimalQuery::PrinterFriendly');
use_ok('CGI::OptimalQuery::CSV');
use_ok('CGI::OptimalQuery::InteractiveFilter');
use_ok('CGI::OptimalQuery::InteractiveQuery');
use_ok('CGI::OptimalQuery::XML');
use_ok('CGI::OptimalQuery::InteractiveQuery2');
use_ok('CGI::OptimalQuery::InteractiveFilter2');
use_ok('CGI::OptimalQuery::ShowColumns');
use_ok('CGI::OptimalQuery::InteractiveQuery2Tools');

