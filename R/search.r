### search strings

search_string <- function(fi, string, allow_multitoken=T, allow_proximity=T, only_last_mtoken=F){
  ## look up a string
  ## multiple strings can be used at once (in which case they are seen as related by OR statements)
  ## supports single token strings, multitoken strings demarcated with quotes (e.g., "this string") and token proximities (e.g., "marco polo"~10)
  ## This function does not manage complex boolean queries (AND, NOT, parentheses).
  ## If multiple strings are given, results are added together as if they were connected with OR statements

  regex = get_feature_regex(string)
  is_multitoken = grepl(' ', regex$term)
  is_proximity = !is.na(regex$window)

  single = regex[!is_multitoken & !is_proximity,,drop=F]
  multi = regex[is_multitoken & !is_proximity,,drop=F]
  proxi = regex[is_multitoken & is_proximity,,drop=F]

  if (nrow(single) > 0){
    hit_single = c() # pun intended
    if(sum(single$ignore_case) > 0) hit_single = union(hit_single, batch_grep(single$regex[single$ignore_case], levels(fi$feature)))
    if(sum(!single$ignore_case) > 0) hit_single = union(hit_single, batch_grep(single$regex[!single$ignore_case], levels(fi$feature), ignore.case = F))
    hit_single = fi[list(hit_single),,nomatch=0]
    hit_single$hit_id = stringi::stri_paste('s', 1:nrow(hit_single), sep='#')
  } else {
    hit_single = NULL
  }

  if (nrow(multi) > 0){
    if (!allow_multitoken) stop('Multitoken queries ("token1 token2") not allowed here (allow_multitoken == F)')
    hit_multi_index = multitoken_grepl(fi, multi, only_last=only_last_mtoken)
    hit_multi = fi[match(hit_multi_index$global_i, fi$global_i),,nomatch=0]
    hit_multi$hit_id = stringi::stri_paste('m', hit_multi_index$hit_id, sep='#')
  } else {
    hit_multi = NULL
  }

  if (nrow(proxi) > 0){
    if (!allow_proximity) stop('Proximity queries ("token1 token2"~5) not allowed here (allow_proximity == F)')
    hit_proxi_index = proximity_grepl(fi, proxi, only_last=only_last_mtoken)
    hit_proxi = fi[match(hit_proxi_index$global_i, fi$global_i),,nomatch=0]
    hit_proxi$hit_id = stringi::stri_paste('p', hit_proxi_index$hit_id, sep='#')
  } else {
    hit_proxi = NULL
  }

  unique(plyr::rbind.fill(hit_single, hit_multi, hit_proxi))
}


batch_grep <- function(patterns, x, ignore.case=T, perl=F, batchsize=25, useBytes=T){
  ## make batches of terms and turn each batch into a single regex
  patterns = split(patterns, ceiling(seq_along(patterns)/batchsize))
  patterns = sapply(patterns, stringi::stri_paste, collapse='|')

  out = rep(F, length(x))
  for(pattern in patterns){
    out = out | grepl(pattern, x, ignore.case=ignore.case, perl=perl, useBytes=useBytes)
  }
  x[out]
}

grep_global_i <- function(fi, regex, ...) {
  exact_feature = levels(fi$feature)[grepl(regex, levels(fi$feature), ...)]
  fi[list(exact_feature),,nomatch=0]$global_i
}

