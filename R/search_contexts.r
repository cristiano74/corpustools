## Function for the tCorpus$search_contexts method
search_contexts <- function(tc, query, code=NULL, feature='token', context_level=c('document','sentence'), verbose=F){
  is_tcorpus(tc, T)

  if(query == '') stop('Query cannot be an empty string')
  context_level = match.arg(context_level)
  windows = stats::na.omit(get_feature_regex(query, default_window = NA)$window)
  max_window_size = if (length(windows) > 0) max(windows) else 0

  fi = tc$feature_index(feature=feature, context_level=context_level, max_window_size=max_window_size, as_ascii=T)

  if (!is.null(code)){
    code = if (length(code) == length(query)) code else rep(code, length(query))
  } else code = sprintf('query_%s', 1:length(query))

  context = tc$context(context_level, with_labels = F)
  context_i = as.numeric(context)
  context_label = levels(context)
  queries = parse_queries(query) ## add argument merge_or_groups = T

  res = list()
  for(i in 1:nrow(queries)){
    q = queries[i,]
    qm = Matrix::spMatrix(max(context_i), length(q$terms), x=logical())
    colnames(qm) = q$terms
    #rownames(qm) = context_label # for reference

    for(term in q$terms){
      hits = search_string(fi, term)
      context_hits = unique(context_i[hits$i])
      qm[,term][context_hits] = T
    }
    queryhit = eval_query_matrix(qm, q$terms, q$form)
    first_context_row = match(context_label[queryhit], context)
    if (context_level == 'document') context_columns = c('doc_id')
    if (context_level == 'sentence') context_columns = c('doc_id', 'sent_i')
    code_label = code[[i]]
    res[[code_label]] = unique(tc$get(context_columns, keep_df = T)[first_context_row,])
  }
  hits = plyr::ldply(res, function(x) x, .id='code')
  if (nrow(hits) == 0) hits = NULL

  contextHits(hits, data.frame(code=code, query=query))
}
