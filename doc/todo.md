# TODO:

> Most finger table issues resolved:
  > todo, n_active_connections needs to query routing for active connections
  > This requires __heartbeats__
  > Heartbeats are important for general connection healing / recovery

> Create priority job queue
> Reenable crypto seed init (segfaults now, known zig issue)
> Extract smiley app from backend
  > Make broadcast / direct message api, then app interprets payload itself
  > Make job queue general so you can supply a struct
  > Create separate job queue for drawing, app logic


# Next: (small) steps selected with priority to make progress.