multitoken_grepl <- function(fi, multi, only_last=T, ignore.case=T, perl=F, useBytes=T){
  ## keywords with underscores are considered multitoken strings. These can occur both in one row of the tcorpus features, or multiple
  ## this function doesn't care, and captures both, by walking over the tokens and checking whether they occur in the same or subsequent (i.e. next global_i) position
  hits = list()
  hit_id = 1

  mtoken_regex = strsplit(multi$regex, split=' ')
  for(i in 1:length(mtoken_regex)){
    mtoken = mtoken_regex[[i]]
    ign_case = multi$ignore_case[i]
    for(q in mtoken){
      if (q == mtoken[1]) {   ## if first token, search everything
        hit = grep_global_i(fi, q, ignore.case=ign_case, perl=perl, useBytes=useBytes)

        if (!only_last) firsthit = hit ## keep in case only_last is FALSE
      } else { ## if not first token
        ## search whether the token occurs in the same or next position as the previous token
        same_or_next = c(hit, hit + 1)
        fi_next = fi[fi$global_i %in% same_or_next,]

        hit = grep_global_i(fi, q, ignore.case=ign_case, perl=perl, useBytes=useBytes)
      }
      if (length(hit) == 0) break
    }

    hit = list(global_i=hit, hit_id = hit_id:(hit_id+(length(hit)-1)))
    hit_id = hit_id + length(hit$global_i)
    if (!only_last & length(hit) > 0){
      possible_positions_start = rep(firsthit, length(mtoken)) + (rep(1:length(mtoken), each=length(firsthit)) - 1)
      possible_positions_found = rep(hit$global_i, length(mtoken)) - (rep(1:length(mtoken), each=length(hit$global_i)) - 1)
      hit_id_exp = rep(hit$hit_id, length(mtoken))
      keep = possible_positions_found %in% possible_positions_start ## intersect from start to end to account for multiple tokens in 1
      hit = list(global_i=possible_positions_found[keep], hit_id=hit_id_exp[keep])
    }
    if (length(hit$global_i) > 0) hits[['']] = hit
  }
  rbindlist(hits)
}

proximity_grepl <- function(fi, proxi, only_last=T, ignore.case=T, perl=F, useBytes=T){
  hits = list()
  if (any(proxi$window < 1)) stop("window cannot be smaller than 1")

  ptoken_regex = strsplit(proxi$regex, split=' ')
  for(i in 1:length(ptoken_regex)){
    q = ptoken_regex[[i]]
    ign_case = proxi$ignore_case[i]

    window = proxi$window[i]
    ptoken_i = data.frame()              # is this specific global i one of the ptokens
    ptoken_window = 1:max(fi$global_i)   # for which global i's do all ptokens occur within the given window
    for(j in 1:length(q)){
        hit_i = grep_global_i(fi, q[j], ignore.case=ign_case, perl=perl, useBytes=useBytes)
        if (length(hit_i) > 0){
          if (only_last){
            if (j == length(q)) {# only remember position if token is last token
              ptoken_i = rbind(ptoken_i, data.frame(global_i=hit_i, j=j))
            }
          } else {
            ptoken_i = rbind(ptoken_i, data.frame(global_i=hit_i, j=j))
          }
        }
        i_window = rep(hit_i, window*2 + 1) + rep(-window:window, each=length(hit_i)) ## add window
        ptoken_window = intersect(ptoken_window, i_window)
    }

    ## for the hit_id, use the gaps in the ptoken_window (n)
    if (length(ptoken_window) > 0){
      isgap = ptoken_window - shift(ptoken_window, 1, 0) > 1
      hit_id_index = data.frame(global_i = ptoken_window,
                                hit_id = cumsum(isgap))

      hit = ptoken_i[ptoken_i$global_i %in% ptoken_window,]
      hit$hit_id = hit_id_index$hit_id[match(hit$global_i, hit_id_index$global_i)]

      ## There can still be positions where not all of the tokens occur (e.g., if for two tokens only the windows overlap, and the third tokens lies in the overlap)
      ## We delete these tokens but only keeping hit_ids where all tokens occur.
      full_hits = table(unique(hit[,c('hit_id','j'),drop=F])$hit_id)
      full_hits = names(full_hits[full_hits == length(q)])
      hit = hit[hit$hit_id %in% full_hits,]

      hit = hit[order(hit$global_i),]
      sub_hit = unlist(tapply(hit$j, hit$hit_id, full_set_ids)) ## make more specific hit_ids within windows if there are multiple occurence of each token

      hit$hit_id = stringi::stri_paste(i, hit$hit_id, sub_hit, sep='#')

      hits[['']] = hit
    }
  }
  rbindlist(hits)
}


full_set_ids <- function(id){
  .Call('corpustools_full_set_ids', PACKAGE = 'corpustools', id, min(table(id)))
}

