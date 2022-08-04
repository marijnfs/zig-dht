# TODO:

> Refactor
  > There are probably still to many layers in communication, e.g. envelope etc

> Good first apps:
  > Library of Alexandria (Mouseion)
    > All public books, there must be a collection somewhere
    > The goal was to make copies of all written text over the world
      > Users will be able to add, perhaps in a part separated from the library directly.
  > Wikipedia copy
  > Public Square
  > Common AI
    > AI for the commons
    > Could be a language model on e.g. Alexandria
    > Could also simply be a paper sharing place initially.
  
> In bitcoind, there is a:
  > request queue
  > requested queue
  > If replies are not requested, they could be seen as announced
  > there are a few datastructures, like latest block, and blocks self-verified but not chained yet, etc
> They only sync from one node, if it stops things get reset and a we start again

> ID from recieved message is now used to store in routing
  > This is actually not true of course when it's a routed message! 
  > We need a small layer or append for every message where the actual send id is added
  > This could also be used for authentication?

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
