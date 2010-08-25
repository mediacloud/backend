bash -c " ( \
nohup time nice ./mediawords_create_media_tag_counts.pl &> /mnt/tmp/create_media_tag_counts_output.txt && \
nohup time nice ./mediawords_create_top_ten_tags_for_media.pl &> /mnt/tmp/create_media_top_ten_tags_output.txt && \
nohup time nice ./mediawords_create_media_google_charts_map_url.pl /mnt/tmp/create_media_google_charts_map_url_output.txt  && \
nohup time nice ./mediawords_create_media_tag_tag_counts_csv_from_sub_tables.pl --csv_file=/mnt/tmp/tag_tag_tables.csv &> /mnt/tmp/create_media_tag_tag_counts_csv_from_subtables_output.txt && \
nohup time nice ./mediawords_create_media_tag_tag_counts_from_csv_file.pl --csv_file=/mnt/tmp/tag_tag_tables.csv &> /mnt/tmp/create_media_tag_tag_counts_from_csv_file_output.txt  \  
) " &> /mnt/tmp/regenerate_tag_tags.log 
