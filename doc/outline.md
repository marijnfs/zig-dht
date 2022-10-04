Zig Dht Outline
===============
This document contains the overview outline describing the working elements of this software.

Guid Centric API
================
Perhaps guid centric API makes finding resources easier

Jobs
====
Main organising element, being worked on sequentially by a main event loop.
This avoids race conditions.

Smaller event loops can be used in future to improve performance if that resource can be separated.

- Jobs needs to be scheduled from different places, often by another job.
- A lot of state is presented in the scheduled job. Jobs contain various information, stored in union(enum).

Memory management
=================
Memory management is done by a main allocator (currently a simple page allocator).

Serialisation
=============
We implement serialisation code that uses the allocator to encode/decode pointers/variable arrays.

Connection Management
=====================
- Used to have TCP which was a mess, now much easier with UDP

