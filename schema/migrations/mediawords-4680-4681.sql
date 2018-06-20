--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4680 and 4681.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4680, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4681, import this SQL file:
--
--     psql mediacloud < mediawords-4680-4681.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--

--
-- 1 of 2. Import the output of 'apgdiff':
--

SET search_path = public, pg_catalog;


-- To be recreated later
DROP VIEW media_with_media_types;
DROP VIEW feedly_unscraped_feeds;


DROP VIEW media_with_collections;
DROP VIEW downloads_sites;

DROP INDEX media_name_trgm;
DROP INDEX media_url_trgm;
DROP INDEX feeds_reparse;
DROP INDEX downloads_in_old_format;
DROP INDEX downloads_sites_pending;
DROP INDEX downloads_sites_downloads_id_pending;

DROP TABLE media_rss_full_text_detection_data;

ALTER TABLE media DROP COLUMN last_solr_import_date;
ALTER TABLE feeds DROP COLUMN reparse;

DROP FUNCTION site_from_host(varchar);


-- Remove obsolete tags
EXPLAIN DELETE FROM tags
WHERE (tag, label, description) IN (
    (
        'Not Typed',
        'Not Typed',
        'The medium has not yet been typed.'
    ),
    (
        'Other',
        'Other',
        'The medium does not fit in any listed type.'
    ),
    (
        'Independent Group',
        'Ind. Group',

        -- Single multiline string
        'An academic or nonprofit group that is not affiliated with the private sector or government, '
        'such as the Electronic Frontier Foundation or the Center for Democracy and Technology)'
    ),
    (
        'Social Linking Site',
        'Social Linking',

        -- Single multiline string
        'A site that aggregates links based at least partially on user submissions and/or ranking, '
        'such as Reddit, Digg, Slashdot, MetaFilter, StumbleUpon, and other social news sites'
    ),
    (
        'Blog',
        'Blog',

        -- Single multiline string
        'A web log, written by one or more individuals, that is not associated with a professional '
        'or advocacy organization or institution'
    ),
    (
        'General Online News Media',
        'General News',

        -- Single multiline string
        'A site that is a mainstream media outlet, such as The New York Times and The Washington Post; '
        'an online-only news outlet, such as Slate, Salon, or the Huffington Post; '
        'or a citizen journalism or non-profit news outlet, such as Global Voices or ProPublica'
    ),
    (
        'Issue Specific Campaign',
        'Issue',
        'A site specifically dedicated to campaigning for or against a single issue.'
    ),
    (
        'News Aggregator',
        'News Agg.',

        -- Single multiline string
        'A site that contains little to no original content and compiles news from other sites, '
        'such as Yahoo News or Google News'
    ),
    (
        'Tech Media',
        'Tech Media',

        -- Single multiline string
        'A site that focuses on technological news and information produced by a news organization, '
        'such as Arstechnica, Techdirt, or Wired.com'
    ),
    (
        'Private Sector',
        'Private Sec.',

        -- Single multiline string
        'A non-news media for-profit actor, including, for instance, trade organizations, industry '
        'sites, and domain registrars'
    ),
    (
        'Government',
        'Government',

        -- Single multiline string
        'A site associated with and run by a government-affiliated entity, such as the DOJ website, '
        'White House blog, or a U.S. Senator official website'
    ),
    (
        'User-Generated Content Platform',
        'User Gen.',

        -- Single multiline string
        'A general communication and networking platform or tool, like Wikipedia, YouTube, Twitter, '
        'and Scribd, or a search engine like Google or speech platform like the Daily Kos'
    )
);


create view media_with_media_types as
    select m.*, mtm.tags_id media_type_tags_id, t.label media_type
    from
        media m
        left join (
            tags t
            join tag_sets ts on ( ts.tag_sets_id = t.tag_sets_id and ts.name = 'media_type' )
            join media_tags_map mtm on ( mtm.tags_id = t.tags_id )
        ) on ( m.media_id = mtm.media_id );

create view feedly_unscraped_feeds as
    select f.*
        from feeds f
            left join scraped_feeds sf on
                ( f.feeds_id = sf.feeds_id and sf.import_module = 'MediaWords::ImportStories::Feedly' )
        where
            f.type = 'syndicated' and
            f.active = 't' and
            sf.feeds_id is null;


CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4681;

BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;

END;
$$
LANGUAGE 'plpgsql';

--
-- 2 of 2. Reset the database version.
--
SELECT set_database_schema_version();

