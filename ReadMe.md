# WingetPathUpdater

**TL;DR:** this package makes the last step of this sequence work as one would hope:

```pwsh
winget install jazzdelightsme.WingetPathUpdater # N.B. requires elevation!
winget install git.git
git -? # <-- read on if you don't understand why this WOULDN'T work...
```

## Background

On Windows, there is an environment variable called "`PATH`" (sometimes referred to as "`%PATH%`" or "`$env:PATH`", in cmd or pwsh syntax), which is a list of directories where commands can be found. Many programs, when installed, copy their files somewhere on your disk (like "C:\Program Files\MyCompany\NewProgram.exe"), then update the `PATH` environment variable, adding a directory at the end, where the new program can be found, so that you can run `NewProgram.exe` from a command window without having to specify the complete path to it.

## The problem

Canonical environment variables are stored in the registry, and each process inherits a process-local environment variable block from its parent process (it either gets a straight-up copy of the parent's block, or the parent can manually specify a custom environment block, if it likes). When an environment variable (such as `PATH`) is changed, most processes typically do NOT refresh their in-memory, process-local copy. ("Why not?" is a longer discussion, but consider: how would you reconcile process-local changes made by your parent process, versus the canonical ones in the registry?)

Practically speaking, what this means is that when you run the installer for `NewProgram.exe`, any previously-existing cmd/pwsh shell processes already have their environment variables set, and when the installer updates the `PATH` environment variable in the registry, your existing shells are none the wiser--if you type "NewProgram.exe" into them, you'll get a "command not found" error. You have to start a fresh, *new* shell process (which will inherit environment variables from the Windows GUI shell (explorer), which *does* update its environment variables when system changes are made), and only in that *new* cmd/pwsh window can you run "NewProgram.exe".

**And the problem is:** that's pretty annoying.

**Secondarily:** it's *more* than just annoying for humans; it really complicates life for scripts, too. If it's a script that is running the installer, then suppose the script wants to actually use the new program that it just installed, what is it supposed to do? (it probably has to engage in dorky workarounds, like hardcoding where the expected install path is, and manually updating the process-local path, or use full paths, or something like that).

**Thirdly:** that's not usually how it works on other systems (people coming from other systems expect to be able to run "`SomePackageManager install MyCompany.NewProgram`", and then immediately, in the same command window, run "`NewProgram`"). People coming from other systems legit think "oh, this package is buggy, because I ran `winget install thing`, and then `thing`, but `thing` wasn't found." (And actually, this probably applies to relatively younger Windows users, who are not familiar with the traditional pains associated with the `PATH` environment variable.)

And, unfortunately, our favorite Windows package manager, `winget` is also subject to this problem. There is a veritable *river* of tears in: https://github.com/microsoft/winget-cli/issues/549

(Clarification: there are actually **two** `PATH`-related problems there: one is that your console's environment variables are not updated after running `winget`, which is the problem addressed by this project (WingetPathUpdater). The *other* problem is that some packages (`vim.vim`, for example, as of this writing) do not update `PATH` **at all!** (So even when you open a new console window, or even reboot, running `vim` doesn't work.) In my opinion, a package author should fix that (the installer should update `PATH`); but some people think it would be nice if `winget` manifests could also have some sort of facility to update `PATH` on behalf on an installer.)

## The solution

Ideally, this problem would be handled by the package manager itself, right?

But it turns out that's not as easy as you might think. (Short story: the `winget.exe` process can't just reach up into the parent process and run code in it to update it's environment variables.)

So what to do?

### Design constraints

I wrote up a complete list of the key design constraints here: https://github.com/microsoft/winget-cli/issues/549#issuecomment-1555948307

If you really want to get into the nitty gritty details, you can go read that post; I'll just summarize here:

The crux of the problem is that environment variables need to be updated in the user’s shell, which is going to be a different process than the `winget.exe` process. This leads to the main constraint for any possible solution:

**Requirement 1:** somehow, someway, there will need to be code that runs in the shell process (`cmd.exe` or `pwsh.exe`).

There is a secondary problem: how could we update the environment, in as safe and non-breaking a way as possible? The critical thing is to not mess up any in-memory customizations, so ideally we just tack on the bare minimum of “what actually changed” onto the very end. (It’s possible that an installer does something super fancy, and purposefully updates `PATH` to stick something new in the middle, before some other paths; but I think that’s a rare case.)

This is what gives rise to:

**Requirement 2:** There has to be a “diff”: we need to know what actually changed, so we can add *just that* to the end of the current, in-memory value.

### Implementation

Now back to requirement 1: we have to have code that runs in the shell process. How can we do that?

Use a shell-specific mechanism.

 - For cmd: a `.cmd`/`.bat` script.
 - For PowerShell: a `.ps1` script.
 - Bash: a `.sh` script.
 - Etc.
 - Because `winget` is Windows-specific, just handling cmd and PS is good enough; who in the world is running `winget` commands from bash, amiright? :D

