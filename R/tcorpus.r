tCorpus <- R6::R6Class("tCorpus",
   private = list(
     .data = NULL,
     .meta = NULL,
     .feature_index = NULL,
     .p = list(),

     set_provenance = function(...){
       p = list(...)
       for(key in names(p)) private$.p[[key]] = p[[key]]
     },
     is_provenance = function(...){
       p = list(...)
       for(key in names(p)) {
         if (!key %in% names(private$.p)) return(FALSE)
         if (!private$.p[[key]] == p[[key]]) return(FALSE)
       }
       return(TRUE)
     },
     select_rows = function(selection) {
       selection = safe_selection(private$.data, selection)
       private$.data = subset(private$.data, selection)
       private$.meta = private$.meta[as.character(unique(private$.data$doc_id)),,nomatch=0]
       private$.meta$doc_id = as.character(private$.meta$doc_id)
       self$reset_feature_index()
       self$set_keys()
     },
     select_meta_rows = function(selection) {
       selection = safe_selection(private$.meta, selection)
       private$.meta = subset(private$.meta, selection)
       private$.meta$doc_id = as.character(private$.meta$doc_id)
       private$.data = private$.data[as.character(unique(private$.meta$doc_id)),,nomatch=0]
       self$reset_feature_index()
       self$set_keys()
     }
   ),

   public = list(
     clone_on_change = T, ## if TRUE, tCorpus works like 'typical' R (modify on copy). If FALSE, all modifications made using methods will be made to the referenced data. Not needing to copy data is a great boon of R6 as a reference class, but we should keep this optional to facilitate the common R workflow
     auto_gc = T, ## if TRUE, automatically perform gc() within functions that create large copies. R seems to handle the cleaning of R6 environments poorly (which can be huge for a tCorpus). It appears (but needs more testing) that R sometimes goes for the swap memory even though RAM has already been freed.
     help = function() ?tCorpus,

     initialize = function(data, meta, feature_index=NULL, p=NULL) {
       private$.data = data.table(data)
       private$.meta = data.table(meta)
       private$.p = if (!is.null(p)) p else list()
       private$.feature_index = if (!is.null(feature_index)) feature_index else NULL
       self$set_keys()
     },


## SHOW/GET DATA METHODS ##
     provenance = function() private$.p,

     feature_index = function(feature='word', context_level='document', max_window_size=100, as_ascii=F){
       if (max_window_size < 100) max_window_size = 100 ## always use a window of at least 100,
       prov = private$.p
       if (is.null(private$.feature_index)){
         private$.feature_index = create_feature_index(self, feature=feature, context_level=context_level, max_window_size=max_window_size, as_ascii=as_ascii)
         private$set_provenance(index_feature=feature, context_level=context_level, max_window_size=max_window_size, as_ascii=as_ascii)
         message('Created feature index')
       } else {
         if (!private$is_provenance(index_feature=feature, context_level=context_level, max_window_size=max_window_size, as_ascii=as_ascii)) {
           private$.feature_index = create_feature_index(self, feature=feature, context_level=context_level, max_window_size=max_window_size, as_ascii=as_ascii)
           private$set_provenance(index_feature=feature, context_level=context_level, max_window_size=max_window_size, as_ascii=as_ascii)
           message('Created new feature index')
         }
       }
       private$.feature_index
     },

     context = function(context_level = c('document','sentence'), with_labels=T){
       get_context(self, context_level = context_level, with_labels=with_labels)
     },

     dtm = function(feature, context_level=c('document','sentence'), weight=c('termfreq','docfreq','tfidf','norm_tfidf'), drop_empty_terms=T, form=c('Matrix', 'tm_dtm', 'quanteda_dfm'), subset_tokens=NULL, subset_meta=NULL, context=NULL, context_labels=T, feature_labels=T, ngrams=NA, ngram_before_subset=F, env=environment()) {
       subset_tokens = if (is(substitute(subset_tokens), 'call')) deparse(substitute(subset_tokens)) else subset_tokens
       subset_meta = if (is(substitute(subset_meta), 'call')) deparse(substitute(subset_meta)) else subset_meta

       get_dtm(self, feature=feature, context_level=context_level, weight=weight, drop_empty_terms=drop_empty_terms, form=form, subset_tokens=subset_tokens, subset_meta=subset_meta, context=context, context_labels=context_labels, feature_labels=feature_labels, ngrams=ngrams, ngram_before_subset=ngram_before_subset, env=env)
     },

## DATA MODIFICATION METHODS ##
     transform = function(..., clone=self$clone_on_change, safe=T) {
       if (clone) {
         selfclone = self$copy_clone()$transform(..., clone=F, safe=safe)
         return(selfclone)
       }
       en = elip_names(...)
       if (any(en == '')) stop('Arguments (...) need to have a name')
       if (safe & any(en %in% c('doc_id','sent_i','word_i'))) stop('The position columns (doc_id, sent_i, word_i) cannot be set or changed (with safe = T)')

       attach(parent.frame(), warn.conflicts = F) ## enable the use of objects from the environment from which the method is called.
       private$.data = transform(private$.data, ...)
       if (any(en %in% self$provenance()$index_feature)) self$reset_feature_index # reset feature index if necessary
       self$set_keys()
       invisible(self)
     },

     within = function(expr, clone=self$clone_on_change, safe=T){
       if (!class(substitute(expr)) == 'name') expr = deparse(substitute(expr)) ## cannot pass on expression, so make character (if not already parsed, which happens if clone is true)
       if (clone) {
         selfclone = self$copy_clone()$within(expr, clone=F, safe=safe)
         return(selfclone)
       }
       en = expr_names(expr)
       if (safe & any(en %in% c('doc_id','sent_i','word_i'))) stop('The position columns (doc_id, sent_i, word_i) cannot be set or changed (with safe = T)')

       attach(parent.frame(), warn.conflicts = F) ## enable the use of objects from the environment from which the method is called.
       private$.data = within(private$.data, eval(parse(text=expr)))

       if (any(en %in% self$provenance()$index_feature)) self$reset_feature_index # reset feature index if necessary
       self$set_keys()
       invisible(self)
     },

     copy_clone = function(){
       selfclone = self$clone()
       selfclone$data = data.table::copy(private$.data)
       selfclone$meta = data.table::copy(private$.meta)
       if (self$auto_gc) gc()
       selfclone
     },

     set_column = function(column, value, subset=NULL, clone=self$clone_on_change, safe=T){
       subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
       if (clone) {
         selfclone = self$copy_clone()$set_column(column=column, value=value, subset=subset, clone=F, safe=safe)
         return(selfclone)
       }

       if (safe & column %in% c('doc_id','sent_i','word_i')) stop('The position columns (doc_id, sent_i, word_i) cannot be set or changed (with safe = T)')
       if (!is.null(subset)){
         r = eval_subset(private$.data, subset)
         if (!column %in% colnames(private$.data)) {
           private$.data[,(column) := NA]
           if (is(value, 'factor')) private$.data[,(column) := fast_factor(private$.data[[column]])]
         }
         if (is(private$.data[[column]], 'factor')) {
           value = fast_factor(value)
           levels(private$.data[[column]]) = c(levels(private$.data[[column]]), levels(value))
         }
         private$.data[r, (column) := value]

       } else {
         ## ugly suppress. Should look into why data.table give the (seemingly harmless) internal.selfref warning
         suppressWarnings(private$.data[,(column) := value])
       }
       if (identical(self$provenance()$index_feature, column)) self$reset_feature_index # reset feature index if necessary
       self$set_keys()
       invisible(self)
     },

     select_columns = function(cnames, clone=self$clone_on_change){
       protected_cols = intersect(self$names, c('doc_id', 'sent_i', 'word_i'))
       if (!any(protected_cols %in% cnames)) stop('selection (cnames) must contain the (existing) position columns (doc_id, word_i, sent_i)')
       if (clone) {
         selfclone = self$copy_clone()$select_columns(cnames=cnames, clone=F)
         return(selfclone)
       }
       private$.data = private$.data[,cnames,with=F]
       invisible(self)
     },

     set_colname = function(oldname, newname) {
       if (oldname %in% c('doc_id','sent_i','word_i')) stop('The position columns (doc_id, sent_i, word_i) cannot be set or changed (with safe = T)')
       colnames(private$.data)[colnames(private$.data) == oldname] = newname
       invisible(self)
     },

     transform_meta = function(..., clone=self$clone_on_change, safe=T) {
       if (clone) {
         selfclone = self$copy_clone()$transform_meta(..., clone=F, safe=safe)
         return(selfclone)
       }
       en = elip_names(...)
       if (any(en == '')) stop('Arguments (...) need to have a name')
       if (safe & any(en %in% c('doc_id'))) stop('The doc_id column cannot be set or changed (with safe = T)')
       attach(parent.frame(), warn.conflicts = F) ## enable the use of objects from the environment from which the method is called.
       private$.meta = transform(private$.meta, ...)
       invisible(self)
     },

     within_meta = function(expr, clone=self$clone_on_change, safe=T){
       if (!class(substitute(expr)) == 'name') expr = deparse(substitute(expr)) ## cannot pass on expression, so make character (if not already parsed, which happens if clone is true)
       if (clone) {
         selfclone = self$copy_clone()$within_meta(expr, clone=F, safe=safe)
         return(selfclone)
       }
       en = expr_names(expr)
       if (safe & any(en %in% c('doc_id'))) stop('The doc_id column cannot be set or changed (with safe = T)')

       attach(parent.frame(), warn.conflicts = F) ## enable the use of objects from the environment from which the method is called.
       private$.meta = within(private$.meta, eval(parse(text=expr)))
       invisible(self)
     },

     set_meta_column = function(column, value, subset=NULL, clone=self$clone_on_change, safe=T){
       subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
       if (clone) {
         selfclone = self$copy_clone()$set_meta_column(column=column, value=value, subset=subset, clone=F, safe=safe)
         return(selfclone)
       }
       if (safe & column %in% c('doc_id')) stop('The doc_id column cannot be set or changed (with safe = T)')
       if (!is.null(subset)){
         r = eval_subset(private$.meta, subset)
         if (!column %in% colnames(private$.meta)) {
           private$.meta[[column]] = NA
           if (is(value, 'factor')) private$.meta[[column]] = fast_factor(private$.meta[[column]])
         }
         if (is(private$.meta[[column]], 'factor')) {
           value = fast_factor(value)
         }
         private$.meta[[column]][r] = value
       } else {
         private$.meta[[column]] = value
       }
       invisible(self)
     },

     select_meta_columns = function(cnames, clone=self$clone_on_change){
        protected_cols = intersect(self$names, c('doc_id'))
        if (!any(protected_cols %in% cnames)) stop('selection (cnames) must contain the document id (doc_id)')
        if (clone) {
          selfclone = self$copy_clone()$select_meta_columns(cnames=cnames, clone=F)
          return(selfclone)
        }
        private$.meta = private$.meta[,cnames,with=F]
        invisible(self)
      },

     set_meta_colname = function(oldname, newname) {
       if (oldname %in% c('doc_id','sent_i','word_i')) stop('The position columns (doc_id, sent_i, word_i) cannot be set or changed (with safe = T)')
       colnames(private$.meta)[colnames(private$.meta) == oldname] = newname
     },

     subset = function(subset=NULL, subset_meta=NULL, drop_levels=T, window=NULL, env=parent.frame(2), clone=self$clone_on_change){
       ## Note about env: in normal subset the parent.frame is used in eval, to also enable the use of objects from the environment from which subset is called. Here we need to go up 2 levels, since subset is called through the R6 class environment.
       ## the reason for passing environment as an argument is that in some cases subset is called through another function, in which case the required environment lies even deeper.

       subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
       subset_meta = if (is(substitute(subset_meta), 'call')) deparse(substitute(subset_meta)) else subset_meta

       if (clone) {
         selfclone = self$copy_clone()$subset(subset=subset, subset_meta=subset_meta, drop_levels=drop_levels, window=window, clone=F)
         return(selfclone)
       }
       e = if (is(substitute(subset), 'character')) parse(text=subset) else substitute(subset)
       e_meta = if (is(substitute(subset_meta), 'character')) parse(text=subset_meta) else substitute(subset_meta)

       r_meta = eval(e_meta, private$.meta, env)
       #r_meta = eval(e_meta, private$.meta, parent.frame(2))

       if (!is.null(r_meta)) {
         r_meta[is.na(r_meta)] = F
         private$select_meta_rows(r_meta) ## also deletes tokens belonging to documents
       }
       #r = eval(e, private$.data, parent.frame(2))
       r = eval(e, private$.data, env)
       if (!is.null(r)){
         r[is.na(r)] = F
         if (!is.null(window)){
           global_i = get_global_i(self, max_window_size=window)
           global_r = global_i[r]
           global_window = rep(global_r, window*2 + 1) + rep(-window:window, each=length(global_r)) ## add window
           r = global_i %in% global_window
         }
         private$select_rows(r) ## also deletes meta documents if all tokens of the document have been deleted
       }

       if (drop_levels) self$droplevels(clone=F)
       invisible(self)
     },

      subset_i = function(subset=NULL, subset_meta=NULL, window=NULL, inverse=F, env=environment()){
        subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
        subset_meta = if (is(substitute(subset_meta), 'call')) deparse(substitute(subset_meta)) else subset_meta

        ## use own subsetting:
        ## if meta is given:
        ## - first make a copy of .data
        ## - add row_id column to this copy
        ## - subset it by meta doc_id
        ## - subset it by token subset, and return i
        ## if meta subset is not given
        ## - simply evaluate the subset and return which

        ## perhaps env can then also be removed

        tc = self$set_column('i', 1:self$n)
        i = tc$subset(subset=subset, subset_meta=subset_meta, window=window, env=env, clone=F)$data$i

        if (!inverse) i else !1:self$n %in% i
      },

     reset_feature_index = function(){
       private$.feature_index = NULL
       private$set_provenance(index_feature=NULL, context_level=NULL, max_window_size=NULL, as_ascii=NULL)
     },

     cast = function(meta_cols=NULL, hits=NULL, feature=NULL, doc_count=T){
        meta = data.table::copy(private$.meta)
        if (is.null(meta_cols)) {
          meta[,group := 'total']
          meta_cols = 'group'
        }

        d = meta[, list(N=.N), by=meta_cols]

        if (!is.null(hits) | !is.null(feature)){
          if (!is.null(hits) & !is.null(feature)) stop('Cannot specify both hits and feature')
          if (!is.null(hits)) {
            if (!is(hits, c('featureHits', 'contextHits'))) stop('hits must be a featureHits or contextHits object (see the $search_features and $search_contexts methods)')
            if (is(hits, 'featureHits')) {
              coldata = hits$hits[!duplicated(hits$hits$hit_id),]
            } else {
              coldata = hits$hits
            }
          }

          if (!is.null(feature)) {
            coldata = data.frame(doc_id = private$.data$doc_id, code = private$.data[[feature]])
            coldata = coldata[!is.na(coldata$code),]
          }

          if (doc_count) coldata = coldata[!duplicated(coldata[,c('doc_id','code')]),]

          count_d = meta[list(coldata$doc_id), meta_cols, with=F]

          count_d$code = coldata$code
          agg_cols = c(meta_cols, 'code')

          count_d = count_d[, list(count=.N), by = agg_cols]
          d = merge(d, count_d, meta_cols)
          d$count[is.na(d$count)] = 0
          d = dcast(d, ... ~ code, value.var='count')
        }
        as.data.frame(d)
      },


## FEATURE MANAGEMENT ##
     preprocess = function(column, new_column=column, lowercase=T, ngrams=1, ngram_context=c('document', 'sentence'), as_ascii=F, remove_punctuation=T, remove_stopwords=F, use_stemming=F, language='english', clone=self$clone_on_change) {
       if (clone) {
         selfclone = self$copy_clone()$preprocess(column=column, new_column=new_column, lowercase=lowercase, ngrams=ngrams, ngram_context=ngram_context, as_ascii=as_ascii, remove_punctuation=remove_punctuation, remove_stopwords=remove_stopwords, use_stemming=use_stemming, language=language, clone=F)
         return(selfclone)
       }
       invisible(preprocess_feature(self, column=column, new_column=new_column, lowercase=lowercase, ngrams=ngrams, ngram_context=ngram_context, as_ascii=as_ascii, remove_punctuation=remove_punctuation, remove_stopwords=remove_stopwords, use_stemming=use_stemming, language=language))
     },

     feature_subset = function(column, new_column, subset, inverse=F, env=environment(), clone=self$clone_on_change){
       subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset

       if (clone) {
         selfclone = self$copy_clone()$feature_subset(column=column, new_column=new_column, subset=subset, inverse=inverse, env=env, clone=F)
         return(selfclone)
       }

       i =  self$subset_i(subset, inverse=!inverse, env=env) ## double inverse, because inverse in subset_i means "give me i for the rows for which condition is not true", and here we use i to set the NA.
       invisible(subset_feature_fun(self, i=i, column=column, new_column=new_column, subset=subset, inverse=inverse))
     },

     feature_stats = function(feature, context_level=c('document','sentence')){
       term.statistics(self, feature=feature, context_level=context_level)
     },

     top_features = function(feature, n=10, group_by=NULL, group_by_meta=NULL, return_long=F){
       top_features(self, feature=feature, n=n, group_by=group_by, group_by_meta=group_by_meta, return_long=return_long)
     },


## SEARCHING / QUERYING ##
     search_features = function(keyword=NA, condition=NA, code=NA, queries=NULL, feature='word', condition_once=F, subset_tokens=NA, subset_meta=NA, keep_false_condition=F, only_last_mword=F, verbose=F){
       subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
       subset_meta = if (is(substitute(subset_meta), 'call')) deparse(substitute(subset_meta)) else subset_meta
       search_features(self, keyword=keyword, condition=condition, code=code, queries=queries, feature=feature, condition_once=condition_once, subset_tokens=subset_tokens, subset_meta=subset_meta, keep_false_condition=keep_false_condition, only_last_mword=only_last_mword, verbose=verbose)
     },

     code_features = function(keyword=NA, condition=NA, code=NA, queries=NULL, feature='word', condition_once=F, subset_tokens=NA, subset_meta=NA, only_last_mword=F, verbose=F, clone=self$clone_on_change){
       subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
       subset_meta = if (is(substitute(subset_meta), 'call')) deparse(substitute(subset_meta)) else subset_meta

       if(clone){
         selfclone = self$copy_clone()$code_features(keyword=keyword, condition=condition, code=code, queries=queries, feature=feature, condition_once=condition_once, subset_tokens=subset_tokens, subset_meta=subset_meta, only_last_mword=only_last_mword, verbose=verbose, clone=F)
         return(selfclone)
       }
       hits = search_features(self, keyword=keyword, condition=condition, code=code, queries=queries, feature=feature, condition_once=condition_once, subset_tokens=subset_tokens, subset_meta=subset_meta, keep_false_condition=F, only_last_mword=only_last_mword, verbose=verbose)

       invisible(self)
     },

     search_recode = function(feature, new_value, keyword, condition=NA, condition_once=F, subset_tokens=NA, subset_meta=NA, clone=self$clone_on_change){
       subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
       subset_meta = if (is(substitute(subset_meta), 'call')) deparse(substitute(subset_meta)) else subset_meta
       if (clone) {
          selfclone = self$copy_clone()$search_recode(feature=feature, new_value=new_value, keyword=keyword, condition=condition, condition_once=condition_once, subset_tokens=subset_tokens, subset_meta=subset_meta, clone=F)
          return(selfclone)
       }

       hits = self$search_features(keyword=keyword, condition=condition, condition_once=condition_once, subset_tokens=subset_tokens, subset_meta=subset_meta)
       x = as.numeric(as.character(hits$hits$i)) ## for one of those inexplicable R reasons, I cannot directly use this numeric vector.... really no clue at all why
       self$set_column(feature, new_value, subset = x, clone = F)
       invisible(self)
     },

     search_contexts = function(query, code=NULL, feature='word', context_level=c('document','sentence'), verbose=F){
       search_contexts(self, query, code=code, feature=feature, context_level=context_level, verbose=verbose)
     },

     subset_query = function(query, feature='word', context_level=c('document','sentence'), clone=self$clone_on_change){
       if (clone) {
         selfclone = self$copy_clone()$subset_query(query=query, feature=feature, context_level=context_level, clone=F)
         return(selfclone)
       }
       context_level = match.arg(context_level)
       hits = self$search_contexts(query, feature=feature, context_level=context_level)
       hits = hits$hits
       if (is.null(hits)) return(NULL)
       if (context_level == 'document'){
         private$select_meta_rows(self$meta$doc_id %in% hits$doc_id)
       }
       if (context_level == 'sentence'){
         d = self$data[,c('doc_id','sent_i')]
         d$i = 1:nrow(d)
         rows = d[list(hits$doc_id, hits$sent_i)]$i
         private$select_rows(rows)
       }
       invisible(self)
     },

     kwic = function(hits=NULL, i=NULL, keyword=NULL, code='', nwords=10, nsample=NA, output_feature='word', context_level=c('document','sentence'), prettypaste=T, kw_tag=c('<','>'), ...){
       if (!is.null(keyword)) hits = self$search_features(keyword=keyword, code=code, ...)
       keyword_in_context(self, hits=hits, i=i, code=code, nwords=nwords, nsample=nsample, output_feature=output_feature, context_level=context_level, prettypaste=prettypaste, kw_tag=kw_tag)
     },

## CO-OCCURRENCE NETWORKS ##
     semnet = function(feature, measure=c('con_prob', 'con_prob_weighted', 'cosine', 'count_directed', 'count_undirected', 'chi2'), context_level=c('document','sentence'), backbone=F, n.batches=NA){
       semnet(self, feature=feature, measure=measure, context_level=context_level, backbone=backbone, n.batches=n.batches)
     },

     semnet_window = function(feature, measure=c('con_prob', 'cosine', 'count_directed', 'count_undirected', 'chi2'), context_level=c('document','sentence'), window.size=10, direction='<>', backbone=F, n.batches=5, set_matrix_mode=c(NA, 'windowXwindow','positionXwindow')){
       semnet_window(self, feature=feature, measure=measure, context_level=context_level, window.size=window.size, direction=direction, backbone=backbone, n.batches=n.batches, set_matrix_mode=set_matrix_mode)
     },

## CORPUS COMPARISON ##

     compare_corpus = function(tc_y, feature, smooth=0.1, min_over=NULL, min_chi2=NULL, is_subset=F, yates_cor=c('auto','yes','no')){
       if (is_subset & self$n > tc_y$n) stop('tCorpus x (the one calling the method) cannot be a subset of tCorpus y, because it has more tokens')
       tcorpus_compare(self, tc_y, feature, smooth=smooth, min_over=min_over, min_chi2=min_chi2, yates_cor=yates_cor, x_is_subset=is_subset)
     },

     compare_subset = function(feature, subset_x=NULL, subset_meta_x=NULL, query_x=NULL, query_feature='word', smooth=0.1, min_over=NULL, min_chi2=NULL, yates_cor=c('auto','yes','no')){
       subset_x = if (is(substitute(subset_x), 'call')) deparse(substitute(subset_x)) else subset_x
       subset_meta_x = if (is(substitute(subset_meta_x), 'call')) deparse(substitute(subset_meta_x)) else subset_meta_x

       if(is.null(subset_x) & is.null(subset_meta_x) & is.null(query_x)) stop("at least one of subset_x, subset_meta_x or query_x has to be specified")
       #tc_x = self$copy_clone()
       if(!is.null(subset_x) | !is.null(subset_meta_x)) tc_x = self$subset(subset=subset_x, subset_meta=subset_meta_x, clone=T)
       if(!is.null(query_x)) tc_x = self$subset_query(query_x, feature=query_feature, clone=T)

       comp = tc_x$compare_corpus(self, feature=feature, smooth=smooth, min_over=min_over, min_chi2=min_chi2, yates_cor=yates_cor, is_subset=T)
       if (self$auto_gc) rm(tc_x); gc()
       comp
     },

## DOCUMENT COMPARISON ##

     compare_documents = function(feature='word', date_col=NULL, hour_window=NULL, measure=c('cosine','overlap_pct'), min_similarity=0, weight=c('norm_tfidf', 'tfidf', 'termfreq','docfreq'), ngrams=NA, from_subset=NULL, to_subset=NULL) {
        weight = match.arg(weight)

        from_subset = if (is(substitute(from_subset), 'call')) deparse(substitute(from_subset)) else from_subset
        to_subset = if (is(substitute(to_subset), 'call')) deparse(substitute(to_subset)) else to_subset

        compare_documents_fun(self, feature=feature, date_col=date_col, hour_window=hour_window, measure=measure, min_similarity=min_similarity, weight=weight, ngrams=ngrams, from_subset=from_subset, to_subset=to_subset)
     },

     deduplicate = function(feature='word', date_col=NULL, meta_cols=NULL, hour_window=NULL, min_docfreq=2, max_docfreq_pct=0.5, measure=c('cosine','overlap_pct'), similarity=1, keep=c('first','last', 'random'), weight=c('norm_tfidf', 'tfidf', 'termfreq','docfreq'), ngrams=NA, print_duplicates=F, env=environment(), clone=self$clone_on_change){
       weight = match.arg(weight)
       match.arg(feature, self$feature_names)
       if (clone) {
         selfclone = self$copy_clone()$deduplicate(feature=feature, date_col=date_col, meta_cols=meta_cols, hour_window=hour_window, min_docfreq=min_docfreq, max_docfreq_pct=max_docfreq_pct, measure=measure, similarity=similarity, keep=keep, weight=weight, ngrams=ngrams, print_duplicates=print_duplicates, env=env, clone=F)
         return(selfclone)
       }

       self$set_column('DEDUPLICATE_FEATURE', self$data[[feature]], clone = F)
       self$feature_subset('DEDUPLICATE_FEATURE', 'DEDUPLICATE_FEATURE', subset = docfreq_filter('DEDUPLICATE_FEATURE', min=min_docfreq, max=self$n * max_docfreq_pct), env=env, clone=F)
       ## delete duplicates modifies tc by reference
       delete_duplicates(self, feature=feature, date_col=date_col, meta_cols=meta_cols, hour_window=hour_window, measure=measure, similarity=similarity, keep=keep, weight=weight, print_duplicates=print_duplicates)

       self$set_column('DEDUPLICATE_FEATURE', NULL, clone=F)
       invisible(self)
     },

## TOPIC MODELING ##

      lda_fit = function(feature, create_feature=NULL, K=50, num.iterations=500, alpha=50/K, eta=.01, burnin=250, context_level=c('document','sentence'), ...) {
        dtm = self$dtm(feature=feature, context_level=context_level, ...)
        m = lda_fit(dtm=dtm, method='Gibbs', K=K, num.iterations=num.iterations, alpha=alpha, eta=eta, burnin=burnin)
        if (!is.null(create_feature)) self$lda_topic_features(m=m, feature=feature, new_feature=create_feature, context_level=context_level, clone=F)
        m
      },

      lda_topic_features = function(m, feature, new_feature='LDA_topic', context_level=c('document','sentence'), clone=self$clone_on_change){
        if (clone) {
          selfclone = self$copy_clone()$lda_topic_features(m=m, feature=feature, new_feature=new_feature, context_level=context_level, clone=F)
          return(selfclone)
        }
        d = lda_features(tc=self, m=m, feature=feature, new_feature=new_feature, context_level=context_level)
        self$set_column(new_feature, d$v[order(d$i)], clone=F)
        invisible(self)
      },

## RESOURCES ##

     jrc_names = function(new_feature='jrc_names', feature='word', resource_path=getOption('tcorpus_resources', NULL), collocation_labels=T, batchsize=50000, low_memory=T, verbose=T, clone=self$clone_on_change){
       if (clone) {
         selfclone = self$copy_clone()$jrc_names(new_feature=new_feature, feature=feature, resource_path=resource_path, collocation_labels=collocation_labels, batchsize=batchsize, low_memory=low_memory, verbose=verbose, clone=F)
         return(selfclone)
       }
       jrc_names(self, new_feature=new_feature, feature=feature, resource_path=resource_path, collocation_labels=collocation_labels, batchsize=batchsize, low_memory=low_memory, verbose=verbose)
     },

     ## util
     set_keys = function(){
       ## ignore clone T or F, since setting keys is always a good thing
       if ('sent_i' %in% colnames(private$.data)){
         setkey(private$.data, 'doc_id', 'sent_i', 'word_i')
       } else {
         setkey(private$.data, 'doc_id', 'word_i')
       }
       setkey(private$.meta, 'doc_id')
       if (!is.null(private$.feature_index)) setkey(private$.feature_index, 'feature')
     },

     droplevels = function(clone=self$clone_on_change){
       if (clone) {
         selfclone = self$copy_clone()$droplevels(clone=F)
         return(selfclone)
       }
       private$.data = base::droplevels(private$.data)
       private$.meta = base::droplevels(private$.meta)
       invisible(self)
     }

   ),

   active = list(
     n = function() nrow(private$.data),
     n_meta = function() nrow(private$.meta),
     feature_names = function(e=NULL) {
       if (!is.null(e)) stop('Cannot change tcorpus$featurenames by assignment. Instead, use the set_colname() function')
       fnames = colnames(private$.data)[!colnames(private$.data) %in% c('doc_id','sent_i','word_i')]
     },
     names = function(e=NULL) {
       if (!is.null(e)) stop('Cannot change tcorpus$datanames by assignment. Instead, use the set_colname() function')
       colnames(private$.data)
     },
     meta_names = function(e=NULL) {
       if (!is.null(e)) stop('Cannot change tcorpus$metanames by assignment. Instead, use the set_meta_colname() function')
       colnames(private$.meta)
     },

     doc_id_labels = function(mod=NULL) {
       if (!is.null(mod)){
         if (identical(levels(self$data$doc_id), levels(self$meta$doc_id))){
           levels(private$.data$doc_id) = mod
           levels(private$.meta$doc_id) = mod
         } else { ## should never happen, but to be sure
           levels(private$.meta$doc_id) = mod[match(levels(private$.meta$doc_id), levels(private$.data$doc_id))]
           levels(private$.data$doc_id) = mod
         }
       }
       levels(self$data$doc_id)
     },

     data = function(mod=NULL) {
       ## access data directly, but with checks to protect structure.
       positioncols = intersect(c('doc_id','sent_i','word_i'), self$names)

       if (!is.null(mod)) {
         if ('sent_i' %in% colnames(mod)) setkeyv(mod, c('doc_id','sent_i','word_i')) else setkeyv(mod, c('doc_id','word_i'))

         if (nrow(mod) < self$n) stop('Replacement cannot have fewer rows. For subsetting, please use the $subset method')
         if (nrow(mod) > self$n) stop('Replacement cannot have more rows. For adding more data, please use the merge_tcorpora function or the $add_data method')
         if (!identical(private$.data[,positioncols,with=F], mod[,positioncols,with=F])) {
           if (!identical(private$.data$doc_id, mod$doc_id)) {
             stop('Cannot change doc_id. If you want to change doc_id labels, you can overwrite $doc_id_labels.')
           }
           if (nrow(unique(mod[,c('doc_id','word_i')])) < nrow(mod)) stop('After transformation, word_i is not unique within documents')
           self$reset_feature_index()
         }

         indexcol = self$provenance()$index_feature
         if (!is.null(indexcol)){
           if (!identical(private$.data[[indexcol]], mod[[indexcol]])) {
             self$reset_feature_index()
           }
         }
         private$.data = mod
         self$set_keys()
       }
       data.table::copy(private$.data)
     },

     meta = function(mod=NULL) {
       ## access data directly, but with checks to protect structure.
       if (!is.null(mod)) {
         setkey(mod, 'doc_id')

         if (nrow(mod) < self$n_meta) stop('Replacement cannot have fewer rows. For subsetting, please use the $subset method')
         if (nrow(mod) > self$n_meta) stop('Replacement cannot have more rows. For adding more data, please use the merge_tcorpora function or the $add_data method')
         if (!identical(private$.meta$doc_id, mod$doc_id)) {
           stop('Cannot change doc_id. If you want to change doc_id labels, you can overwrite $doc_id_labels.')
         }
         private$.meta = mod
         self$set_keys()
       }
       data.table::copy(private$.meta)
     }

   )
)

