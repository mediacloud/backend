# ELK logging


## Setup

1. Create the following [index patterns](http://localhost:5601/app/management/kibana/indexPatterns):
    * `auditbeat-*`
    * `filebeat-*`
    * `journalbeat-*`
    * `*` ("all" index)

    Use `@timestamp` as *Time field* for all index patterns.

2. Go to [Console under Dev Tools](http://localhost:5601/app/dev_tools#/console), copy in the following request and run it:

    ```
    PUT /_all/_settings?preserve_existing=true
    {
      "index.max_docvalue_fields_search" : "1000"
    }
    ```
