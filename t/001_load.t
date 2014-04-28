# -*- perl -*-

# t/001_load.t - check module loading and create testing directory
use File::Temp();
use DBI();
use Test::More tests => 13;

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


# create test database, make some test data
my $tempdb_fn = File::Temp::mktemp('cgi_oq_sqlite_testdb_XXXX');
END { unlink $tempdb_fn }
my $dbh = DBI->connect("dbi:SQLite:dbname=$tempdb_fn","","");
{
  # test people
  $dbh->do("CREATE TABLE person ( person_id INTEGER, name TEXT, birthdate INTEGER )");
  my @people = (
    [1, 'Harrison Ford', 19420713],
    [2, 'Mark Hamill', 19510925],
    [3, 'Irvin Kershner', 19230429],
    [4, 'Richard Marquand', 19380101],
    [5, 'Steven Spielberg', 19461218],
  );
  $dbh->do("INSERT INTO person VALUES (?,?,?)", undef, @$_) for @people;

  # test movies
  $dbh->do("CREATE TABLE movie ( movie_id INTEGER, name TEXT, releaseyear INTEGER, director_person_id INTEGER )");
  my @movies = (
    [1, 'The Empire Strikes Back', 1980, 3],
    [2, 'Return of the Jedi', 1983, 4],
    [3, 'Raiders of the Lost Ark', 1981, 5]
  );
  $dbh->do("INSERT INTO movie VALUES (?,?,?,?)", undef, @$_) for @movies;

  # test cast
  $dbh->do("CREATE TABLE moviecast ( movie_id INTEGER, person_id INTEGER)");
  my @cast = ([1,1],[1,2],[2,1],[2,2],[3,1]);
  $dbh->do("INSERT INTO moviecast VALUES (?,?)", undef, @$_) for @cast;
}
pass("create testdb");

# create a test optimal query
my $o = CGI::OptimalQuery->new({
  'URI' => '/Movies',
  'dbh' => $dbh,
  'select' => {
    'ID' => ['movie','movie.movie_id','Movie ID'],
    'NAME' => ['movie','movie.name','Movie Name'],
    'DIRECTOR' => ['director', 'director.name', "Director's Name"],
    'CAST' => ['moviecastperson', 'moviecastperson.name', 'All Cast (seprated by commas)'],
    'DIRECTOR_BITHDATE' => ['director', 'director.birthdate', 'Director Birthdate'],
    'RELEASE_YEAR' => ['movie', 'movie.releaseyear', 'Release Year']
  },
  module => 'CSV',
  'joins' => {
    'movie' => [undef, 'movie'],
    'director' => ['movie', 'LEFT JOIN person director ON (movie.director_person_id = director.person_id)'],
    'moviecast' => ['movie', 'JOIN moviecast ON (movie.movie_id = moviecast.movie_id)', undef, { new_cursor => 1 }],
    'moviecastperson' => ['moviecast', 'JOIN person moviecastperson ON (moviecast.person_id= moviecastperson.person_id)']
  }
});
isa_ok ($o, 'CGI::OptimalQuery::Base');

$o->output();
pass("able to output");