#' @export
print.tCorpus <- function(tc) {
  sent_info = if ('sent_i' %in% tc$names) paste(' and sentences (n = ', nrow(unique(tc$data[,c('doc_id','sent_i')])), ')', sep='') else ''
  cat('tCorpus containing ', tc$n, ' tokens',
      '\nsplit by documents (n = ', tc$n_meta, ')', sent_info,
      '\ncontains:',
      '\n  - ', length(tc$names), ' data column', if (length(tc$names) > 1) '(s)', ':\t', paste(tc$names, collapse=', '),
      '\n  - ', length(tc$meta_names), ' meta column', if (length(tc$meta_names) > 1) '(s)', ': \t', paste(tc$meta_names, collapse=', '),
      '\n', sep='')
}

#' Refresh a tCorpus object using the current version of corpustools
#'
#' As an R6 class, tCorpus contains its methods within the class object (i.e. itself). Therefore, if you use a new version of corpustools with an older tCorpus object (e.g., stored as a .rds. file), then the methods are not automatically updated. You can then use refresh_tcorpus() to reinitialize the tCorpus object with the current version of corpustools.
#'
#' @param tc a tCorpus object
#'
#' @return a tCorpus object
#' @export
refresh_tcorpus <- function(tc){
  tCorpus$new(data=tc$.__enclos_env__$private$.data,
              meta=tc$.__enclos_env__$private$.meta,
              p = tc$.__enclos_env__$private$.p,
              feature_index = tc$.__enclos_env__$private$.feature_index)
}

