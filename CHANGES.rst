Development Changelog
'''''''''''''''''''''

**NB:** The changelog for releases can be found at: https://tezos.gitlab.io/CHANGES.html


This file lists the changes added to each version of tezos-node,
tezos-client, and the other Octez executables. The changes to the economic
protocol are documented in the ``docs/protocols/`` directory; in
particular in ``docs/protocols/alpha.rst``.

When you make a commit on master, you can add an item in one of the
following subsections (node, client, …) to document your commit or the
set of related commits. This will ensure that this change is not
forgotten in the final changelog, which can be found in ``docs/CHANGES.rst``.
By having your commits update this file you also make it easy to find the
commits which are related to your changes using ``git log -p -- CHANGES.rst``.
Relevant items are moved to ``docs/CHANGES.rst`` after each release.

Only describe changes which affect users (bug fixes and new features),
or which will affect users in the future (deprecated features),
not refactorings or tests. Changes to the documentation do not need to
be documented here either.

Node
----

- Add a field ``dal`` in the node's configuration file. This field is
  for a feature which is being developed and should not be
  modified. It should be used only for testing.

- Fixed a bug in the p2p layer that prevented a fast regulation of the
  number of connections (when having too few or too many connections)

- Improved the octez store merging mechanism performed on each new
  cycle. The node's memory consumption should not differ from a normal
  usage where, in the past, it could take up to several gigabytes of
  memory to perform a store merge. It also takes less time to perform
  a merge and shouldn't impact normal node operations as much as it
  previously did; especially on light architectures.

- Added support for ``level..level`` range parameters in the replay command.

- Breaking change: Node events using a legacy logging system and are migrated to
  the actual one. Impacted events are in the following sections:
  ``validator.chain``, ``validator.peer``, ``prevalidator`` and
  ``validator.block``. Section ``node.chain_validator`` is merged into
  ``validator.chain`` for consistency reasons. Those events see their JSON
  reprensentation shorter, with no duplicated information. e.g.
  ``validator.peer`` events were named ``validator.peer.v0`` at top-level and
  had an ``event`` field with a ``name`` field containing the actual event name,
  for example ``validating_new_branch``. Now, the event is called
  ``validating_new_branch.v0`` at top-level and contains a ``section`` field
  with ``validator`` and ``peer``.


Client
------

- Simulation returns correct errors on batches of operations where some are
  backtracked, failed and/or skipped.

Accuser
-------

Signer
------

Proxy Server
------------

Protocol Compiler And Environment
---------------------------------

Codec
-----

Docker Images
-------------

Rollups
-------

Miscellaneous
-------------
