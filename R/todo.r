
## the default min docfreq in deduplicate is misleading, because 1 docfreq words do count for the similarity calculation.
## instead, make it so that for the matrix multiplication columns with sum 1 are emptied (not deleted, to preserve the resulting adjacency matrix)

## fix and test how data.table deals with factors if assign by reference is used.
## do something about how the set and set_meta methods deal with assigning by subset if the classes don't match. Yield error seems best

## there is still some funky stuff with subset and set. When a call is a single object name, it is not recognized as a call
## e.g., tc$set('feature', word) does not work, even if tc$data has a word column. But tc$set('feature', tolower(word)) would work.
## Currently the reason to only evaluate if a call is that this allows passing on of evaluation results in nested functions.
## One solution is to pass evaluation results as an evalhere_ object, and then always evaluate calls.

## when creating a tCorpus, keep all settings as provenance. When appending data, use provenance as default settings

### all functions within methods that have the copy parameter MUST work by reference only!!
### check this thoroughly!!

## add the add_data and add_tokens method. This can simply be a combination of create_tcorpus/tokens_to_tcorpus and merge_tcorpua

## add information gain measure for semnet. add function to select only the top words that contain most information about a given term (as an ego network based filter)

## add a from_csv argument to create_tcorpus, that uses the excellent data.table::fread
## (also, in time add a from_csv argument for creating huge shattered tcorpora from csv)
## alternatively, use the even more excellent readtext

## add boilerplate and remove_boilerplate functions. The idea is then to look for long identical sequences of words that occurr across many documents (and optionally, over time).
## Possible method: for long boilerplate, look for 5-grams, then given detected 5-grams look for 6-grams, 7-grams etc. till a given length, and mark as boilerplate if it occurs in more than a given pct of articles. (possibly use 90% overlap instead of 100%)
## also add option to give meta variables, that will be used to do this per group (since boilerplate is often medium specific)
## also take word possitions into account

## if multiple text columns are given to create_tcorpus, add a column that notes what part of the document it is (e.g., headline, body)
## Kohlschutter, C., Fankhauser, P., and Nejdl, W. (2010). Boilerplate detection using shallow text features. InProceedings of the 3rdACM International Conference on Web Search and Data Mining (WSDM ’10). New York, NY, USA: ACM, 441–450.
