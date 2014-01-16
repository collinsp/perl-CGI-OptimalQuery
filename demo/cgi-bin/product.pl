#!/usr/bin/perl

use strict;
use FindBin qw($Bin);
use lib "$Bin/../../lib"; # include project lib

use DBI();
use CGI::OptimalQuery();

chdir "$Bin/..";

my $dbh = DBI->connect("dbi:SQLite:dbname=db/dat.db","","");

my %schema = (
  'dbh' => $dbh,
  'savedSearchUserID' => 12345,
  'title' => 'The Product Catalog',
  'select' => {
    'U_ID' => ['product', 'product.id', 'SYS ID', { always_select => 1 }],
    'NAME' => ['product', 'product.name', 'Name'],
    'PRODNO' => ['product', 'product.prodno', 'Product No.'],
    'MANUFACT' => ['manufact', 'manufact.name', 'Manufacturer']
  },
  'show' => "NAME,MANUFACT",
  'joins' => {
    'product' => [undef, 'product'],
    'manufact' => ['product', 'LEFT JOIN manufact ON (product.manufact=manufact.id)'],
  },
  'options' => {
    'CGI::OptimalQuery::InteractiveQuery' => {
      'editLink' => 'record.pl'
    }
  }
);

CGI::OptimalQuery->new(\%schema)->output();
