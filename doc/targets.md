# Summary
Targets are functional programs that have a direct usecase. Some have follow-ups denoted by >

# Targets
- Attack mitigation
  - Sync set: 
    - people can just bombard with set addition, there is no limit
    - a lot of transactions can be normal speedy operation, or attack.
        
- Sync set
  Keep a set in sync across nodes, any node can add to set (no security)
  > Sequence Set
    - Set with sequence number + operands. Set + operations -> next set + hash of previous set, new set, transaction.
    - Nodes can communicate their latest number / hash power and provide proof. Other nodes can verify and keep to sync with the latest.
    - Largest number wins, or most hash power wins
      - operands: add/delete, can use an efficient hash! (Utreexo)
    - Operations can be more restricted, and involve signatures (Eltoo!)
      - Anyone can start from the root-tree with a new commitment transaction, money+rules can be initiated there.
    - Sync protocol:
      Bloom filters, but applied smartly
      - Filters on active set
        - Every connection has a bloom set (number of blooms determined by size of set, nonces kept in sync with each connection).
         - Syncing happens by:
           - periodically communicating set size + hash
           - then communicating blooms (in sync request + reply dance)
           - either side could omit blooms for some reason
           - During sync 
      - Bloom filter 
      - Most of the set will be old
        - Old set gets pruned in pruning ritual
        - Oldest propertion gets moved to archive (meaning not acquired, assumed to be stored by users)
        - Old transactions can be updated with a proof for Utreexo and then spent (proof and spend can be compressed)
    
- Crypto Currency
  - Sync set implements a lot of a crypto currency
  - Based on that a good protocol should be built
  - Ideally, implemented in an independent API, that uses general sets
  - Can be a largest set protocol, with minimum time between blocks
    - only allow clocks within your time + delta.
    - People stay away from delta, best target clock + sync_time == time + delta.
    - Ideally protocol is not that competitive, because you can easily collect hashes using a O(k) collection strategy. K is something reasonable. people are happy to do shared mining.
    - People are incouraged to include other hashes. Perhaps hashes need to contain a specific.
    - Hashing: 
      - Everyone keeps lowest hash they get till time limit.
      - Start emitting collective hash at time limit (1minute?) (estimated hash seconds can be used for verification).
      - emit before to synchronise, new transaction have a time stamp and will have to commit to a time.
        - which transactions do you still accept collectively
          > hard question. People should be on the safe side.
            - After time + delta > stop accepting payment requests
              - Still accept set
            - After time + delta * 2
              - Disaccordance rules, start paying more attention to hash count
              - When in doubt, hash count should win.
                - As long as verified
    
