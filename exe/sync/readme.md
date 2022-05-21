# Sync

Simple application to sync data across devices.

param should be a path

path gets indexed in blob tree

param should be a db

blob tree goes in db, gets synced across devices

how to get data out?




bloom filter set reconciliation

# Master tree node
Structure will have a master tree node like cereal sync
DB doesn't have a place to store this yet.

Could create 'private' blobs, where hash is rand prefix (ID) + url like 'a30ax/root'.
Prefix can then be hard set in an application, and blobs can be queried.
Could also function with indirection, i.e. ID is stored in blob, and that is queried again.
This keeps versioning instead of overwriting.



# API
./sync -p port -a addaddress -d /db/path -i /import/path

or

interactive shell:
./sync -p port -a addaddress -d /db/path
> i path #import path
> p #list peers or whatever
