

-- cached extractor results for extraction jobs with use_cache set to true
create table cached_extractor_results(
    cached_extractor_results_id         bigserial primary key,
    extracted_html                      text,
    extracted_text                      text,
    downloads_id                        bigint
);



