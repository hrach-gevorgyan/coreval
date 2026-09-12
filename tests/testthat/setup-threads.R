# CRAN asks that a package use no more than two cores, and runs checks on
# shared machines. data.table defaults to half the machine's cores, which is
# reasonable for a user but rude on a build farm - and on a many-core runner
# contention can make the check slower rather than faster.
#
# The previous value travels through an option rather than a local variable:
# teardown code runs in its own environment and cannot see locals from a
# setup file, so restoring from a local silently did nothing.
options(coreval.test.old_dtthreads = data.table::getDTthreads())
data.table::setDTthreads(2L)
