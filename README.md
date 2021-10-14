# pgagent_add_job

Adds a simple command line API for pgagent

e.g.

* SELECT pgagent.remove_job('reindex');
* SELECT pgagent.add_job('reindex', '15 0 * * *', 'reindex database postgres');

SQL script - no binary component.

Assumes that pgagent is already installed.

Released under The PostgreSQL Licence
Copyright EnterpriseDB Inc. 2021