Okay, so we’re going to have a script.

This brings us to the last piece of the puzzle: how is the [shell-specific] script going to get executed in the proper shell process? `Winget.exe` can’t do it directly...

Easy: just have the user do it! :D

We train people to just run “`winget <arguments>`”... but that does not have to directly be winget.EXE. If we have `winget.ps1` and `winget.cmd`, which come before `winget.exe` on the `PATH`, then when you are in `cmd.exe`, and you run “`winget`”, you will run winget.CMD; when in `pwsh.exe`, you will get winget.PS1.

And here’s what the script will do:

1. [If we are doing an "install",] read the current `PATH`* values out of the registry (the “before” snapshot). This is possibly very different from what’s in memory, but that’s okay; this is just a reference point to find out what the installer has actually changed.
2. Run `winget.exe`, passing through all arguments (`%*`/`$args`).
3. Read the current `PATH` values out of the registry (the “after” snapshot), compare to “before” to see what the installer changed, and tack the additions onto the end of the in-memory environment values.

Et voilà!

(This is actually a pretty standard trick; to wrap things in a script wrapper for various reasons.)

`*`: Note: the wrapper scripts actually update *all* environment variables, not just `PATH`. This is because sometimes people add "unexpanded" environment variable names to the `PATH` (so your `PATH` might be something like `C:\windows\system32;%VIMRUNTIME%`: we need to pick up the new `VIMRUNTIME` variable, too). Note that only **additions** are handled; if an installer deletes variables or reorders paths, the wrapper scripts ignore that.

## This package

That's where this package comes in: it installs `winget.ps1` and `winget.cmd` scripts into the `C:\Windows\System32` directory (which ought to come before `winget.exe`'s directory on the `PATH`). So when people run "`winget install foo`", they will actually be running the wrapper script instead of `winget.exe`, the wrapper script will update the in-memory `PATH`, and everything magically works.

## Disadvantages

This package is not a perfect solution. Downsides:

 * The biggest problem is that **it is not included as part of `winget`**. You have to know that you need it, and install it first.
 * **It requires elevation.** If you do not have administrative access, you won't be able to install this package.

## How to install

Just as you would expect:

```pwsh
winget install jazzdelightsme.WingetPathUpdater # N.B. requires elevation!
```

Note that you cannot make your package depend on the WingetPathUpdater package, to automagically make your package findable on the `PATH` without any extra steps. That's because if a single `winget.exe` invocation installs WingetPathUpdater and your package, the wrapper scripts do not come into play at all. The WingetPathUpdater package *must* be installed separately; only when the `winget.exe` process that has done that returns will the wrapper scripts be able to "take effect" for subsequent invocations of "`winget`".

## Bonus Reading

From Raymond Chen, "The Old New Thing": ["What happens if I define one environment variable in terms of the value of another environment variable?"](https://devblogs.microsoft.com/oldnewthing/20231212-00/?p=109137).

TechNet/MSDN/Microsoft blog platform du jour is ***notorious*** for moving stuff (or just deleting it) and breaking links, so let me summarize here: creating an in-memory "environment block" from the values stored in the registry happens in several steps, and the order has implications if you are trying to define one environment variable in terms of another. Raymond's "simplified for purposes of exposition" (good enough for me) list of steps is:

 1. Core system environment variables: `ALLUSERSPROFILE`, `ProgramData`, `PUBLIC`, `SystemDrive`, `SystemRoot`.
 2. System environment variables of type `REG_SZ`.
 3. System environment variables of type `REG_EXPAND_SZ`.
 4. Core user environment variables: `APPDATA`, `COMPUTERNAME`, `LOCALAPPDATA`, `ProgramFiles`, `USERPROFILE`.
 5. User environment variables of type `REG_SZ`.
 6. User environment variables of type `REG_EXPAND_SZ`.
 7. Account environment variables: `USERDNSDOMAIN`, `USERDOMAIN`, `USERNAME`.

> "There is a bonus special rule for the `PATH` environment variable: The User definition of the `PATH` environment variable is appended to the System definition, rather than replacing it."

Which leads to this word of caution:

> "If you have a `REG_EXPAND_SZ` between variables at the same step, it is unspecified whether the expansion is the old value or the new value, so don’t do that."

I would further add: there are loads of dodgy "install scripts" and such out there that do things like "hey I need to update an environment variable; I'll just take my current in-memory (fully expanded!) value and jam it back into the registry", without regard to whether certain values have significant, special runtime modifications (as with [`PSModulePath`](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_psmodulepath)), and *without regard to whether things were `REG_EXPAND_SZ` values or not* (so they may end up whacking your carefully constructed environment-variable-relative-based scheme). So be careful trying to use such tactics--realize that once you've set it up, you'd best not change the value of the "base" variable, because people may have expanded it out behind your back.
