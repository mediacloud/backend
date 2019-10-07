def sample_cliff_response() -> dict:
    return {
        "milliseconds": 231,
        "results": {
            "organizations": [
                {
                    "count": 2,

                    # Newlines should be replaced to spaces, string should get trimmed
                    "name": " Kansas\nHealth\nInstitute   \n  ",
                },
                {
                    "count": 2,

                    # Test whether tags that already exist get merged into one
                    "name": "Kansas Health Institute",
                },
                {
                    "count": 3,
                    "name": "Census Bureau",
                },
            ],
            "people": [
                {
                    "count": 7,
                    "name": "Tim Huelskamp",
                },
                {
                    "count": 5,
                    "name": "a.k.a. Obamacare",
                },
            ],
            "places": {
                "focus": {
                    "cities": [
                        {
                            "countryCode": "US",
                            "countryGeoNameId": "6252001",
                            "featureClass": "P",
                            "featureCode": "PPLA2",
                            "id": 5391959,
                            "lat": 37.77493,
                            "lon": -122.41942,
                            "name": "San Francisco",
                            "population": 805235,
                            "score": 1,
                            "stateCode": "CA",
                            "stateGeoNameId": "5332921",
                        },
                        {
                            "countryCode": "US",
                            "countryGeoNameId": "6252001",
                            "featureClass": "P",
                            "featureCode": "PPL",
                            "id": 5327684,
                            "lat": 37.87159,
                            "lon": -122.27275,
                            "name": "Berkeley",
                            "population": 112580,
                            "score": 1,
                            "stateCode": "CA",
                            "stateGeoNameId": "5332921",
                        }
                    ],
                    "countries": [
                        {
                            "countryCode": "US",
                            "countryGeoNameId": "6252001",
                            "featureClass": "A",
                            "featureCode": "PCLI",
                            "id": 6252001,
                            "lat": 39.76,
                            "lon": -98.5,
                            "name": "United States",
                            "population": 310232863,
                            "score": 10,
                            "stateCode": "00",
                            "stateGeoNameId": "",
                        }
                    ],
                    "states": [
                        {
                            "countryCode": "US",
                            "countryGeoNameId": "6252001",
                            "featureClass": "A",
                            "featureCode": "ADM1",
                            "id": 4273857,
                            "lat": 38.50029,
                            "lon": -98.50063,
                            "name": "Kansas",
                            "population": 2740759,
                            "score": 10,
                            "stateCode": "KS",
                            "stateGeoNameId": "4273857",
                        },
                        {
                            "countryCode": "US",
                            "countryGeoNameId": "6252001",
                            "featureClass": "A",
                            "featureCode": "ADM1",
                            "id": 5332921,
                            "lat": 37.25022,
                            "lon": -119.75126,
                            "name": "California",
                            "population": 37691912,
                            "score": 2,
                            "stateCode": "CA",
                            "stateGeoNameId": "5332921",
                        },
                    ],
                },
            },
            "mentions": [
                {
                    "confidence": 1,
                    "countryCode": "US",
                    "countryGeoNameId": "6252001",
                    "featureClass": "A",
                    "featureCode": "ADM1",
                    "id": 4273857,
                    "lat": 38.50029,
                    "lon": -98.50063,
                    "name": "Kansas",
                    "population": 2740759,
                    "source": {
                        "charIndex": 162,
                        "string": "Kansas",
                    },
                    "stateCode": "KS",
                    "stateGeoNameId": "4273857",
                },
                {
                    "confidence": 1,
                    "countryCode": "US",
                    "countryGeoNameId": "6252001",
                    "featureClass": "P",
                    "featureCode": "PPL",
                    "id": 5327684,
                    "lat": 37.87159,
                    "lon": -122.27275,
                    "name": "Berkeley",
                    "population": 112580,
                    "source": {
                        "charIndex": 6455,
                        "string": "Berkeley",
                    },
                    "stateCode": "CA",
                    "stateGeoNameId": "5332921",
                },
            ],
        },
        "status": "ok",
        "version": "2.4.1",
    }


def expected_cliff_tags() -> list:
    return [
        {
            'tag_sets_name': 'cliff_geonames',
            'tag_sets_label': 'cliff_geonames',
            'tag_sets_description': 'CLIFF geographical names',
            'tags_name': 'geonames_4273857',
            'tags_label': 'Kansas',
            'tags_description': 'Kansas | A | KS | US',
        },
        {
            'tag_sets_name': 'cliff_geonames',
            'tag_sets_label': 'cliff_geonames',
            'tag_sets_description': 'CLIFF geographical names',
            'tags_name': 'geonames_5327684',
            'tags_label': 'Berkeley',
            'tags_description': 'Berkeley | P | CA | US',
        },
        {
            'tag_sets_name': 'cliff_geonames',
            'tag_sets_label': 'cliff_geonames',
            'tag_sets_description': 'CLIFF geographical names',
            'tags_name': 'geonames_5332921',
            'tags_label': 'California',
            'tags_description': 'California | A | CA | US',
        },
        {
            'tag_sets_name': 'cliff_geonames',
            'tag_sets_label': 'cliff_geonames',
            'tag_sets_description': 'CLIFF geographical names',
            'tags_name': 'geonames_5391959',
            'tags_label': 'San Francisco',
            'tags_description': 'San Francisco | P | CA | US',
        },
        {
            'tag_sets_name': 'cliff_geonames',
            'tag_sets_label': 'cliff_geonames',
            'tag_sets_description': 'CLIFF geographical names',
            'tags_name': 'geonames_6252001',
            'tags_label': 'United States',
            'tags_description': 'United States | A | US',
        },
        {
            'tag_sets_name': 'cliff_organizations',
            'tag_sets_label': 'cliff_organizations',
            'tag_sets_description': 'CLIFF organizations',
            'tags_name': 'Census Bureau',
            'tags_label': 'Census Bureau',
            'tags_description': 'Census Bureau',
        },
        {
            'tag_sets_name': 'cliff_organizations',
            'tag_sets_label': 'cliff_organizations',
            'tag_sets_description': 'CLIFF organizations',
            'tags_name': 'Kansas Health Institute',
            'tags_label': " Kansas\nHealth\nInstitute   \n  ",
            'tags_description': " Kansas\nHealth\nInstitute   \n  ",
        },
        {
            'tag_sets_name': 'cliff_people',
            'tag_sets_label': 'cliff_people',
            'tag_sets_description': 'CLIFF people',
            'tags_name': 'a.k.a. Obamacare',
            'tags_label': 'a.k.a. Obamacare',
            'tags_description': 'a.k.a. Obamacare',
        },
        {
            'tag_sets_name': 'cliff_people',
            'tag_sets_label': 'cliff_people',
            'tag_sets_description': 'CLIFF people',
            'tags_name': 'Tim Huelskamp',
            'tags_label': 'Tim Huelskamp',
            'tags_description': 'Tim Huelskamp',
        },
        {
            'tag_sets_name': 'geocoder_version',
            'tag_sets_label': 'geocoder_version',
            'tag_sets_description': 'CLIFF version the story was tagged with',
            'tags_name': 'cliff_clavin_v2.4.1',
            'tags_label': 'cliff_clavin_v2.4.1',
            'tags_description': 'Story was tagged with \'cliff_clavin_v2.4.1\'',
        },
    ]
