


-- We no longer use PL/Perl and PL/PerlU so drop support for those in the
-- database that's being migrated
DROP LANGUAGE IF EXISTS plperl;
DROP LANGUAGE IF EXISTS plperlu;



