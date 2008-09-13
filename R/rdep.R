
r_bundle_of <- function(pkgname) {
    # returns the bundle containing pkgname or NA
    bundles <- names(available[!is.na(available[, 'Bundle']), 'Contains'])
    # use the first bundle
    for (bundle in bundles) {
        if (pkgname %in% r_bundle_contains(bundle)) {
            return(bundle)
        }
    }
    return(NULL)
}

r_bundle_contains <- function(bundlename) {
    return(strsplit(available[bundlename,'Contains'],'[[:space:]]+')[[1]])
}

r_requiring <- function(names) {
    for (name in names) {
        if (!(name %in% base_pkgs) && !(name %in% rownames(available))) {
            bundle <- r_bundle_of(name)
            if (!is.null(bundle)) {
                name = bundle
                names <- c(names,bundle)
            }
        }
        if (name %in% rownames(available) && !is.na(available[name,'Contains'])) {
            names <- c(names,r_bundle_contains(name))
        }
    }
    # approximately prune first into a smaller availability
    candidates <- rownames(available)[sapply(rownames(available)
                                            ,function(name)
                                                length(grep(paste(names,collapse='|')
                                                           ,available[name,r_depend_fields])) > 0)]
    if (length(candidates) == 0) {
        return(c())
    }
    # find a logical index into available of every package/bundle
    # whose dependency field contains at least one element of names.
    # (this is not particularly easy to read---sorry---but is much faster than
    # the alternatives i could think of)
    prereq=c()
    dep_matches <- function(dep) chomp(gsub('\\([^\\)]+\\)','',dep)) %in% names
    any_dep_matches <- function(name,field=NA)
                any(sapply(strsplit(chomp(available[name,field])
                                   ,'[[:space:]]*,[[:space:]]*')
                          ,dep_matches))

    for (field in r_depend_fields) {
        matches = sapply(candidates, any_dep_matches, field=field)
        if (length(matches) > 0) {
            prereq = c(prereq,candidates[matches])
        }
    }
    return(unique(prereq))
}

r_dependencies_of <- function(name=NULL,description=NULL) {
    # find the immediate dependencies (children in the dependency graph) of an
    # R package
    if (!is.null(name) && (name == 'R' || name %in% base_pkgs)) {
        return(data.frame())
    }
    if (is.null(description) && is.null(name)) {
        fail('must specify either a description or a name.')
    }
    if (is.null(description)) {
        if (!(name %in% rownames(available))) {
            bundle <- r_bundle_of(name)
            if (!is.null(bundle)) {
                name <- bundle
            } else {
                # unavailable packages don't depend upon anything
                return(data.frame())
            }
        }
        description <- data.frame()
        # keep only the interesting fields
        for (field in r_depend_fields) {
            if (!(field %in% names(available[name,]))) {
                next
            }
            description[1,field] = available[name,field]
        }
    }
    # extract the dependencies from the description
    deps <- data.frame()
    for (field in r_depend_fields) {
        if (!(field %in% names(description[1,]))) {
            next
        }
        new_deps <- lapply(strsplit(chomp(description[1,field])
                                   ,'[[:space:]]*,[[:space:]]*')[[1]]
                          ,r_parse_dep_field)
        deps <- iterate(lapply(new_deps[!is.na(new_deps)],rbind),deps,rbind)
    }
    return (deps)
}

r_parse_dep_field <- function(dep) {
    if (is.na(dep)) {
        return(NA)
    }
    # remove other comments
    dep = gsub('(\\(\\)|\\([[:space:]]*[^<=>!].*\\))','',dep)
    # squish spaces
    dep = chomp(gsub('[[:space:]]+',' ',dep))
    # parse version
    pat = '^([^ ()]+) ?(\\( ?([<=>!]+ ?[0-9.-]+) ?\\))?$'
    if (!length(grep(pat,dep))) {
        fail('R dependency',dep,'does not appear to be well-formed')
    }
    version = sub(pat,'\\3',dep)
    dep = sub(pat,'\\1',dep)
    if (!(dep %in% rownames(available))) {
        depb <- r_bundle_of(dep)
        if (!is.null(depb)) {
            dep <- depb
        }
    }
    return(list(name=dep,version=version))
}

r_dependency_closure <- function(fringe, forward_arcs=T) {
    # find the transitive closure of the dependencies/prerequisites of some R
    # packages
    closure <- list()
    if (is.data.frame(fringe)) {
        fringe <- as.list(fringe$name)
    }
    fun = function(x) r_dependencies_of(name=x)$name
    if (!forward_arcs) {
        fun = r_requiring
    }
    while(length(fringe) > 0) {
        # pop off the top
        top <- fringe[[1]]
        if (length(fringe) > 1) {
            fringe <- fringe[2:length(fringe)]
        } else {
            fringe <- list()
        }
        src <- pkgname_as_debian(top,binary=F)
        if (src == 'R') {
            next
        }
        newdeps <- fun(top)
        closure=c(closure,top)
        fringe=c(fringe,newdeps)
    }
    # build order
    return(rev(unique(closure,fromLast=T)))
}

