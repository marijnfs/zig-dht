# TODO:
> After resolution; do we need incoming/outgoing distingtion
> Find some resolution to combine InConnection and OutConnection
> Create priority job queue
> Reenable crypto seed init (segfaults now, known zig issue)
> Extract smiley app from backend
  > Make broadcast / direct message api, then app interprets payload itself
  > Make job queue general so you can supply a struct
  > Create separate job queue for drawing, app logic
> Join functionality into Server, which will be the main API
	> Will also manage the Fingertable, Timers, Job loop
	> Will have broadcast and send
	> registers the callbacks for receiving messages (direct/broadcast)

# Next: (small) steps selected with priority to make progress.
