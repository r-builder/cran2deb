log_messages <- list()

log_clear <- function() {
    assign('log_messages',list(),envir=.GlobalEnv)
}

log_add <- function(text,print=T) {
    if (print) {
        message(text)
    }
    assign('log_messages',c(log_messages, text),envir=.GlobalEnv)
}

log_retrieve <- function() {
    return(log_messages)
}

notice <- function(...) {
    log_add(paste('N:',...))
}

warn <- function(...) {
    log_add(paste('W:',...))
}

error <- function(...) {
    log_add(paste('E:',...))
}

fail <- function(...) {
    txt <- paste('E:',...)
    log_add(txt)
    stop(txt)
}

log_system <- function(...) {
    r <- try((function() {
        # pipe() does not appear useful here, since
        # we want the return value!
        # XXX: doesn't work with ; or | !
        tmp <- tempfile('log_system')
        on.exit(unlink(tmp))
        cmd <- paste(...)
        # unfortunately this destroys ret
        #cmd <- paste(cmd,'2>&1','| tee',tmp)
        cmd <- paste(cmd,'>',tmp,'2>&1')
        ret <- system(cmd)
        f <- file(tmp)
        output <- readLines(f)
        close(f)
        unlink(tmp)
        return(list(ret,output))
    })())
    if (inherits(r,'try-error')) {
        fail('system failed on:',paste(...))
    }
    for (line in r[[2]]) {
        if (!length(grep('^[WENI]:',line))) {
            line = paste('I:',line)
        }
        log_add(line) #,print=F)
    }
    return(r[[1]])
}

