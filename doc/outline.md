Zig Dht Outline
===============
This document contains the overview outline describing the working elements of this software.



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
We use Zig's net implementation, which allows for async reading and writing of sockets.

Server is implemented with a stream server, which has a reader and writer.
- It listens on a local address (like 127.0.0.1:port)
- Then accepts a connection, which returns a connection.
- This connection has a stream with reader and writer.


Client is a stream.
- Uses (try) tcpConnectToAddress to connect.
- returns a Stream.
- Can read and write on stream.

# Failures
On connection errors while connecting, try will return an error.
On connection errors during operation, the send/recv will return an error.

The error is communicated by changing the state of the connection.

# Running

Server and connection tasks continuously accept / read in a thread:
- Server -> accept
- Inbound connection -> read
- Outbound connection -> read

The writing to connections are done in a job.

Memory / Logging
================
Because we deal with external connections, we need a solid way of recording issues with connecting/ misbehaviours. Detect internal and external errors etc.

Logging is the main way to do this. We will define a simple standard logging system.