rebuild_tcorpus <- function(tc) {
  tokens_to_tcorpus(tokens = tc$data,
                    doc_col = 'doc_id',
                    sent_i_col = ifelse('sent_i' %in% tc$names, T, F),
                    word_i_col = 'word_i',
                    meta = tc$meta)
}

#' @export
summary.tCorpus <- function(tc) {
  tc
}

#' @export
summary.tCorpus <- function(tc) tc

#' @export
as.tcorpus <- function(x) UseMethod('as.tcorpus')

#' @export
as.tcorpus.tCorpus <- function(x) x

#' @export
as.tcorpus.default <- function(x) stop('x has to be a tCorpus object')
## params: preprocess_params=list, filter_params,

is_tcorpus <- function(x, allow_stc=F){
  if (!class(x)[1] %in% c('tCorpus', 'shattered_tCorpus')) stop('not a tCorpus object')
  if (is_shattered(x) & !allow_stc) stop('function not implemented for shattered_tCorpus')
  TRUE
}

is_shattered <- function(x) is(x, 'shattered_tCorpus')

###  utility

safe_selection <- function(d, selection){
  if (any(is.na(selection))) stop('selection cannot contain NA')
  if (!is(selection, 'numeric') & !is(selection,'logical')) stop('selection has to be either a logical vector or a numerical vector (indices for TRUE values)')
  if (is(selection, 'numeric')) selection = 1:nrow(d) %in% selection
  selection
}

