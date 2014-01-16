#!/usr/bin/perl

use strict;
use DBI();
use CGI::OptimalQuery();
use FindBin qw($Bin);

chdir "$Bin/..";

my $dbh = DBI->connect("dbi:SQLite:dbname=test_data.db","","");

my %schema = (
  'dbh' => $dbh,
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
