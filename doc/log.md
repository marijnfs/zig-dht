
[log]
[apr 10 2022]
Reorganised a bunch of code, putting things into place. Seems to really help the overview.

> Plan
Planning to create some event loop with queue items for Tasks that stay longer. Like retrieving a file / tree / perform search for you or others. Queue items can be priority queue where time distance is used to determine order. 
When sending query, you time out at some point for a checkup.
If message comes before that, the new message can be put on inbox and a Priorization move can push the corresponding reader to the front.

Tasks can have state, like times tried etc; to determine what is to be done.
Could also call them 'bots' or state machine.

[sep 14 2021]
Got confused by source_id in both Message and Content, only set one of them. Thent the reply send to the unset source_id and everything failed.
Should have used debugger earlier.
Already was annoyed by two source_id's before, should remove it; don't use two variables for one thing.

added format for connection (didn't print properly yet)