module mecca.platform.os.darwin;

version (Darwin):
package(mecca):

public import mecca.platform.os.darwin.ucontext;
public import mecca.platform.os.darwin.time;

import core.sys.posix.sys.types : pthread_t;

import mecca.platform.os : MmapArguments;

// These two do not exist on Darwin platforms. We'll just use a value that won't
// have any affect when used together with mmap and mremap.
enum MAP_POPULATE = 0;
enum MREMAP_MAYMOVE = 0;

///
enum OSSignal
{
    SIGNONE = 0, /// invalid
    SIGHUP = 1, /// hangup
    SIGINT = 2, /// interrupt
    SIGQUIT = 3, /// quit
    SIGILL = 4, /// illegal instruction (not reset when caught)
    SIGTRAP = 5, /// trace trap (not reset when caught)
    SIGABRT = 6, /// abort()
    SIGIOT = SIGABRT, /// compatibility
    SIGEMT = 7, /// EMT instruction
    SIGFPE = 8, /// floating point exception
    SIGKILL = 9, /// kill (cannot be caught or ignored)
    SIGBUS = 10, /// bus error
    SIGSEGV = 11, /// segmentation violation
    SIGSYS = 12, /// bad argument to system call
    SIGPIPE = 13, /// write on a pipe with no one to read it
    SIGALRM = 14, /// alarm clock
    SIGTERM = 15, /// software termination signal from kill
    SIGURG = 16, /// urgent condition on IO channel
    SIGSTOP = 17, /// sendable stop signal not from tty
    SIGTSTP = 18, /// stop signal from tty
    SIGCONT = 19, /// continue a stopped process
    SIGCHLD = 20, /// to parent on child stop or exit
    SIGTTIN = 21, /// to readers pgrp upon background tty read
    SIGTTOU = 22, /// like TTIN for output if (tp->t_local&LTOSTOP)
    SIGIO = 23, /// input/output possible signal
    SIGXCPU = 24, /// exceeded CPU time limit
    SIGXFSZ = 25, /// exceeded file size limit
    SIGVTALRM = 26, /// virtual time alarm
    SIGPROF = 27, /// profiling time alarm
    SIGWINCH = 28, /// window size changes
    SIGINFO = 29, /// information request
    SIGUSR1 = 30, /// user defined signal 1
    SIGUSR2 = 31 /// user defined signal 2
}

/**
 * Represents the ID of a thread.
 *
 * This type is platform dependent.
 */
alias ThreadId = ulong;

__gshared static immutable BLOCKED_SIGNALS = [
    OSSignal.SIGHUP, OSSignal.SIGINT, OSSignal.SIGQUIT,
    //OSSignal.SIGILL, OSSignal.SIGTRAP, OSSignal.SIGABRT,
    //OSSignal.SIGBUS, OSSignal.SIGFPE, OSSignal.SIGKILL,
    //OSSignal.SIGUSR1, OSSignal.SIGSEGV, OSSignal.SIGUSR2,
    OSSignal.SIGPIPE, OSSignal.SIGALRM, OSSignal.SIGTERM,
    //OSSignal.SIGSTKFLT, OSSignal.SIGCONT, OSSignal.SIGSTOP,
    OSSignal.SIGCHLD, OSSignal.SIGTSTP, OSSignal.SIGTTIN,
    OSSignal.SIGTTOU, OSSignal.SIGURG, OSSignal.SIGXCPU,
    OSSignal.SIGXFSZ, OSSignal.SIGVTALRM, OSSignal.SIGPROF,
    OSSignal.SIGWINCH, OSSignal.SIGIO,
    //OSSignal.SIGSYS,
];

extern (C) private int pthread_threadid_np(pthread_t, ulong*) nothrow;

/// Returns: the current thread ID
ThreadId currentThreadId() @system nothrow
{
    import mecca.lib.exception : ASSERT;

    enum assertMessage = "pthread_threadid_np failed, should not happen";

    ulong threadId;
    ASSERT!"assertMessage"(pthread_threadid_np(null, &threadId) == 0);

    return threadId;
}

enum O_CLOEXEC = 0x1000000;
enum F_DUPFD_CLOEXEC = 67;

// this does not exist on Darwin
enum EREMOTEIO = -1;

// `pipe2` does not exist on Darwin so we're emulating it instead. This is
// emulated by first calling the regular `pipe` followed by `fcntl` on the two
// file descriptors. This is not thread safe.
extern(C) private int pipe2(ref int[2] pipefd, int flags) nothrow @trusted @nogc
{
    import core.sys.posix.unistd : close, pipe;

    static int setFlags(int fd, int flags)
    {
        import core.sys.posix.fcntl : fcntl, F_SETFD, F_GETFD;

        const existingFlags = fcntl(fd, F_GETFD);

        if (existingFlags == -1)
            return existingFlags;

        return fcntl(fd, F_SETFD, existingFlags | flags);
    }

    static void closePipe(ref int[2] pipe)
    {
        foreach (fd; pipe)
            close(fd);
    }

    const pipeResult = pipe(pipefd);

    if (pipeResult != 0)
        return pipeResult;

    foreach (fd; pipefd)
    {
        if (setFlags(fd, flags) == -1)
        {
            closePipe(pipefd);
            return -1;
        }
    }

    return 0;
}

enum ITIMER_REAL = 0;

void* mremap(MmapArguments mmapArguments, void* oldAddress, size_t oldSize,
    size_t newSize, int flags, void* newAddress = null)
{
    import core.stdc.string : memcpy;
    import core.sys.posix.sys.mman : mmap, munmap, MAP_FAILED;

    if (oldSize == newSize)
        return oldAddress;

    if (newSize < oldSize)
    {
        const sizeToUnmap = oldSize - newSize;
        if (munmap(oldAddress + sizeToUnmap, sizeToUnmap) != 0)
            return MAP_FAILED;

        return oldAddress;
    }

    auto newMemory = mmap(newAddress, newSize, mmapArguments.tupleof);

    if (newMemory == MAP_FAILED)
        return MAP_FAILED;

    memcpy(newMemory, oldAddress, oldSize);

    if (munmap(oldAddress, oldSize) != 0)
    {
        if (munmap(newMemory, newSize) != 0)
            assert(false);

        return MAP_FAILED;
    }

    return newMemory;
}
