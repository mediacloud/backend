var wcDataset = {{story_length_info['values_json']}};
histogramChart("#mcWordCounts",wcDataset,400,100,20,{{story_length_info['final_bucket']}},{{story_length_info['items_to_show']}},{{story_length_info['biggest_value']}},{{story_length_info['items_to_show']/4}});

var rlDataset = {{reading_level_info['values_json']}};
histogramChart("#mcReadability",rlDataset,400,50,20,{{reading_level_info['final_bucket']}},{{reading_level_info['items_to_show']}},{{reading_level_info['biggest_value']}},10);