eval_subset <- function(d, subset){
  subset = if (is(substitute(subset), 'call')) deparse(substitute(subset)) else subset
  subset = if (is(substitute(subset), 'character')) parse(text=subset) else substitute(subset)
  eval(subset, d, parent.frame(2))
}

elip_names <- function(...) names(as.list(match.call()))[-1]

expr_names <- function(expr){
  if (!is(expr, 'character')) expr = deparse(substitute(expr))
  expr = expr[!expr %in% c('{','}')]
  expr = stringi::stri_trim(gsub('[<=[].*', '', expr))
  if (grepl('(', expr, fixed = T)) expr = gsub('.*\\((.*)[,\\)].*', '\\1', expr)
  expr
}

get_context <- function(tc, context_level = c('document','sentence'), with_labels=T){
  context_level = match.arg(context_level)

  if (context_level == 'document') {
    context = tc$data$doc_id
    if (!with_labels) levels(context) = 1:length(levels(context))
  }
  if (context_level == 'sentence') {
    if (!'sent_i' %in% tc$names) stop('Sentence level not possible, since no sentence information is available. To enable sentence level analysis, use split_sentences = T in "create_tcorpus()" or specify sent_i_col in "tokens_to_tcorpus()"')
    d = tc$data
    if (with_labels){
      ucontext = unique(d[,c('doc_id','sent_i')])
      ucontext = stringi::stri_paste(ucontext$doc_id, ucontext$sent_i, sep=' #')
      context = fast_factor(global_position(d$sent_i, d$doc_id, presorted = T, position_is_local=T), levels = ucontext)
    } else {
      context = fast_dummy_factor(global_position(d$sent_i, d$doc_id, presorted = T, position_is_local=T))
    }
  }
  context
}

function(){
tokens = data.frame(document = c(rep(1, 8), rep(2, 5), rep(3, 5)),
                    sentence = c(rep(1,4), rep(2,4), rep(1,5), rep(1,5)),
                    id = 1:18,
                    word = c('Renewable','fuel','is','better','than','fossil','fuels','!','A','fueled','debate','about','fuel','Mark','Rutte','is','simply','Rutte'))
tc = tokens_to_tcorpus(tokens, doc_col ='document', sent_i_col = 'sentence', word_i_col = 'id')
tc$data
}
