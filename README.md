# "p", the Pants wrapper

Fair disclaimer: there _could not be_ anything more "work in progress" than
this. Still I already find this useful so I'm hoping other folks do as well,
and it is with that hope that I'm writing this.

## What does this do?

`p` is a Pants2 auto-complete script as well as a wrapper for pants that
allows specifying cwd-relative (as opposed to repo-root relative) targets.

`p` completes global options, goal names, goal-specific option names, and
relative, absolute and `//`-form target names.

An example, worth ~1K words:

``` bash
~ $ cd my_repo/utils
~/my_repo/utils $ p test :
/Users/calius/my_repo/pants test utils:
19:18:19.73 [INFO] Completed: Run Pytest - utils/tests/test_iter_utils.py:../tests succeeded.

✓ utils/tests/test_iter_utils.py:../tests succeeded in 0.47s (memoized).
```

Instead of invoking `./pants test utils:` from the repo root (`~/my_repo`)
we instead invoked `p test :` from `utils/`. What `p` did was translate `:`
into `utils:` for us and then invoke `pants` from the repo root. For good
measure `p` starts by writing the full command it runs:

`/Users/calius/my_repo/pants test utils:`

Another example, this time worth (32 << 5) words:

``` bash
~/my_repo/utils $ p t<TAB>
tailor  test
~/my_repo/utils $ p test :<TAB>
lib    tests
~/my_repo/utils $ p test :l<TAB>
~/my_repo/utils $ p test :lib
```

And also:

``` bash
~/my_repo/utils $ p --co<TAB>
--colors                 --loop                   --no-process-cleanup     --remote-cache-write
--concurrent             --no-colors              --no-remote-cache-read   --remote-execution
--dynamic-ui             --no-concurrent          --no-remote-cache-write  --spec-files
--dynamic-ui-renderer    --no-dynamic-ui          --no-remote-execution    --tag
--exclude-target-regexp  --no-local-cache         --pantsd
--level                  --no-loop                --process-cleanup
--local-cache            --no-pantsd              --remote-cache-read
~/my_repo/utils $ p test --<TAB>
--debug             --force             --no-force          --no-use-coverage   --output
--extra-env-vars    --no-debug          --no-open-coverage  --open-coverage     --use-coverage
```

So `p` completes context-specific as well as global options.

## Installing

place the single file `p` somewhere in your `PATH` (make sure to `chmod +x p`),
and add the following to your `.bashrc`:

``` bash
complete -o default -C p p
```

(obviously if you want to test it in the same shell session you'll need a
one-time `source ~/.bashrc`)

## Hacking configutaion

Look inside `p` to set `COMPLETE_GOAL`, `COMPLETE_OPTIONS`,
`COMPLETE_ADVANCED_OPTIONS` and `COMPLETE_TARGETS`. (see below for why you might
want to edit those)

These will eventually, obviously, move to env / some-rc-file.

## Completing goal names

Each specific repo may have a different pants configuration, and thus may have
different goals available. The way `p` knows which goals are available in your
specific repo is by invoking `pants help-all` from the repo root and parsing
the output. This is unfortunately sometimes noticeable. I have some thoughts
about how to make this a smooth experience, but before implementing any I would
love some feedback. I am currently thinking of:

* cache the result and only re-run every X hours
* current invocation uses cached results, but also spawns an "update cache"
  process, which will benefit the next invocation (the next time you press TAB).
* only invoke `pants help-all` if a goal isn't specified
  (or more precisely: something that _looks_ like a goal; `p` won't be able to
  tell for sure)
* disable goal name completion altogether; people may just not use it much (?)

## Completion TODO

`p` could try to be smart about which target names to offer when completing
target names. E.g. `p` might only propose binary targets if what you typed
so far is `p run :` and then pressed TAB.
