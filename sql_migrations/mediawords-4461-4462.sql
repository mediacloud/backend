--
-- This is a Media Cloud PostgreSQL schema difference file (a "diff") between schema
-- versions 4461 and 4462.
--
-- If you are running Media Cloud with a database that was set up with a schema version
-- 4461, and you would like to upgrade both the Media Cloud and the
-- database to be at version 4462, import this SQL file:
--
--     psql mediacloud < mediawords-4461-4462.sql
--
-- You might need to import some additional schema diff files to reach the desired version.
--
--
-- 1 of 2. Import the output of 'apgdiff':
--

delete from tags t using tag_sets ts where t.tag_sets_id = ts.tag_sets_id and ts.name = 'media_type';
delete from tag_sets where name = 'media_type';
insert into tag_sets ( name, label, description ) values ( 'media_type', 'Media Type', 'High level topology for media sources for use across a variety of different topics' );

create temporary table media_type_tags ( name text, label text, description text );
insert into media_type_tags values
    ( 'Independent Group', 'Ind. Group', 'An academic or nonprofit group that is not affiliated with the private sector or government, such as the Electronic Frontier Foundation or the Center for Democracy and Technology)' ),
    ( 'Social Linking Site', 'Social Linking', 'A site that aggregates links based at least partially on user submissions and/or ranking, such as Reddit, Digg, Slashdot, MetaFilter, StumbleUpon, and other social news sites' ),
    ( 'Blog', 'Blog', 'A web log, written by one or more individuals, that is not associated with a professional or advocacy organization or institution' ), 
    ( 'General Online News Media', 'General News', 'A site that is a mainstream media outlet, such as The New York Times and The Washington Post; an online-only news outlet, such as Slate, Salon, or the Huffington Post; or a citizen journalism or non-profit news outlet, such as Global Voices or ProPublica' ),
    ( 'Issue Specific Campaign', 'Issue', 'A site specifically dedicated to campaigning for or against a single issue.' ),
    ( 'News Aggregator', 'News Agg.', 'A site that contains little to no original content and compiles news from other sites, such as Yahoo News or Google News' ),
    ( 'Tech Media', 'Tech Media', 'A site that focuses on technological news and information produced by a news organization, such as Arstechnica, Techdirt, or Wired.com' ),
    ( 'Private Sector', 'Private Sec.', 'A non-news media for-profit actor, including, for instance, trade organizations, industry sites, and domain registrars' ), 
    ( 'Government', 'Government', 'A site associated with and run by a government-affiliated entity, such as the DOJ website, White House blog, or a U.S. Senator official website' ),
    ( 'User-Generated Content Platform', 'User Gen.', 'A general communication and networking platform or tool, like Wikipedia, YouTube, Twitter, and Scribd, or a search engine like Google or speech platform like the Daily Kos' );
    
insert into tags ( tag_sets_id, tag, label, description )
    select ts.tag_sets_id, mtt.name, mtt.name, mtt.description 
        from tag_sets ts cross join media_type_tags mtt
        where ts.name = 'media_type';
        
insert into media_tags_map ( media_id, tags_id )
    select cmc.media_id, t.tags_id
        from 
            controversy_media_codes cmc
            join controversies c on ( c.controversies_id = cmc.controversies_id )
            join tags t on ( substr( cmc.code, 1, 4 ) = substr( t.tag, 1, 4 ) )
            join tag_sets ts on ( t.tag_sets_id = ts.tag_sets_id ) 
        where
            c.name = 'sopa' and
            cmc.code_type = 'media_type' and
            ts.name = 'media_type';
            
alter table cd.tags add label text;
alter table cd.tags add description text;
            
alter table cd.tag_sets add label text;
alter table cd.tag_sets add description text;

CREATE OR REPLACE FUNCTION update_media_last_updated () RETURNS trigger AS
$$
   DECLARE
   BEGIN

      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'INSERT') THEN
      	 update media set db_row_last_updated = now() where media_id = NEW.media_id;
      	 RETURN NEW;
      END IF;
      
      IF ( TG_OP = 'UPDATE' ) OR (TG_OP = 'DELETE') THEN
      	 update media set db_row_last_updated = now() where media_id = OLD.media_id;
      	 RETURN OLD;
      END IF;
   END;
$$
LANGUAGE 'plpgsql';
            
--
-- 2 of 2. Reset the database version.
--

CREATE OR REPLACE FUNCTION set_database_schema_version() RETURNS boolean AS $$
DECLARE
    
    -- Database schema version number (same as a SVN revision number)
    -- Increase it by 1 if you make major database schema changes.
    MEDIACLOUD_DATABASE_SCHEMA_VERSION CONSTANT INT := 4462;
    
BEGIN

    -- Update / set database schema version
    DELETE FROM database_variables WHERE name = 'database-schema-version';
    INSERT INTO database_variables (name, value) VALUES ('database-schema-version', MEDIACLOUD_DATABASE_SCHEMA_VERSION::int);

    return true;
    
END;
$$
LANGUAGE 'plpgsql';

SELECT set_database_schema_version();


