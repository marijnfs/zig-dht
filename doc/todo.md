# TODO:

> In bitcoind, there is a:
  > request queue
  > requested queue
  > If replies are not requested, they could be seen as announced
  > there are a few datastructures, like latest block, and blocks self-verified but not chained yet, etc
> They only sync from one node, if it stops things get reset and a we start again


> Most finger table issues resolved:
  > todo, n_active_connections needs to query routing for active connections
  > This requires __heartbeats__
  > Heartbeats are important for general connection healing / recovery

> Create priority job queue
 > Start is zig-bot
> Reenable crypto seed init (segfaults now, known zig issue)
> Extract smiley app from backend
  > Create separate job queue for drawing, app logic


# Next: (small) steps selected with priority to make progress.
