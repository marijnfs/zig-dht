# TODO:

> Finger table has issues
  > does get closest get the base id, or stored id
  > this undefinedness causes issues in the finger table implementation
  > e.g. when updating a new id, get's the value id, not internal id, this returns 0 in beginning and update commands fail etc.
  > Need a clear API distinction

> Create priority job queue
> Reenable crypto seed init (segfaults now, known zig issue)
> Extract smiley app from backend
  > Make broadcast / direct message api, then app interprets payload itself
  > Make job queue general so you can supply a struct
  > Create separate job queue for drawing, app logic

# Next: (small) steps selected with priority to make progress.
