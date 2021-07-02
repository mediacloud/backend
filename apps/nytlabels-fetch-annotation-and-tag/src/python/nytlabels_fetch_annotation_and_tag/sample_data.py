def sample_nytlabels_response() -> dict:
    return {
        "allDescriptors": [
            {
                "label": "hurricanes and tropical storms",
                "score": "0.89891",
            },
            {
                "label": "energy and power",
                "score": "0.50804"
            }
        ],
        "descriptors3000": [
            {
                "label": "hurricanes and tropical storms",
                "score": "0.82505"
            },
            {
                "label": "hurricane katrina",
                "score": "0.17088"
            }
        ],

        # Only "descriptors600" are to be used
        "descriptors600": [
            {
                # Newlines should be replaced to spaces, string should get trimmed
                "label": " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
                "score": "0.92481"
            },
            {
                "label": "electric light and power",
                "score": "0.10210"  # should be skipped due to threshold
            }
        ],

        "descriptorsAndTaxonomies": [
            {
                "label": "top/news",
                "score": "0.82466"
            },
            {
                "label": "hurricanes and tropical storms",
                "score": "0.81941"
            }
        ],
        "taxonomies": [
            {
                "label": "Top/Features/Travel/Guides/Destinations/Caribbean and Bermuda",
                "score": "0.83390"
            },
            {
                "label": "Top/News",
                "score": "0.77210"
            }
        ]
    }


def expected_nytlabels_tags() -> list:
    return [
        {
            'tag_sets_name': 'nyt_labels',
            'tags_description': " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
            'tag_sets_description': 'NYTLabels labels',
            'tags_label': " hurricanes \n and\r\ntropical\n\nstorms   \r\n  \n",
            'tags_name': 'hurricanes and tropical storms',
            'tag_sets_label': 'nyt_labels'
        },
        {
            'tag_sets_label': 'nyt_labels_version',
            'tags_label': 'nyt_labeller_v1.0.0',
            'tag_sets_description': 'NYTLabels version the story was tagged with',
            'tags_name': 'nyt_labeller_v1.0.0',
            'tag_sets_name': 'nyt_labels_version',
            'tags_description': 'Story was tagged with \'nyt_labeller_v1.0.0\''
        }
    ]
