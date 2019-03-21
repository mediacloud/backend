

ALTER TABLE media add constraint media_dup_media_id_fkey_deferrable FOREIGN KEY (dup_media_id) REFERENCES media(media_id) ON DELETE SET NULL DEFERRABLE;
ALTER table media DROP CONSTRAINT media_dup_media_id_fkey;
ALTER TABLE media add constraint media_dup_media_id_fkey FOREIGN KEY (dup_media_id) REFERENCES media(media_id) ON DELETE SET NULL DEFERRABLE;
ALTER table media DROP CONSTRAINT media_dup_media_id_fkey_deferrable;


