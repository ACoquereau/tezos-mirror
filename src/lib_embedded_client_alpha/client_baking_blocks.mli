(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

type block_info = {
  hash: Block_hash.t ;
  net_id: Net_id.t ;
  predecessor: Block_hash.t ;
  fitness: MBytes.t list ;
  timestamp: Time.t ;
  protocol: Protocol_hash.t ;
  level: Level.t ;
}

val info:
  #Client_rpcs.ctxt ->
  ?include_ops:bool -> Client_node_rpcs.Blocks.block -> block_info tzresult Lwt.t

val compare:
  block_info -> block_info -> int

val monitor:
  #Client_rpcs.ctxt ->
  ?include_ops:bool -> ?length:int -> ?heads:Block_hash.t list ->
  ?delay:int -> ?min_date:Time.t -> ?min_heads:int ->
  ?compare:(block_info -> block_info -> int) ->
  unit -> block_info list tzresult Lwt_stream.t tzresult Lwt.t

val blocks_from_cycle:
  #Client_rpcs.ctxt ->
  Client_node_rpcs.Blocks.block ->
  Cycle.t ->
  Block_hash.t list tzresult Lwt.t
