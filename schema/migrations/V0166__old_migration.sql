

DROP VIEW downloads_sites;

DROP INDEX downloads_sites_index;

DROP INDEX downloads_sites_pending;

DROP INDEX downloads_sites_downloads_id_pending;


CREATE OR REPLACE FUNCTION site_from_host("host" varchar) RETURNS varchar AS
$$
BEGIN
    RETURN regexp_replace(host, E'^(.)*?([^.]+)\\.([^.]+)$' ,E'\\2.\\3');
END;
$$
LANGUAGE 'plpgsql' IMMUTABLE;

CREATE INDEX downloads_sites_index ON downloads ( site_from_host(host) );

CREATE INDEX downloads_sites_pending ON downloads ( site_from_host( host ) ) where state='pending';

CREATE UNIQUE INDEX downloads_sites_downloads_id_pending ON downloads ( site_from_host(host), downloads_id ) WHERE (state = 'pending');

CREATE VIEW downloads_sites AS
	select site_from_host( host ) as site, * from downloads_media;

